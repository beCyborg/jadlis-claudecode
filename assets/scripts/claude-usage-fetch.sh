#!/bin/sh
# claude-usage-fetch.sh — ЕДИНСТВЕННЫЙ процесс, которому разрешён curl к
# https://api.anthropic.com/api/oauth/usage. Один кэш на аккаунт, общий backoff и
# бюджет попыток (≤MAX_PER_HOUR в час): эндпоинт банит на час (429, retry-after 3600),
# и три независимых потребителя (statusline, тик снапшота, гейт ритуалов) до 05.09.2026
# складывали свои запросы и дожигали окно даже под баном.
#
# Потребители:
#   statusline-command.sh      → refresh --config-dir … --caller statusline --max-age 900
#   jadlis-usage-snapshot.sh   → sync --acct X --caller tick --max-age 1500 --format json
#   jadlis-ritual-ensure.sh    → sync --acct X --caller gate --max-age 900 --stale-ok 3600
#                                     --priority high --format gate
#                                (gate = "<seven10> <five10> <status> <reset_epoch>", с 10.09.2026
#                                 reset_epoch — ближайший недельный сброс, 0 если неизвестен)
#
# CLI:
#   env     <sel>                         # печатает CUF_SLUG/CUF_TAG/CUF_CACHE/CUF_BACKOFF/CUF_CFG для eval
#   refresh <sel> [--caller X] [--max-age N]            # без ожидания лока, без вывода; вызывать с `&`
#   sync    <sel> [--caller X] [--max-age N] [--stale-ok S] [--priority high]
#                 [--timeout T] [--format json|gate]    # ждёт лок ≤10 с, печатает результат
#   state   <sel> [--field age|backoff_left|budget_left|hist]
#   hold    <sel> <sec>                   # общий стоп-кран: молчать всем потребителям <sec> секунд
#   clear   <sel>                         # снять backoff и серию 429
# <sel> = --acct A|B | --config-dir <dir> (пусто или $HOME/.claude → A/default).
#
# Файлы на аккаунт в $CUF_HOME (по умолчанию ~/.claude/statusline-cache/):
#   usage-<slug>.json      {schema:1, acct, fetched_at, http, via, usage:<полное тело>, fable}
#                          перезапись только на 200 + числовой five_hour.utilization;
#                          без weekly_scoped в теле — старый fable сохраняется
#   usage-<slug>.lock      mkdir-лок single-flight, pid внутри, протухает через 90 с
#   usage-<slug>.backoff   epoch «молчать до» (429/ошибки/hold)
#   usage-<slug>.hist      epoch'и попыток (хвост 20) — локальная модель серверного окна
#   usage-<slug>.streak429 длина серии подряд идущих 429 (×2 к backoff)
#   fetch.log              ts slug http retry_after ms caller reason req_id budget_left age
#   429-headers.log        все заголовки каждого 429 — материал для калибровки лимита
#
# Дополнительный бесплатный источник: cachedUsageUtilization в .claude.json профиля —
# CC пишет его после удачного /usage пользователя; если свежее нашего кэша — берём без запроса.
#
# Тест-хуки (без сети): CUF_TEST_HTTP=<код> CUF_TEST_RETRY=<сек> CUF_TEST_BODY=<файл>
# (алиасы SL_TEST_*), CUF_NOW=<epoch> подменяет время, CUF_HOME=<dir> — каталог кэша.
# Все ветки завершаются exit 0: ни рендер statusline, ни ритуал уронить нельзя.

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

URL="https://api.anthropic.com/api/oauth/usage"
CUF_HOME="${CUF_HOME:-$HOME/.claude/statusline-cache}"
LOG="$CUF_HOME/fetch.log"
HLOG="$CUF_HOME/429-headers.log"
NOW="${CUF_NOW:-$(date +%s)}"
TEST_HTTP="${CUF_TEST_HTTP:-${SL_TEST_HTTP:-}}"
TEST_RETRY="${CUF_TEST_RETRY:-${SL_TEST_RETRY:-}}"
TEST_BODY="${CUF_TEST_BODY:-${SL_TEST_BODY:-}}"

CMD="${1:-}"
[ $# -gt 0 ] && shift

SEL_ACCT=""; SEL_DIR=""; SEL_SET=0
CALLER=cli; MAX_AGE=900; STALE_OK=""; PRIORITY=normal; TIMEOUT=6; FORMAT=json; FIELD=""; POS=""
while [ $# -gt 0 ]; do
	case "$1" in
		--acct)       SEL_ACCT="${2:-}"; SEL_SET=1; shift 2 ;;
		--config-dir) SEL_DIR="${2:-}";  SEL_SET=1; shift 2 ;;
		--caller)     CALLER="${2:-cli}"; shift 2 ;;
		--max-age)    MAX_AGE="${2:-900}"; shift 2 ;;
		--stale-ok)   STALE_OK="${2:-}"; shift 2 ;;
		--priority)   PRIORITY="${2:-normal}"; shift 2 ;;
		--timeout)    TIMEOUT="${2:-6}"; shift 2 ;;
		--format)     FORMAT="${2:-json}"; shift 2 ;;
		--field)      FIELD="${2:-}"; shift 2 ;;
		-*)           echo "claude-usage-fetch: unknown option $1" >&2; exit 0 ;;
		*)            POS="$POS $1"; shift ;;
	esac
done
[ -n "$TEST_HTTP" ] && CALLER="${CALLER}"   # тест-режим ничем не выделяем: лог тот же

MAXPH="${CUF_MAX_PER_HOUR:-3}"
MININT="${CUF_MIN_INTERVAL:-600}"
if [ "$PRIORITY" = high ]; then
	MAXPH="${CUF_MAX_PER_HOUR:-4}"
	MININT="${CUF_MIN_INTERVAL:-120}"
fi

# ---------- профиль ----------
resolve_profile() {
	[ "$SEL_SET" = 0 ] && SEL_DIR="${CLAUDE_CONFIG_DIR:-}"
	case "$SEL_ACCT" in
		A|a) SEL_DIR="" ;;
		B|b) SEL_DIR="$HOME/.claude-B" ;;
		"")  ;;
		*)   echo "claude-usage-fetch: unknown acct $SEL_ACCT" >&2; exit 0 ;;
	esac
	# CLAUDE_CONFIG_DIR=$HOME/.claude — тоже дефолтный профиль A: его хеш (07a43917)
	# указывает на пустую Keychain-запись.
	if [ -z "$SEL_DIR" ] || [ "$SEL_DIR" = "$HOME/.claude" ]; then
		SLUG=default; KC_SVC="Claude Code-credentials"; CFG="$HOME/.claude.json"; TAG=A
	else
		SLUG=$(printf %s "$SEL_DIR" | shasum -a 256 | cut -c1-8)
		KC_SVC="Claude Code-credentials-$SLUG"; CFG="$SEL_DIR/.claude.json"
		TAG="${SEL_DIR##*.claude-}"; [ "$TAG" = "$SEL_DIR" ] && TAG="$SLUG"
	fi
	CACHE="$CUF_HOME/usage-$SLUG.json"
	LOCK="$CUF_HOME/usage-$SLUG.lock"
	BACKOFF="$CUF_HOME/usage-$SLUG.backoff"
	HIST="$CUF_HOME/usage-$SLUG.hist"
	STREAK="$CUF_HOME/usage-$SLUG.streak429"
}

# ---------- утилиты ----------
num_file() { _v=$(cat "$1" 2>/dev/null); case "$_v" in ''|*[!0-9]*) echo 0 ;; *) echo "$_v" ;; esac; }

cache_fetched_at() {
	[ -s "$CACHE" ] || { echo 0; return; }
	_fa=$(jq -r '.fetched_at // empty' "$CACHE" 2>/dev/null)
	case "$_fa" in ''|*[!0-9]*) _fa=$(stat -f %m "$CACHE" 2>/dev/null || echo 0) ;; esac
	echo "$_fa"
}
cache_age() { _fa=$(cache_fetched_at); if [ "$_fa" -gt 0 ]; then echo $(( NOW - _fa )); else echo 999999; fi; }
cache_usable() { [ -s "$CACHE" ] && jq -e '.usage.five_hour.utilization | type == "number"' "$CACHE" >/dev/null 2>&1; }
backoff_left() { _b=$(num_file "$BACKOFF"); if [ "$_b" -gt "$NOW" ]; then echo $(( _b - NOW )); else echo 0; fi; }
hist_count() {
	[ -f "$HIST" ] || { echo 0; return; }
	awk -v now="$NOW" '$1+0 >= now-3600 && $1+0 <= now {n++} END{print n+0}' "$HIST"
}
hist_last() {
	[ -f "$HIST" ] || { echo 0; return; }
	awk -v now="$NOW" '$1+0 <= now && $1+0 > m {m=$1+0} END{print m+0}' "$HIST"
}
budget_left() { _l=$(( MAXPH - $(hist_count) )); [ "$_l" -lt 0 ] && _l=0; echo "$_l"; }

# backoff — max(существующий, новый): hold не должен укорачиваться очередным 429-расчётом
set_backoff() {
	_new=$(( NOW + $1 )); _old=$(num_file "$BACKOFF")
	[ "$_old" -gt "$_new" ] && _new="$_old"
	echo "$_new" > "$BACKOFF.tmp.$$" && mv "$BACKOFF.tmp.$$" "$BACKOFF"
}

# запись кэша: только валидный JSON, старый fable сохраняем, если в новом теле нет weekly_scoped
write_cache() {
	_old=null
	[ -s "$CACHE" ] && jq -e . "$CACHE" >/dev/null 2>&1 && _old=$(cat "$CACHE")
	if printf '%s' "$1" | jq -c --argjson old "$_old" '.fable = (.fable // $old.fable // null)' \
	     > "$CACHE.tmp.$$" 2>/dev/null \
	   && jq -e '(.fetched_at|type) == "number"' "$CACHE.tmp.$$" >/dev/null 2>&1; then
		mv "$CACHE.tmp.$$" "$CACHE"
		return 0
	fi
	rm -f "$CACHE.tmp.$$"
	return 1
}

# бесплатный сид: cachedUsageUtilization из .claude.json профиля (пишет сам CC после /usage)
try_seed() {
	[ -s "$CFG" ] || return 1
	_fa=$(cache_fetched_at)
	_seed=$(jq -c --argjson fa "$_fa" --arg acct "$TAG" '
		.cachedUsageUtilization as $c
		| select($c != null
		         and (($c.fetchedAtMs|type) == "number")
		         and ($c.accountUuid == .oauthAccount.accountUuid)
		         and (($c.fetchedAtMs/1000|floor) > $fa)
		         and (($c.utilization.five_hour.utilization|type) == "number"))
		| {schema:1, acct:$acct, fetched_at:($c.fetchedAtMs/1000|floor), http:200, via:"ccseed",
		   usage:$c.utilization,
		   fable:(([$c.utilization.limits[]? | select(.kind=="weekly_scoped")][0]) // null)}' \
		"$CFG" 2>/dev/null)
	[ -n "$_seed" ] || return 1
	write_cache "$_seed"
}

HAVE_LOCK=0
acquire_lock() {   # $1 = сколько секунд ждать (0 — не ждать); лок по РЕАЛЬНЫМ часам
	_deadline=$(( $(date +%s) + ${1:-0} ))
	while :; do
		if [ -d "$LOCK" ]; then
			_lm=$(stat -f %m "$LOCK" 2>/dev/null || echo 0); _la=$(( $(date +%s) - _lm ))
			if [ "$_la" -ge 90 ] || [ "$_la" -lt 0 ]; then rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; fi
		fi
		if mkdir "$LOCK" 2>/dev/null; then echo $$ > "$LOCK/pid"; HAVE_LOCK=1; return 0; fi
		[ "$(date +%s)" -ge "$_deadline" ] && return 1
		sleep 0.2
	done
}
release_lock() {
	if [ "$HAVE_LOCK" = 1 ]; then rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null; HAVE_LOCK=0; fi
	rm -f "$R_BODY" "$R_HDR" 2>/dev/null
}
trap release_lock EXIT

rotate_logs() {
	if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 1000 ]; then
		tail -500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
	fi
	if [ -f "$HLOG" ] && [ "$(stat -f %z "$HLOG" 2>/dev/null || echo 0)" -gt 204800 ]; then
		tail -c 102400 "$HLOG" > "$HLOG.tmp" 2>/dev/null && mv "$HLOG.tmp" "$HLOG"
	fi
}
# ts slug http retry_after ms caller reason req_id budget_left age
log_line() {
	printf '%s %s %s %s %s %s %s %s %s %s\n' "$(date -u -r "$NOW" +%FT%TZ)" "$SLUG" \
		"${1:--}" "${2:--}" "${3:-0}" "$CALLER" "$4" "${5:--}" "$(budget_left)" "$(cache_age)" >> "$LOG"
	rotate_logs
}
log_skip() {   # не чаще 1/300 с на пару (slug, reason)
	_m="$CUF_HOME/.skiplog/$SLUG-$1"; mkdir -p "$CUF_HOME/.skiplog" 2>/dev/null
	if [ -f "$_m" ]; then
		_mm=$(stat -f %m "$_m" 2>/dev/null || echo 0)
		[ $(( $(date +%s) - _mm )) -lt 300 ] && return 0
	fi
	touch "$_m"
	log_line - - 0 "$1" -
}
log_429_headers() {
	{
		printf '=== %s slug=%s caller=%s retry-after=%s\n' "$(date -u -r "$NOW" +%FT%TZ)" "$SLUG" "$CALLER" "${R_RETRY:--}"
		tr -d '\r' < "$R_HDR" 2>/dev/null | grep -v '^$'
		printf 'body: '; head -c 600 "$R_BODY" 2>/dev/null; printf '\n'
	} >> "$HLOG" 2>/dev/null
}

get_token() {
	if [ -n "$TEST_HTTP" ]; then TOKEN=test; return; fi
	TOKEN=$(security find-generic-password -s "$KC_SVC" -w 2>/dev/null \
	        | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
}

do_fetch() {   # → R_HTTP R_RETRY R_MS R_REQID, тело в $R_BODY, заголовки в $R_HDR
	R_BODY="$CUF_HOME/.body-$SLUG.$$"; R_HDR="$CUF_HOME/.hdr-$SLUG.$$"
	R_HTTP=""; R_RETRY=""; R_MS=0; R_REQID=-
	if [ -n "$TEST_HTTP" ]; then
		R_HTTP="$TEST_HTTP"; R_RETRY="$TEST_RETRY"
		if [ -n "$TEST_BODY" ]; then cp "$TEST_BODY" "$R_BODY" 2>/dev/null || : > "$R_BODY"; else : > "$R_BODY"; fi
		printf 'HTTP/2 %s\r\nretry-after: %s\r\nrequest-id: req_test\r\n' "$R_HTTP" "$R_RETRY" > "$R_HDR"
		return
	fi
	_out=$(curl -s --connect-timeout 3 --max-time "$TIMEOUT" -o "$R_BODY" -D "$R_HDR" \
	       -w '%{http_code} %{time_total}' "$URL" \
	       -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)
	R_HTTP="${_out%% *}"; _tt="${_out#* }"
	R_MS=$(awk -v t="${_tt:-0}" 'BEGIN{printf "%.0f", t*1000}')
	R_RETRY=$(awk 'tolower($1)=="retry-after:"{gsub(/\r/,"",$2); print $2; exit}' "$R_HDR" 2>/dev/null)
	R_REQID=$(awk 'tolower($1)=="request-id:"{gsub(/\r/,"",$2); print $2; exit}' "$R_HDR" 2>/dev/null)
	[ -n "$R_REQID" ] || R_REQID=-
}

handle_result() {   # → FETCH_STATUS, SOURCE; кэш/backoff
	SOURCE=""
	case "$R_HTTP" in
		200)
			if jq -e '.five_hour.utilization | type == "number"' "$R_BODY" >/dev/null 2>&1; then
				_doc=$(jq -c --arg acct "$TAG" --argjson fa "$NOW" '
					{schema:1, acct:$acct, fetched_at:$fa, http:200, via:"curl", usage:.,
					 fable:(([.limits[]? | select(.kind=="weekly_scoped")][0]) // null)}' "$R_BODY" 2>/dev/null)
				if [ -n "$_doc" ] && write_cache "$_doc"; then
					rm -f "$BACKOFF" "$STREAK"; FETCH_STATUS=ok; SOURCE=live; R_RETRY=""
					return
				fi
			fi
			set_backoff 300; FETCH_STATUS=badjson; R_HTTP=badjson ;;
		429)
			_s=$(( $(num_file "$STREAK") + 1 )); echo "$_s" > "$STREAK"
			_r="$R_RETRY"; case "$_r" in ''|*[!0-9]*) _r=3600 ;; esac
			[ "$_r" -lt 60 ] && _r=60
			[ "$_r" -gt 7200 ] && _r=7200
			_i=1; while [ "$_i" -lt "$_s" ] && [ "$_r" -lt 14400 ]; do _r=$(( _r * 2 )); _i=$(( _i + 1 )); done
			[ "$_r" -gt 14400 ] && _r=14400
			_j=$(( 30 + (NOW + $$) % 61 ))          # джиттер 30–90 с: не бить ровно в границу окна
			set_backoff $(( _r + _j ))
			log_429_headers
			FETCH_STATUS=http429 ;;
		401)    set_backoff 1800; FETCH_STATUS=http401 ;;      # CC освежит токен сам
		000|"") set_backoff 300;  FETCH_STATUS=neterr ;;
		5*)     set_backoff 600;  FETCH_STATUS="http$R_HTTP" ;;
		*)      set_backoff 300;  FETCH_STATUS="http$R_HTTP" ;;
	esac
}

# ---------- sync / refresh ----------
do_sync() {   # $1 = ожидание лока (с)
	mkdir -p "$CUF_HOME" 2>/dev/null
	REASON=""; FETCH_STATUS=""; SOURCE=""; R_HTTP=""; R_RETRY=""; R_MS=0; R_REQID=-
	if cache_usable && [ "$(cache_age)" -lt "$MAX_AGE" ]; then
		REASON=skip-fresh
	elif acquire_lock "$1"; then
		try_seed && log_line 200 - 0 seed ccseed
		if cache_usable && [ "$(cache_age)" -lt "$MAX_AGE" ]; then
			REASON=skip-fresh
		elif [ "$(backoff_left)" -gt 0 ]; then
			REASON=skip-backoff
		elif [ "$(hist_count)" -ge "$MAXPH" ]; then
			REASON=skip-budget
		elif [ $(( NOW - $(hist_last) )) -lt "$MININT" ]; then
			REASON=skip-mininterval
		else
			get_token
			if [ -z "$TOKEN" ]; then
				set_backoff 300; REASON=notoken; FETCH_STATUS=notoken     # сети не было — слот не тратим
			else
				echo "$NOW" >> "$HIST"                                    # слот занят ДО curl
				tail -20 "$HIST" > "$HIST.tmp.$$" 2>/dev/null && mv "$HIST.tmp.$$" "$HIST"
				do_fetch; REASON=fetch
				handle_result
			fi
		fi
		release_lock
	else
		REASON=skip-lock
	fi
	case "$REASON" in
		fetch) log_line "$R_HTTP" "${R_RETRY:--}" "$R_MS" fetch "$R_REQID" ;;
		*)     log_skip "$REASON" ;;
	esac
	# итоговый статус: live → ok; кэш в пределах stale-ok → ok/stale по возрасту; иначе причина
	_age=$(cache_age)
	if [ "$SOURCE" = live ]; then
		STATUS=ok
	elif cache_usable && { [ -z "$STALE_OK" ] || [ "$_age" -le "$STALE_OK" ]; }; then
		SOURCE=cache
		if [ "$_age" -le "$MAX_AGE" ]; then STATUS=ok; else STATUS=stale; fi
	else
		SOURCE=none
		if [ -n "$FETCH_STATUS" ]; then STATUS="$FETCH_STATUS"
		else
			case "$REASON" in
				skip-backoff) STATUS=backoff ;; skip-budget) STATUS=budget ;;
				skip-mininterval) STATUS=mininterval ;; skip-lock) STATUS=lock ;;
				*) STATUS=nodata ;;
			esac
		fi
	fi
}

emit() {
	case "$FORMAT" in
		gate)
			# "<seven10> <five10> <status> <reset_epoch>". reset_epoch — ближайший недельный
			# сброс (.usage.seven_day.resets_at): кэш мог быть снят ДО сброса, поэтому штамп
			# докручивается вперёд шагами по 7 суток, пока не станет > NOW; нет поля/мусор → 0.
			if [ "$SOURCE" != none ]; then
				jq -r --arg st "$STATUS" --argjson now "$NOW" '
					def reset_epoch:
						(.usage.seven_day.resets_at // "") as $r
						| if ($r|type) != "string" or $r == "" then 0
						  else (try ($r | sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | fromdateiso8601) catch 0) end
						| if . <= 0 then 0 else (. + (if . > $now then 0 else ((($now - .) / 604800 | floor) + 1) * 604800 end)) end;
					"\((.usage.seven_day.utilization // 0)*10|floor) \((.usage.five_hour.utilization // 0)*10|floor) \($st) \(reset_epoch)"' \
					"$CACHE" 2>/dev/null || echo "0 0 nodata 0"
			else
				echo "0 0 $STATUS 0"
			fi ;;
		*)
			_in=null
			[ "$SOURCE" != none ] && _in=$(cat "$CACHE" 2>/dev/null)
			[ -n "$_in" ] || _in=null
			printf '%s' "$_in" | jq -c --arg source "$SOURCE" --arg reason "$REASON" --arg status "$STATUS" \
				--arg http "$R_HTTP" --arg acct "$TAG" --argjson now "$NOW" '
				(. // {}) | {source:$source, reason:$reason, status:$status,
				  http:(if $http == "" then null else $http end),
				  acct:(.acct // $acct), fetched_at:(.fetched_at // null),
				  measured_at:(if .fetched_at then (.fetched_at|todate) else null end),
				  cache_age_sec:(if .fetched_at then ($now - .fetched_at) else null end),
				  usage:(.usage // null), fable:(.fable // null)}' 2>/dev/null \
			|| printf '{"source":"none","reason":"%s","status":"%s","usage":null,"fable":null}\n' "$REASON" "$STATUS" ;;
	esac
}

# ---------- команды ----------
case "$CMD" in
	env)
		resolve_profile
		printf "CUF_SLUG='%s'; CUF_TAG='%s'; CUF_CACHE='%s'; CUF_BACKOFF='%s'; CUF_CFG='%s'\n" \
			"$SLUG" "$TAG" "$CACHE" "$BACKOFF" "$CFG" ;;
	refresh)
		resolve_profile
		do_sync 0 >/dev/null 2>&1 ;;
	sync)
		resolve_profile
		do_sync 10
		emit ;;
	state)
		resolve_profile
		_age=$(cache_age); _bl=$(backoff_left); _bu=$(budget_left); _hc=$(hist_count)
		case "$FIELD" in
			age) echo "$_age" ;; backoff_left) echo "$_bl" ;; budget_left) echo "$_bu" ;; hist) echo "$_hc" ;;
			"") echo "slug=$SLUG tag=$TAG age=$_age backoff_left=$_bl budget_left=$_bu hist=$_hc usable=$(cache_usable && echo 1 || echo 0)" ;;
			*) echo "claude-usage-fetch: unknown field $FIELD" >&2 ;;
		esac ;;
	hold)
		resolve_profile; mkdir -p "$CUF_HOME" 2>/dev/null
		_sec=$(echo "$POS" | awk '{print $1+0}')
		[ "$_sec" -gt 0 ] && { set_backoff "$_sec"; CALLER="${CALLER:-cli}"; log_line - "$_sec" 0 hold -; }
		echo "hold $TAG until $(date -r "$(num_file "$BACKOFF")" '+%H:%M:%S')" ;;
	clear)
		resolve_profile
		rm -f "$BACKOFF" "$STREAK"
		echo "cleared $TAG" ;;
	*)
		sed -n '2,25p' "$0" >&2 ;;
esac
exit 0

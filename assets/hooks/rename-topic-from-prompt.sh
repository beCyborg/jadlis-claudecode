#!/bin/bash
# UserPromptSubmit hook (SYNC): генерирует СМЫСЛОВОЙ заголовок сессии (4-6 слов,
# русский) и отдаёт его в sessionTitle (JSON stdout).
#
# Архитектура (ревизия 2026-08-11, план wise-singing-pudding; ревизии 09-09 и 09-10):
# - sessionTitle отсюда идёт путём /rename: ставит custom-title И напрямую
#   патчит Remote Control-сессию (updateBridgeSessionTitle в бинаре 2.1.227).
#   Отдельный Stop-хук с tmux send-keys больше не нужен.
# - Терминал (tmux-окно/таб) обновляет statusline-command.sh по полю
#   .session_name — прямых tmux-вызовов здесь нет (один канал, нет гонок).
# - Если в промпте упомянут файл — читаем его выжимку (frontmatter/заголовки/
#   первые абзацы) и передаём модели вместе с задачей: имя отражает СУТЬ
#   работы и материала, а не «выполнение файла».
# - Два режима генерации, TITLE_BACKEND (ревизия 2026-09-09, без платного API):
#   * native (default): для свободного промпта хук МОЛЧИТ — сессию именует
#     нативный фоновый генератор CC (haiku-слот = ANTHROPIC_DEFAULT_HAIKU_MODEL,
#     подписка; русский через language=Russian; сам синкает RC и statusline).
#     Хук ставит только мгновенные имена slash-ритуалов (мэппинг ниже) и —
#     с 2026-09-10 — headless-имена для промптов с файлом / в план-моде (слой 1).
#   * headless: `claude -p` на подписке (OAuth), литеральный id модели
#     (алиасы haiku/sonnet ремапятся env-ом в claude-opus-5-5), без settings,
#     MCP, хуков, инструментов и персистенции сессии; perl alarm как timeout
#     (timeout/gtimeout на машине нет). ~3 с стены на claude-opus-5 (замер до 22.09.2026, сейчас claude-opus-5-5).
#     Включать: TITLE_BACKEND=headless в env лаунчера; TITLE_MODEL,
#     TITLE_MAX_TIME — переопределения.
#   Старый curl в api.anthropic.com (.title-key / Keychain speak11-anthropic-key)
#   убран; ключ лежит в hooks/_archive/.title-key на случай отката.
# - ПРОВАЛ = ТИШИНА: ничего не печатаем и выходим 0 — сессию именует нативный
#   генератор CC (русский, т.к. language=Russian). Никаких untitled-*.
#
# Планы (ревизия 2026-09-10, план «Именование сессий по смыслу плана»):
# - Факт (бинарь 2.1.267): при принятии плана (любой вариант, кроме «No») CC
#   вызывает генератор ИМЕНИ сессии (`rename_generate_name`, тот же, что у
#   /rename без аргумента) на первых 1000 символах плана и пишет ai-title —
#   ASCII-слаг вида `ritual-account-reset-priority` (регексп имени ASCII-only,
#   русского имени там не будет). Guard `Tu(Y())`: если у сессии уже есть
#   CUSTOM-title (наш sessionTitle или ручной /rename) — слаг не ставится.
#   При showClearContextOnPlanAccept реализация идёт в новой сессии, первое
#   сообщение которой служебное (`Implement the following plan: …`, origin
#   auto-continuation) — нативный генератор его игнорирует, слаг остаётся.
# - Слой 1 (защита): на первом промпте с файлом ИЛИ в план-моде хук ставит
#   headless-имя сразу (custom-title → guard не даёт слагу появиться).
# - Слой 2 (имя по сути плана): на КАЖДОМ промпте, до гейтов имени, ищем
#   свежепринятый план — (а) сам промпт `Implement the following plan:`;
#   (б) хвост транскрипта: user-запись с `planContent` (clear-context) или
#   assistant-запись `ExitPlanMode` (keep-context; принят ⇔ permission_mode
#   уже не plan). Нашли новый (ключ ≠ /tmp/claude-plan-titled-$SID) →
#   headless по выжимке плана → sessionTitle, даже если имя уже есть.
#
# /goal (ревизия 2026-09-10, план «Имя сессии по сути /goal»):
# - Факт (бинарь 2.1.267): /goal — встроенная команда (local-jsx, immediate),
#   сама сессию НЕ именует. В хук приходит СЫРОЙ строкой `/goal <условие>`
#   (условие ≤500 символов; `@путь` не раскрывается — остаётся текстом);
#   `clear|stop|off|reset|none|cancel` (без учёта регистра) и пустой `/goal`
#   снимают цель. Условие хранится как сессионный Stop-хук + activeGoal;
#   служебный kickoff-промпт идёт meta-сообщением того же хода и хук не дёргает.
#   До ревизии `/goal @план.md` (один токен → AWC<2) получал имя «Goal».
# - Слой 3: `/goal <условие>` — до гейтов имени (новая цель = новое назначение
#   сессии → имя ставится ПОВЕРХ существующего, решение 10.09). collect_material
#   по условию (@путь, голый путь, [[wikilink]]) → ВСЕГДА headless с задачей
#   «Цель сессии: …» независимо от TITLE_BACKEND → sessionTitle. Пустой /goal
#   и clear-слова имя не трогают.
#
# Гейты (в порядке проверки):
# 1) CLAUDE_HOOK_RENAME_NESTED — ручной override.
# 2) env CLAUDE_CODE_SESSION_ID != .session_id → вложенная CC-сессия
#    (мост claude -p из verif/full-research) → молчим.
# —) Слой 2 (план) и слой 3 (/goal) — раньше гейтов 3–4, иначе унаследованное/
#    первое имя заблокирует переименование по плану или цели.
# 3) .session_title из stdin непуст → имя уже есть (наше с прошлого промпта,
#    ручной /rename, rename с claude.ai) → не трогаем.
#    Поле недокументировано для UserPromptSubmit, но реально приходит
#    (проверено T0 2026-08-11, v2.1.227).
#    ИСКЛЮЧЕНИЕ (ревизия 2026-09-11, слой 0): имя, УНАСЛЕДОВАННОЕ при /clear.
#    Факт (транскрипт 2.1.268): /clear заводит новый SID и копирует в него
#    custom-title + agent-name старой сессии ПЕРВЫМИ строками нового .jsonl,
#    а bridge-session (RC) остаётся тем же → на телефоне висит старое имя, и
#    нативный генератор CC молчит (guard «есть CUSTOM-title»). Признак
#    унаследованного имени: 1-я строка транскрипта = запись custom-title,
#    таких записей ровно одна (ручной /rename после /clear дописал бы вторую),
#    записей с "promptId" ≤ 1 (это первый настоящий промпт сессии).
#    Тогда гейт 3 снимается и имя генерится headless даже в native-режиме
#    (нативный путь заблокирован guard'ом) — один раз, дальше держит гейт 4.
# 4) Маркер /tmp/claude-topic-$SID — вторичный гейт на случай исчезновения
#    поля session_title в апдейте CC. Пишется ТОЛЬКО после успеха; при провале
#    счётчик попыток (макс 2), дальше сдаёмся в пользу нативного именования.
#
# Тесты: RENAME_HOOK_DEBUG=1 → лог /tmp/claude-rename-<sid>.log; TITLE_FORCE=<имя>
# подменяет headless-вызов фиксированным именем (маршрутизация без модели:
# native-тишина остаётся тишиной, slash-мэппинг остаётся мэппингом).

export LC_ALL=en_US.UTF-8   # byte-wise cut рвёт кириллицу при пустом LANG у tmux-сервера

[ -n "$CLAUDE_HOOK_RENAME_NESTED" ] && exit 0

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
PMODE=$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)
TPATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
STITLE=$(printf '%s' "$INPUT" | jq -r '.session_title // empty' 2>/dev/null)
VAULT="$HOME/Jadlis"

# Гейт вложенности: env-переменные не работают (CC переопределяет
# CLAUDE_CODE_SESSION_ID на свой SID даже для хуков вложенной сессии —
# проверено probe 2026-08-11). Зато headless-режим виден по командной строке
# CC-процесса-предка: `claude -p …` / `--print`. Идём вверх максимум 4 предка.
_pp=$PPID
for _i in 1 2 3 4; do
  [ -z "$_pp" ] || [ "$_pp" -le 1 ] 2>/dev/null && break
  _cmd=$(ps -o command= -p "$_pp" 2>/dev/null)
  case "$_cmd" in
    claude\ *|*/claude\ *|node\ *claude*)
      case " $_cmd" in *" -p "*|*" --print"*|*" -p") exit 0 ;; esac
      break ;;
  esac
  _pp=$(ps -o ppid= -p "$_pp" 2>/dev/null | tr -d ' ')
done

MARKER="/tmp/claude-topic-$SID"
TRIES="/tmp/claude-title-tries-$SID"
PLAN_MARKER="/tmp/claude-plan-titled-$SID"
PLAN_TRIES="/tmp/claude-plan-tries-$SID"

# Опциональный отладочный лог: RENAME_HOOK_DEBUG=1
DBG=""
[ -n "$RENAME_HOOK_DEBUG" ] && DBG="/tmp/claude-rename-$SID.log"
log() { [ -n "$DBG" ] && printf '%s\n' "$*" >> "$DBG" 2>/dev/null; return 0; }
log "── $(date '+%H:%M:%S') PROMPT=$(printf '%s' "$PROMPT" | head -c 300)"
log "env: CC_SID=[${CLAUDE_CODE_SESSION_ID:-}] session_title=[$STITLE] pmode=[$PMODE]"

# --- helpers ---------------------------------------------------------------
sanitize_title() {
  # первая строка; без управляющих/markdown-символов и опасных для дальнейших
  # каналов знаков (` $ ;), без ведущего «/» (иначе титул похож на slash-команду),
  # без обрамляющих кавычек и финальной точки; обрезка до 60 символов.
  printf '%s' "$1" \
    | head -1 \
    | tr -d '\000-\037\177`$;' \
    | sed -E 's/[*_#>~|]+/ /g' \
    | sed -E 's/^[[:space:]"'"'"'\/]+//; s/[[:space:]"'"'"']+$//' \
    | sed -E 's/  +/ /g; s/[.]+$//' \
    | cut -c1-60 \
    | sed -E 's/[[:space:]]+$//'
}

valid_title() {
  # $1 = sanitized title → печатает его, если он годится, иначе пусто
  case "$1" in ''|Error:*|error:*) return 0 ;; esac
  [ ${#1} -lt 4 ] && return 0
  printf '%s' "$1"
}

fail_and_maybe_giveup() {
  # $1 = причина (лог), $2 = файл счётчика, $3 = маркер, $4 = содержимое маркера.
  # 2-й провал ставит маркер: дальше эту ветку не дёргаем (native / план забыт).
  log "FAIL: $1"
  local n
  n=$(cat "$2" 2>/dev/null); n=$(( ${n:-0} + 1 ))
  printf '%s' "$n" > "$2" 2>/dev/null
  if [ "$n" -ge 2 ]; then
    printf '%s' "$4" > "$3" 2>/dev/null
    rm -f "$2" 2>/dev/null
    log "giving up after $n tries → marker $3"
  fi
  exit 0
}

emit_title() {
  # Успех: JSON. sessionTitle сам доедет до RC (путь /rename) и до терминала
  # (statusline-синк по .session_name). Вне tmux — ещё и OSC-заголовок.
  if [ -z "$TMUX" ]; then
    local seq
    seq=$(printf '\033]2;%s\007\033]1;%s\007' "$1" "$1")
    jq -nc --arg t "$1" --arg s "$seq" \
      '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", sessionTitle:$t}, terminalSequence:$s}'
  else
    jq -nc --arg t "$1" \
      '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", sessionTitle:$t}}'
  fi
}

digest_text() {
  # stdin → выжимка: frontmatter title/description → заголовки (≤3) → первые
  # абзацы, без кода; $1 = лимит символов (default 600). Ведущие пустые строки
  # снимаются, чтобы frontmatter распознавался и у inline-плана.
  head -c 20000 | awk 'NF{f=1} f' | awk '
    BEGIN { fm=0; fence=0; heads=0; paras=0; buf="" }
    NR==1 && $0=="---" { fm=1; next }
    fm==1 { if ($0=="---") { fm=2; next }
            if ($0 ~ /^(title|description):/) print $0
            next }
    /^```/ { fence=!fence; next }
    fence { next }
    /^#{1,3} / { if (heads<3) { print $0; heads++ }; next }
    /^[[:space:]]*$/ { if (buf!="") { print buf; buf=""; paras++ }; next }
    paras<3 { buf = (buf=="" ? $0 : buf" "$0) }
    END { if (buf!="" && paras<3) print buf }
  ' | head -c "${1:-600}"
}

# --- сбор материала из упомянутых файлов -----------------------------------
# Кандидаты (юникод-safe, LC_ALL уже UTF-8):
#  a) @-меншены CC (пробелы экранированы «\ »),
#  b) пути в двойных/одинарных кавычках,
#  c) голые токены с известным расширением,
#  d) [[wikilink]] (до «|» и «#»; без расширения → «.md»).
# Резолв: абсолютный / ~/ / относительно cwd / относительно корня vault;
# голое имя без «/» (wikilink) — папки планов, затем первый файл с таким
# именем в vault (одноимённые заметки → может взяться не та; ломается только
# качество имени).
# MATERIAL_KIND=plan, если файл лежит в папке планов или frontmatter `type: plan`.
MATERIAL=''
MATERIAL_KIND=''
collect_material() {
  local raw candidates p full count=0 digest
  raw=$(printf '%s' "$PROMPT" | head -c 4000)
  candidates=$(
    {
      printf '%s\n' "$raw" | grep -oE '@[^[:space:]]+([\\][ ][^[:space:]]*)*' | sed 's/^@//; s/\\ / /g'
      printf '%s\n' "$raw" | grep -oE '"[^"]+\.(md|txt|json|ya?ml|py|ts|js|sh|canvas|base)"' | tr -d '"'
      printf '%s\n' "$raw" | grep -oE "'[^']+\.(md|txt|json|ya?ml|py|ts|js|sh|canvas|base)'" | tr -d "'"
      printf '%s\n' "$raw" | grep -oE '[^[:space:]"'"'"']+\.(md|txt|json|ya?ml|py|ts|js|sh|canvas|base)'
      printf '%s\n' "$raw" | grep -oE '\[\[[^]|#]+' | sed -E 's/^\[\[[[:space:]]*//; s/[[:space:]]+$//' \
        | awk '$0!="" { if ($0 !~ /\.(md|txt|json|ya?ml|py|ts|js|sh|canvas|base)$/) $0=$0".md"; print }'
    } | awk '!seen[$0]++' | head -6
  )
  [ -z "$candidates" ] && return 0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    full=''
    case "$p" in
      /*)  [ -f "$p" ] && full="$p" ;;
      '~/'*) [ -f "$HOME/${p#\~/}" ] && full="$HOME/${p#\~/}" ;;
      *)
        if   [ -n "$CWD" ] && [ -f "$CWD/$p" ]; then full="$CWD/$p"
        elif [ -f "$VAULT/$p" ]; then full="$VAULT/$p"
        elif [ "${p##*/}" = "$p" ]; then
          # голое имя (wikilink): папки планов → первый файл с таким именем в vault
          if   [ -f "$VAULT/Система/Планы/$p" ]; then full="$VAULT/Система/Планы/$p"
          elif [ -f "$HOME/.claude/plans/$p" ]; then full="$HOME/.claude/plans/$p"
          else full=$(find "$VAULT" -type f -name "$p" -not -path '*/.*' -print -quit 2>/dev/null)
          fi
        fi ;;
    esac
    [ -z "$full" ] && continue
    case "$full" in
      "$VAULT/Система/Планы/"*|"$HOME/.claude/plans/"*) MATERIAL_KIND=plan ;;
      *) head -20 "$full" 2>/dev/null | grep -qE '^type:[[:space:]]*plan[[:space:]]*$' && MATERIAL_KIND=plan ;;
    esac
    digest=$(digest_text 600 < "$full" 2>/dev/null)
    if [ -n "$digest" ]; then
      MATERIAL="${MATERIAL}=== $(basename "$full")
${digest}

"
      count=$((count+1)); [ "$count" -ge 2 ] && break
    fi
  done <<< "$candidates"
  MATERIAL=$(printf '%s' "$MATERIAL" | head -c 1200)
  [ -n "$MATERIAL" ] && log "material: $count file(s), kind=[${MATERIAL_KIND}], $(printf '%s' "$MATERIAL" | wc -c | tr -d ' ') chars"
  return 0
}

# --- описание вызванного скилла (слой 4, 2026-10-03) ------------------------
# $1 = имя команды без «/» (`plugin:skill` или `skill`) → stdout «/имя — описание»
# (≤600 символов) или пусто, если файл скилла/команды не найден (встроенные
# команды CC: /advisor, /model, … — их именует нативный генератор).
# Поиск: проект ($CWD/.claude) → ~/.claude → установленные плагины профиля
# (installed_plugins.json; при `plugin:` — только этот плагин).
# Описание: frontmatter `description:` (строкой или блоком `>`/`|`), хвост
# с триггерами и «Do NOT» отрезается — для имени это шум.
skill_description() {
  local cmd="$1" plugin='' name="$1" f='' p d
  case "$cmd" in *:*) plugin=${cmd%%:*}; name=${cmd##*:} ;; esac
  [ -n "$name" ] || return 0
  if [ -z "$plugin" ]; then
    for p in "$CWD/.claude/skills/$name/SKILL.md" "$CWD/.claude/commands/$name.md" \
             "$HOME/.claude/skills/$name/SKILL.md" "$HOME/.claude/commands/$name.md"; do
      [ -n "$CWD" ] || case "$p" in /.claude/*) continue ;; esac
      [ -f "$p" ] && { f=$p; break; }
    done
  fi
  if [ -z "$f" ]; then
    local ip="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
    [ -f "$ip" ] || ip="$HOME/.claude-B/plugins/installed_plugins.json"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      for p in "$d/skills/$name/SKILL.md" "$d/commands/$name.md"; do
        [ -f "$p" ] && { f=$p; break 2; }
      done
    done < <(jq -r --arg pl "$plugin" '.plugins // {} | to_entries[]
               | select($pl == "" or (.key | startswith($pl + "@")))
               | .value[]?.installPath // empty' "$ip" 2>/dev/null)
  fi
  [ -n "$f" ] || return 0
  d=$(head -80 "$f" 2>/dev/null | awk '
    NR==1 { if ($0 != "---") exit; next }
    /^---[[:space:]]*$/ { exit }
    blk { if ($0 ~ /^[[:space:]]/ || $0 == "") { sub(/^[[:space:]]+/, ""); out = out " " $0; next } else exit }
    /^description:/ {
      v = $0; sub(/^description:[[:space:]]*/, "", v)
      if (v ~ /^[>|][-+]?[[:space:]]*$/ || v == "") { blk = 1; next }
      gsub(/^["'"'"']|["'"'"']$/, "", v); out = v; exit
    }
    END { print out }' \
    | sed -E 's/(English triggers|RU triggers|Russian triggers|Triggers|Триггеры|TRIGGER when|Do NOT|DO NOT|Invoke via)[: ].*$//' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | cut -c1-600)
  # Нет description (команда-гайд вроде ~/.claude/commands/twitter.md) →
  # заголовок + первый абзац тела.
  [ -n "$d" ] || d=$(digest_text 400 < "$f" 2>/dev/null | tr '\n' ' ' \
                     | sed -E 's/[*`#]+//g; s/[[:space:]]+/ /g; s/^ //; s/ $//')
  [ -n "$d" ] || return 0
  log "skill: /$cmd → $f ($(printf '%s' "$d" | wc -c | tr -d ' ') chars)"
  printf '/%s — %s' "$cmd" "$d"
}

# --- поиск свежепринятого плана (слой 2) -----------------------------------
# Результат: PLAN_TEXT (выжимка ≤1200), PLAN_KEY (cksum текста без пробелов —
# одинаков для inline-промпта и planContent того же плана), PLAN_SRC (лог).
PLAN_TEXT=''; PLAN_KEY=''; PLAN_SRC=''
plan_source() {
  local body='' rec pf
  case "$PROMPT" in
    'Implement the following plan:'*)
      body=${PROMPT#Implement the following plan:}
      body=${body%%If you need specific details from before exiting plan mode*}
      body=${body%%User feedback on this plan:*}
      PLAN_SRC=inline
      ;;
    *)
      [ -n "$TPATH" ] && [ -f "$TPATH" ] || return 1
      rec=$(tail -c 3000000 "$TPATH" 2>/dev/null \
            | command grep -e '"planContent":' -e '"name":"ExitPlanMode"' | tail -1)
      [ -z "$rec" ] && return 1
      body=$(printf '%s' "$rec" | jq -r '.planContent // empty' 2>/dev/null)
      if [ -n "$body" ]; then
        PLAN_SRC=transcript-planContent
      else
        # ExitPlanMode: принят ⇔ сессия уже не в план-моде (при отказе остаётся).
        if [ "$PMODE" = plan ]; then
          log "plan: ExitPlanMode in transcript, but still in plan mode → not accepted"
          return 1
        fi
        body=$(printf '%s' "$rec" | jq -r '[.message.content[]? | select(type=="object" and .type=="tool_use" and .name=="ExitPlanMode") | .input.plan // empty] | last // empty' 2>/dev/null)
        PLAN_SRC=transcript-ExitPlanMode
        if [ -z "$body" ]; then
          pf=$(tail -c 3000000 "$TPATH" 2>/dev/null | command grep -o '"planFilePath":"[^"]*"' \
               | tail -1 | sed 's/^"planFilePath":"//; s/"$//')
          if [ -n "$pf" ] && [ -f "$pf" ]; then
            body=$(head -c 20000 "$pf" 2>/dev/null); PLAN_SRC=transcript-planFile
          fi
        fi
      fi
      ;;
  esac
  [ -z "$(printf '%s' "$body" | tr -d '[:space:]' | head -c 1)" ] && return 1
  PLAN_KEY=$(printf '%s' "$body" | tr -d '[:space:]' | head -c 3000 | cksum | cut -d' ' -f1)
  if [ "$(cat "$PLAN_MARKER" 2>/dev/null)" = "$PLAN_KEY" ]; then
    log "plan: src=$PLAN_SRC key=$PLAN_KEY already titled → skip"
    return 1
  fi
  PLAN_TEXT=$(printf '%s\n' "$body" | digest_text 1200)
  [ -z "$PLAN_TEXT" ] && return 1
  log "plan: src=$PLAN_SRC key=$PLAN_KEY digest=$(printf '%s' "$PLAN_TEXT" | wc -c | tr -d ' ') chars"
  return 0
}

# --- headless-вызов: делегируем общему генератору ----------------------------
# Системный промпт и модель живут в ~/.claude/scripts/session-title.sh (вынесен
# 17.09.2026). Таймаут вызова модели ОБЯЗАН быть меньше timeout хука в
# settings.json (UserPromptSubmit → 20 с): иначе CC снимает хук раньше alarm и
# прогон модели тратится впустую. 14 с модели + ~1–3 с на jq/поиск материала.
TITLE_MAX_TIME="${TITLE_MAX_TIME:-14}"
headless_title() {
  local out
  out=$(TITLE_MAX_TIME="$TITLE_MAX_TIME" /bin/sh "$HOME/.claude/scripts/session-title.sh" "$1" "$2" "$3" "$4" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$out" ]; then
    log "headless failed (session-title.sh)"
    return 1
  fi
  log "headless raw=$out"
  printf '%s' "$out"
}

gen_title() {
  # $1 задача, $2 материал, $3 kind (plan|''), $4 скилл. TITLE_FORCE — тестовая подмена модели.
  if [ -n "$TITLE_FORCE" ]; then
    log "TITLE_FORCE → [$TITLE_FORCE] (task=$(printf '%s' "$1" | head -c 60)… material=$(printf '%s' "$2" | wc -c | tr -d ' ') chars kind=[$3] skill=$(printf '%s' "$4" | wc -c | tr -d ' ') chars)"
    printf '%s' "$TITLE_FORCE"; return 0
  fi
  headless_title "$1" "$2" "$3" "$4"
}

# --- гейт пульта: дежурную сессию jadlis-manager-B не переименовываем --------
# Имя пульта фиксированное (cld-spawn.sh --spawner). Слои 2/3/0 ставят имя ПОВЕРХ
# существующего (план, /goal, /clear) и затирали его. Признак — имя tmux-сессии;
# если имя уже съехало — возвращаем. (2026-09-20; пульт A убран 30.09.2026)
if [ -n "$TMUX" ]; then
  _tmux=$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)
  case "$("$_tmux" display-message -p ${TMUX_PANE:+-t "$TMUX_PANE"} '#S' 2>/dev/null)" in
    jadlis-manager-B) MGR_TITLE='Менеджер сессии B' ;;
    *)                MGR_TITLE='' ;;
  esac
  if [ -n "$MGR_TITLE" ]; then
    log "manager session → fixed title [$MGR_TITLE] (was [$STITLE])"
    [ "$STITLE" = "$MGR_TITLE" ] || emit_title "$MGR_TITLE"
    exit 0
  fi
fi

# --- слой 2: имя по сути принятого плана (до гейтов имени) -----------------
if plan_source; then
  RAW=$(gen_title "Реализовать принятый план (суть — в МАТЕРИАЛЕ)" "$PLAN_TEXT" plan)
  TOPIC=$(valid_title "$(sanitize_title "$RAW")")
  [ -z "$TOPIC" ] && fail_and_maybe_giveup "plan: empty title" "$PLAN_TRIES" "$PLAN_MARKER" "$PLAN_KEY"
  log "PLAN RESULT=$TOPIC"
  printf '%s' "$PLAN_KEY" > "$PLAN_MARKER" 2>/dev/null
  rm -f "$PLAN_TRIES" 2>/dev/null
  printf '%s' "$TOPIC" > "$MARKER" 2>/dev/null
  rm -f "$TRIES" 2>/dev/null
  emit_title "$TOPIC"
  exit 0
fi

# --- слой 3: /goal — имя по сути цели (до гейтов имени) --------------------
# Приходит сырой строкой `/goal <условие>`; clear-слова и пустой /goal — тишина.
PROMPT_TRIM=$(printf '%s' "$PROMPT" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
case "$PROMPT_TRIM" in
  /*)
    GOAL_CMD=$(printf '%s' "$PROMPT_TRIM" | sed -E 's#^/([^[:space:]]+).*#\1#')
    if [ "${GOAL_CMD##*:}" = goal ]; then                 # снять префикс плагина
      GOAL_ARGS=$(printf '%s' "$PROMPT_TRIM" | sed -E 's#^/[^[:space:]]+[[:space:]]*##')
      case "$(printf '%s' "$GOAL_ARGS" | tr '[:upper:]' '[:lower:]')" in
        ''|clear|stop|off|reset|none|cancel)
          log "goal: args=[$GOAL_ARGS] → no rename"; exit 0 ;;
      esac
      collect_material
      RAW=$(gen_title "Цель сессии: $GOAL_ARGS" "$MATERIAL" "$MATERIAL_KIND")
      TOPIC=$(valid_title "$(sanitize_title "$RAW")")
      [ -z "$TOPIC" ] && fail_and_maybe_giveup "goal: empty title" "$TRIES" "$MARKER" "native"
      log "GOAL RESULT=$TOPIC"
      printf '%s' "$TOPIC" > "$MARKER" 2>/dev/null
      rm -f "$TRIES" 2>/dev/null
      emit_title "$TOPIC"
      exit 0
    fi ;;
esac

# --- слой 0: имя, унаследованное при /clear (снимает гейт 3) ----------------
# Подробности и признаки — в шапке, гейт 3. Только на первом промпте новой
# сессии; дальше держат маркер (гейт 4) и счётчик попыток.
inherited_after_clear() {
  [ -n "$STITLE" ] || return 1
  [ -f "$MARKER" ] && return 1
  [ -s "$TPATH" ] || return 1
  head -1 "$TPATH" 2>/dev/null | command grep -q '"type":"custom-title"' || return 1
  local ct pc
  ct=$(command grep -c '"type":"custom-title"' "$TPATH" 2>/dev/null); ct=${ct:-0}
  [ "$ct" -eq 1 ] || return 1                 # ручной /rename после /clear — не трогаем
  pc=$(command grep -c '"promptId":' "$TPATH" 2>/dev/null); pc=${pc:-0}
  [ "$pc" -le 1 ] || return 1                 # не первый промпт сессии
  return 0
}

CLEARED=''
if inherited_after_clear; then
  CLEARED=1
  log "clear: inherited title [$STITLE] → переименовываем поверх"
fi

# --- гейты имени -----------------------------------------------------------
[ -n "$STITLE" ] && [ -z "$CLEARED" ] && exit 0
[ -f "$MARKER" ] && exit 0

# Самоочистка старых маркеров (>7 дней) — фоном, не блокирует.
# /private/tmp, не /tmp: BSD find не разворачивает симлинк стартовой точки.
( find /private/tmp -maxdepth 1 \( -name 'claude-topic-*' -o -name 'claude-termtitle-*' \
    -o -name 'claude-rc-synced-*' -o -name 'claude-title-tries-*' -o -name 'claude-plan-*' \
    -o -name 'claude-rename-*.log' \) -mtime +7 -delete 2>/dev/null ) &
disown 2>/dev/null

# --- классификация промпта --------------------------------------------------
TOPIC=''
LLM_INPUT=""
SKILL_INFO=''
case "$PROMPT_TRIM" in                                     # PROMPT_TRIM — из слоя 3
  /*)
    CMD=$(printf '%s' "$PROMPT_TRIM" | sed -E 's#^/([^[:space:]]+).*#\1#')
    CMD_BASE=${CMD##*:}                                   # снять префикс плагина
    ARGS=$(printf '%s' "$PROMPT_TRIM" | sed -E 's#^/[^[:space:]]+[[:space:]]*##')
    AWC=$(printf '%s' "$ARGS" | wc -w | tr -d ' ')
    # Ритуалы перезапуска — имя с периодом, ДО гейта AWC (аргумент «закрой вчера» /
    # «2026-W36» уточняет период, а не тему). Расчёт дат — scripts/ritual-title.sh
    # (общий с лаунчером jadlis-ritual-ensure.sh, который ставит то же имя через
    # --remote-control/--name при автозапуске). TITLE_NOW — подмена «сейчас» для тестов.
    case "$CMD_BASE" in
      day-relaunch|week-relaunch|jadlis-day|jadlis-week)
        TOPIC=$(bash "$HOME/.claude/scripts/ritual-title.sh" "$CMD_BASE" $ARGS 2>/dev/null)
        log "ritual: $CMD_BASE args=[$ARGS] → [$TOPIC]"
        ;;
    esac
    # Слой 4 (2026-10-03): скилл/команда с файлом описания → имя по смыслу
    # скилла + тексту после команды, всегда headless (нативный генератор CC
    # вызовы скиллов не именует: /cis-research <текст> оставался без имени).
    # Без текста — только если для команды нет готового имени ниже.
    if [ -z "$TOPIC" ]; then
      case "$CMD_BASE" in
        day-relaunch|day-start|day-end|commit-push|commit-push-pr|commit|week-end|metric-new|research|science-research|deep-research|verif|verify)
          [ "${AWC:-0}" -ge 1 ] && SKILL_INFO=$(skill_description "$CMD") ;;
        *) SKILL_INFO=$(skill_description "$CMD") ;;
      esac
    fi
    if [ -n "$TOPIC" ]; then
      :
    elif [ -n "$SKILL_INFO" ]; then
      LLM_INPUT="$PROMPT_TRIM"
    elif [ "${AWC:-0}" -ge 2 ]; then
      LLM_INPUT="$PROMPT_TRIM"          # осмысленный аргумент важнее имени команды
    else
      case "$CMD_BASE" in
        day-relaunch|day-start) TOPIC='Перезапуск дня' ;;
        day-end)        TOPIC='Завершение дня' ;;
        commit-push)    TOPIC='Коммит и push' ;;
        commit-push-pr) TOPIC='Коммит, push и PR' ;;
        commit)         TOPIC='Коммит' ;;
        week-end)       TOPIC='Итоги недели' ;;
        metric-new)     TOPIC='Новый замер' ;;
        research)       TOPIC='Полное исследование' ;;
        science-research) TOPIC='Научный обзор' ;;
        deep-research)  TOPIC='Глубокое исследование' ;;
        verif|verify)   TOPIC='Верификация' ;;
        *)
          TOPIC=$(printf '%s' "$CMD_BASE" | sed -E 's/[_-]/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/  */ /g')
          FIRST=$(printf '%s' "$TOPIC" | cut -c1 | tr '[:lower:]' '[:upper:]')
          REST=$(printf '%s' "$TOPIC" | cut -c2-)
          TOPIC="$FIRST$REST"
          ;;
      esac
    fi
    ;;
  *)
    [ -n "$PROMPT_TRIM" ] && LLM_INPUT="$PROMPT_TRIM"
    ;;
esac

# --- генерация (слой 1) ----------------------------------------------------
TITLE_BACKEND="${TITLE_BACKEND:-native}"
if [ -z "$TOPIC" ] && [ -n "$LLM_INPUT" ]; then
  collect_material
  case "$TITLE_BACKEND" in
    headless)
      RAW=$(gen_title "$LLM_INPUT" "$MATERIAL" "$MATERIAL_KIND" "$SKILL_INFO")
      [ -n "$RAW" ] && TOPIC=$(sanitize_title "$RAW")
      ;;
    *)
      # native: тишина без счётчика попыток и маркера — CC именует сам в фоне.
      # Исключения (слой 1): упомянут файл или сессия в план-моде → headless,
      # чтобы custom-title защитил от ASCII-слага при принятии плана.
      # Слой 4: вызов скилла — тоже headless (нативный генератор его пропускает).
      if [ -n "$MATERIAL" ] || [ "$PMODE" = plan ] || [ -n "$CLEARED" ] || [ -n "$SKILL_INFO" ]; then
        log "native backend, material/plan-mode/clear/skill → headless (kind=[${MATERIAL_KIND}] pmode=[$PMODE] cleared=[${CLEARED:-0}] skill=[${SKILL_INFO:+1}])"
        RAW=$(gen_title "$LLM_INPUT" "$MATERIAL" "$MATERIAL_KIND" "$SKILL_INFO")
        [ -n "$RAW" ] && TOPIC=$(sanitize_title "$RAW")
      else
        log "native backend → silent, CC titles the session"
        exit 0
      fi
      ;;
  esac
fi

TOPIC=$(valid_title "$(sanitize_title "$TOPIC")")
# Слой 4, провал модели на скилле без текста → имя команды (как до 03.10).
if [ -z "$TOPIC" ] && [ -n "$SKILL_INFO" ] && [ "${AWC:-0}" -eq 0 ]; then
  TOPIC=$(printf '%s' "$CMD_BASE" | sed -E 's/[_-]/ /g; s/  */ /g')
  TOPIC="$(printf '%s' "$TOPIC" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$TOPIC" | cut -c2-)"
  TOPIC=$(valid_title "$TOPIC")
  log "skill: model failed, no args → command name [$TOPIC]"
fi
[ -z "$TOPIC" ] && fail_and_maybe_giveup "empty topic" "$TRIES" "$MARKER" "native"
log "RESULT=$TOPIC"

# Успех: маркер (вторичный гейт) + JSON.
printf '%s' "$TOPIC" > "$MARKER" 2>/dev/null
rm -f "$TRIES" 2>/dev/null
emit_title "$TOPIC"

exit 0

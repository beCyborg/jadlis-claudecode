#!/bin/bash

input=$(cat)

# --- Синк заголовка терминала с именем сессии (/rename, --name, hook-sessionTitle) ---
sl_sid=$(echo "$input" | jq -r '.session_id // empty')
sl_name=$(echo "$input" | jq -r '.session_name // empty')
if [ -n "$sl_sid" ] && [ -n "$sl_name" ]; then
  sl_cache="/tmp/claude-termtitle-$sl_sid"
  if [ "$(cat "$sl_cache" 2>/dev/null)" != "$sl_name" ]; then
    printf '%s' "$sl_name" > "$sl_cache"
    "$HOME/.claude/hooks/_rename-apply.sh" "$sl_name" >/dev/null 2>&1 &
    # не-tmux окно/таб: best-effort OSC прямо в tty (если он у процесса есть)
    if [ -z "$TMUX" ] && [ -w /dev/tty ]; then
      printf '\033]2;%s\007\033]1;%s\007' "$sl_name" "$sl_name" > /dev/tty 2>/dev/null
    fi
  fi
fi

# --- Colors ---
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

colorize() {
  local val=$1
  if [ "$val" -ge 80 ]; then printf '%b' "$RED"
  elif [ "$val" -ge 60 ]; then printf '%b' "$YELLOW"
  else printf '%b' "$GREEN"
  fi
}

# --- Project Directory ---
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .cwd // ""')
project_name="${project_dir##*/}"

# --- Context Percentage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
used_int=$(printf "%.0f" "$used_pct")
ctx_color=$(colorize "$used_int")
ctx_part="${ctx_color}${used_int}%${RESET}"

# --- Model + effort (effort.level отсутствует, если модель его не поддерживает) ---
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
effort_lvl=$(echo "$input" | jq -r '.effort.level // empty')
model_part=""
if [ -n "$model_name" ]; then
  model_part="${model_name}${effort_lvl:+/$effort_lvl}"
fi

# --- Rate Limits ---
now=$(date +%s)

format_reset() {
  local resets_at=$1
  local diff=$(( resets_at - now ))
  if [ "$diff" -le 0 ]; then
    echo "now"
    return
  fi
  local days=$(( diff / 86400 ))
  local hours=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    printf '%dд %dч' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf '%dч %02dм' "$hours" "$mins"
  else
    printf '%dм' "$mins"
  fi
}

# --- Fable weekly (per-model недельная квота — только в /api/oauth/usage) ---
# Единственный fetcher — ~/.claude/scripts/claude-usage-fetch.sh: один кэш на аккаунт,
# общий backoff/бюджет для statusline, тика снапшота и гейта ритуалов (эндпоинт банит
# на час по 429). Здесь — только чтение кэша и дешёвая предпроверка (возраст + backoff),
# сам запрос уходит в фон через `refresh`. Профиль резолвит fetcher (env), включая
# ловушку CLAUDE_CONFIG_DIR=$HOME/.claude → default. Маркеры: ~ при возрасте > 1800 с,
# ! при > 7200 с. Тест-хуки CUF_TEST_* — в fetcher.
FETCHER="$HOME/.claude/scripts/claude-usage-fetch.sh"
CUF_CACHE=""; CUF_BACKOFF=""; CUF_TAG=""
[ -x "$FETCHER" ] && eval "$("$FETCHER" env --config-dir "${CLAUDE_CONFIG_DIR:-}" 2>/dev/null)"
fable_part=""
fable_age=999999
if [ -n "$CUF_CACHE" ] && [ -s "$CUF_CACHE" ]; then
  fable_fa=$(jq -r '.fetched_at // empty' "$CUF_CACHE" 2>/dev/null)
  case "$fable_fa" in ''|*[!0-9]*) fable_fa=$(stat -f %m "$CUF_CACHE" 2>/dev/null || echo 0) ;; esac
  fable_age=$(( now - fable_fa ))
fi
if [ -n "$CUF_CACHE" ] && [ "$fable_age" -ge 900 ]; then
  fable_bo=$(cat "$CUF_BACKOFF" 2>/dev/null)
  case "$fable_bo" in ''|*[!0-9]*) fable_bo=0 ;; esac
  if [ "$now" -ge "$fable_bo" ]; then
    "$FETCHER" refresh --config-dir "${CLAUDE_CONFIG_DIR:-}" --caller statusline --max-age 900 >/dev/null 2>&1 &
  fi
fi
if [ -n "$CUF_CACHE" ] && [ -s "$CUF_CACHE" ]; then
  fable_pct=$(jq -r '.fable.percent // empty' "$CUF_CACHE" 2>/dev/null)
  if [ -n "$fable_pct" ]; then
    fable_int=$(printf "%.0f" "$fable_pct")
    fable_color=$(colorize "$fable_int")
    fable_name=$(jq -r '.fable.scope.model.display_name // "Fable"' "$CUF_CACHE" 2>/dev/null)
    fable_stale=""
    [ "$fable_age" -gt 1800 ] && fable_stale="~"
    [ "$fable_age" -gt 7200 ] && fable_stale="!"
    fable_part="${fable_color}${fable_int}%${RESET}${fable_stale}(${CUF_TAG:+[$CUF_TAG] }${fable_name:-Fable})"
  fi
fi

rl_part=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$five_pct" ] && [ -n "$seven_pct" ]; then
  five_int=$(printf "%.0f" "$five_pct")
  seven_int=$(printf "%.0f" "$seven_pct")

  five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
  seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')

  five_color=$(colorize "$five_int")
  seven_color=$(colorize "$seven_int")

  five_time=$(format_reset "$five_reset")
  seven_time=$(format_reset "$seven_reset")

  rl_part="${five_color}${five_int}%${RESET}(${five_time}) | ${seven_color}${seven_int}%${RESET}(${seven_time})"
fi

for extra in "$fable_part"; do
  [ -z "$extra" ] && continue
  if [ -n "$rl_part" ]; then
    rl_part="${rl_part} | ${extra}"
  else
    rl_part="$extra"
  fi
done

# --- Output ---
ctx_part="${ctx_part}${model_part:+ $model_part}"
if [ -n "$rl_part" ]; then
  printf "%s | %b | %b\n" "$project_name" "$ctx_part" "$rl_part"
else
  printf "%s | %b\n" "$project_name" "$ctx_part"
fi

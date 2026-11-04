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

# --- Weekly limit only (5h window removed on the plan 2026-11; Fable display dropped) ---
rl_part=""
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$seven_pct" ]; then
  seven_int=$(printf "%.0f" "$seven_pct")
  seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')
  seven_color=$(colorize "$seven_int")
  seven_time=$(format_reset "$seven_reset")
  rl_part="${seven_color}${seven_int}%${RESET}(${seven_time})"
fi

# --- Output ---
ctx_part="${ctx_part}${model_part:+ $model_part}"
if [ -n "$rl_part" ]; then
  printf "%s | %b | %b\n" "$project_name" "$ctx_part" "$rl_part"
else
  printf "%s | %b\n" "$project_name" "$ctx_part"
fi

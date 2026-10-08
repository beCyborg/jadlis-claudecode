# jadlis-claudecode — terminal block (cld, tld). Source: owner's ~/.zshrc, exported by tools/export-owner.py
alias cc='cld'
_tmux_server_alive() {
  tmux list-sessions &>/dev/null
}

_cld_session_name() {
  local name
  name=$(git -C "$PWD" remote get-url origin 2>/dev/null | sed 's|.*/||;s|\.git$||')
  name=${name:-$(basename "$PWD")}
  local sanitized
  sanitized=$(printf '%s' "$name" | tr '.:\\ /' '_')
  [[ "$sanitized" == -* ]] && sanitized="_${sanitized}"
  printf '%s' "$sanitized"
}

# _cld_spawn <runner> <base> [claude args...] — механика cld.
_cld_spawn() {
  local runner="$1" base="$2"
  shift 2

  # Фоновое автообновление claude/codex (throttle 6ч, лог ~/.cache/tools-autoupdate/)
  ~/.claude/scripts/tools-autoupdate.sh &>/dev/null &!

  local session="$base"
  if _tmux_server_alive; then
    local -a existing
    existing=($(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E "^${base}(_[0-9]+)?$"))
    if (( ${#existing[@]} > 0 )); then
      local max=1
      for s in "${existing[@]}"; do
        if [[ "$s" =~ _([0-9]+)$ ]]; then
          local n=${match[1]}
          (( n >= max )) && max=$((n + 1))
        elif [[ "$s" == "$base" ]]; then
          (( max < 2 )) && max=2
        fi
      done
      session="${base}_${max}"
    fi
  fi

  local -a claude_args=(
    --dangerously-skip-permissions
    --model claude-opus-5-5   # Opus 5.5, 1M по умолчанию (22.09.2026; с 18.09 — opus[1m], до того fable[1m])
  )
  (( $# > 0 )) && claude_args+=("$@")

  if [[ -n "$TMUX" ]]; then
    tmux new-session -d -s "$session" -c "$PWD" "$runner$(printf ' %q' "${claude_args[@]}")"
    tmux set-option -t "=$session" status off
    tmux switch-client -t "=$session"
    tmux set-option -t "=$session" destroy-unattached on
  else
    tmux new-session -s "$session" -c "$PWD" "$runner$(printf ' %q' "${claude_args[@]}")" \; \
      set-option status off \; \
      set-option destroy-unattached on
  fi
}

# cld — всегда создаёт новую Claude Code session с auto-incremented suffix
# (base, base_2, base_3, ...). base = имя проекта из git remote или basename($PWD).
cld() {
  _cld_spawn claude "$(_cld_session_name)" "$@"
}

# tld — tmux-сессии с заголовками Claude Code (title панели). Без аргумента — список,
# с именем — attach снаружи tmux / switch-client изнутри (по $TMUX).
tld() {
  if [[ -z "$1" ]]; then
    tmux list-panes -a -F '#{session_name}	#{?session_attached,*, }	#{pane_title}' | column -t -s $'\t'
    return
  fi
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "=$1"
  else
    tmux attach -t "=$1"
  fi
}

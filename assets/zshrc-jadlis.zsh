# jadlis-claudecode — terminal block (cld). Source: owner's ~/.zshrc, exported by tools/export-owner.py
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

# _cld_spawn <runner> <base> [claude args...] — общая механика cld/cld2.
_cld_spawn() {
  local runner="$1" base="$2"
  shift 2

  # Фоновое автообновление claude/grok/codex (throttle 6ч, лог ~/.cache/tools-autoupdate/)
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
    --model 'fable[1m]'
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
  # env -u обязателен: запущенный из сессии второго аккаунта, cld иначе
  # унаследует его конфиг-дир и токен и будет жечь квоту B под видом A
  _cld_spawn "env -u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDE_CONFIG_DIR claude" \
    "$(_cld_session_name)" "$@"
}

#!/bin/zsh
# cu-autoapprove.sh — auto-approve the Claude Code TUI dialog
# "Computer Use wants to control these apps".
#
# Policy (owner decision 2026-09-13): approve everything, sentinels included (terminals, IDEs, Finder,
# System Settings) — consistent with bypassPermissions. Optional deny list: ~/.config/jadlis/cu-deny-apps,
# one extended regex (first non-# line) matched against each «◉ <app>» line of the dialog; a dialog that
# names a listed app gets Deny (Esc), so Claude hears «no» and reports instead of waiting.
# Example for a Mac with payment cards in 1Password:
#   1Password|Связка ключей|Keychain Access|Терминал|Terminal|iTerm|Редактор скриптов|Script Editor|Automator|Быстрые команды|Shortcuts
# Works only when Claude Code runs inside tmux (cld, or any tmux pane): it reads and types into the pane.
#
# Two modes:
#   --pane <%id> [--ttl <sec>]  (since 2026-09-15, the normal path)
#       Watch ONE pane, started by the PreToolUse hook cu-autoapprove-hook.sh
#       (matcher mcp__computer-use__.*). The hook fires ~0.6 s before the dialog
#       renders and touches $PING on every later computer-use call; the watcher
#       exits TTL seconds after the last ping. Nothing runs while computer use
#       is idle — the always-on launchd daemon cost ~3.4 Wh/day (5 % of the
#       battery) polling every pane once a second.
#   (no args)  legacy: poll every tmux pane forever. Kept for manual use;
#       no launchd agent: the hook mode is the normal path.
#
# Detection = TWO lines in one capture-pane snapshot of the visible screen:
#   1. the dialog title line (anchored, nothing else on the line)
#   2. the Deny option line ending in "(esc)" (anchored), plus a visible cursor
#      "❯" on Deny or Allow. The title alone appears in notes and logs; the
#      anchored Deny/(esc) line with a cursor is drawn only by the dialog itself.
# Action: wait 1.5 s (CC refuses input right after render) → re-snapshot →
#   cursor on Allow → Enter, otherwise Down + Enter (default focus is Deny).
# Post-cycle: 2 s later re-check the pane; the dialog visible again means the
#   next batch (dialog budget = 8 units) or refused keys → act again.
# Rate limit: ≤ 6 actions per pane per 60 s, then "ERROR stuck" and a 30 s
#   pause for that pane.

export LC_ALL=en_US.UTF-8
setopt no_nomatch

TMUX_SOCK=${CU_TMUX_SOCK:-${TMUX%%,*}}
[[ -n $TMUX_SOCK ]] || TMUX_SOCK=/private/tmp/tmux-$UID/default
TMUX_BIN=${CU_TMUX_BIN:-/opt/homebrew/bin/tmux}
[[ -x $TMUX_BIN ]] || TMUX_BIN=$(command -v tmux)

LOGDIR=$HOME/.claude/logs
LOG=${CU_LOG:-$LOGDIR/cu-autoapprove.log}
HB=${CU_HEARTBEAT:-$LOGDIR/cu-autoapprove.heartbeat}
mkdir -p "$LOGDIR"

# Strings are split by concatenation so that reading this script in a pane
# never looks like the dialog to the daemon itself.
TITLE_RE='^[[:space:]]*Computer Use wants to control'' these apps[[:space:]]*$'
DENY_RE='^[[:space:]]*(❯ )?Deny, and tell Claude'' what to do differently \(esc\)[[:space:]]*$'
CURSOR_RE='^[[:space:]]*❯ (Deny, and tell Claude|Allow for this'' session)'
ALLOW_RE='^[[:space:]]*❯ Allow for this'' session'
APP_RE='^[[:space:]]*◉ '
DENY_APPS=""
[[ -r $HOME/.config/jadlis/cu-deny-apps ]] && DENY_APPS=$(grep -v -e '^#' -e '^[[:space:]]*$' "$HOME/.config/jadlis/cu-deny-apps" | head -1)

RENDER_WAIT=${CU_RENDER_WAIT:-1.5}   # refuseInput window
KEY_GAP=0.4
POST_WAIT=2
MAX_ACTIONS=6
WINDOW=60
STUCK_PAUSE=30
LOG_MAX_BYTES=$((1024*1024))
LOG_KEEP_LINES=200

WATCH_PANE=""
WATCH_TTL=90
while (( $# )); do
  case "$1" in
    --pane) WATCH_PANE="$2"; shift 2 ;;
    --ttl)  WATCH_TTL="$2"; shift 2 ;;
    *) print -u2 "usage: $0 [--pane %id [--ttl sec]]"; exit 2 ;;
  esac
done

typeset -A act_times     # pane_id -> space-separated epochs of actions
typeset -A stuck_until   # pane_id -> epoch until which the pane is ignored

tm() { "$TMUX_BIN" -S "$TMUX_SOCK" "$@" }
log() { print -r -- "$(date '+%F %T') $*" >> "$LOG" }

trim_log() {
  local size
  size=$(stat -f %z "$LOG" 2>/dev/null) || return
  if (( size > LOG_MAX_BYTES )); then
    local tmp="$LOG.tmp.$$"
    tail -n "$LOG_KEEP_LINES" "$LOG" > "$tmp" && mv "$tmp" "$LOG"
    log "log trimmed to last $LOG_KEEP_LINES lines (was $size bytes)"
  fi
}

# dialog_visible <snapshot> → 0 if the dialog is on screen
dialog_visible() {
  local t="$1"
  print -r -- "$t" | grep -qE -- "$TITLE_RE" || return 1
  print -r -- "$t" | grep -qE -- "$DENY_RE"  || return 1
  print -r -- "$t" | grep -qE -- "$CURSOR_RE" || return 1
  return 0
}

# log_dialog <pane_name> <snapshot> — write the dialog block (title..Allow line)
log_dialog() {
  local name="$1" t="$2"
  {
    print -r -- "----- dialog in $name -----"
    print -r -- "$t" | awk -v tre="$TITLE_RE" '
      $0 ~ tre {on=1}
      on {print}
      on && /Allow for this session/ {exit}'
    print -r -- "----- end dialog -----"
  } >> "$LOG"
}

# count actions for pane within WINDOW; prune old ones
recent_actions() {
  local pid="$1" now=$(date +%s) keep="" n=0 e
  for e in ${=act_times[$pid]}; do
    if (( now - e < WINDOW )); then keep+="$e "; ((n++)); fi
  done
  act_times[$pid]="$keep"
  print -- $n
}

# act_on_pane <pane_id> <pane_name> → 0 if keys were sent
act_on_pane() {
  local pid="$1" name="$2" t cur n
  n=$(recent_actions "$pid")
  if (( n >= MAX_ACTIONS )); then
    log "ERROR stuck $name: $n actions in ${WINDOW}s, pausing ${STUCK_PAUSE}s"
    stuck_until[$pid]=$(( $(date +%s) + STUCK_PAUSE ))
    act_times[$pid]=""
    return 1
  fi
  sleep "$RENDER_WAIT"
  t=$(tm capture-pane -p -t "$pid" 2>/dev/null) || { log "WARN $name vanished before action"; return 1; }
  dialog_visible "$t" || { log "INFO $name dialog gone before action (handled elsewhere?)"; return 1; }
  log_dialog "$name" "$t"
  local -a keys
  local denied
  [[ -n $DENY_APPS ]] && denied=$(print -r -- "$t" | grep -E -- "$APP_RE" | grep -E -- "$DENY_APPS" | head -1 | sed -E 's/^[[:space:]]*◉ //')
  if [[ -n $denied ]]; then
    keys=(Escape)
    log "DENY $name: app on the deny list: $denied"
  elif print -r -- "$t" | grep -qE -- "$ALLOW_RE"; then keys=(Enter); else keys=(Down Enter); fi
  local k
  for k in "${keys[@]}"; do
    tm send-keys -t "$pid" "$k" 2>/dev/null || { log "WARN $name send-keys $k failed"; return 1; }
    sleep "$KEY_GAP"
  done
  act_times[$pid]+="$(date +%s) "
  log "action $name: sent ${(j:+:)keys}"
  return 0
}

# handle_pane <pane_id> <pane_name> — detect, act, post-cycle for batches
# → 0 if a dialog was handled, 1 if none was visible
handle_pane() {
  local pid="$1" name="$2" t now rounds=0
  now=$(date +%s)
  if (( ${stuck_until[$pid]:-0} > now )); then return 1; fi
  t=$(tm capture-pane -p -t "$pid" 2>/dev/null) || return 1
  dialog_visible "$t" || return 1
  log "DETECTED $name"
  while true; do
    act_on_pane "$pid" "$name" || return 0
    ((rounds++))
    sleep "$POST_WAIT"
    t=$(tm capture-pane -p -t "$pid" 2>/dev/null) || { log "INFO $name gone after action"; return 0; }
    if dialog_visible "$t"; then
      log "DETECTED $name again after action #$rounds (next batch or refused input)"
      continue
    fi
    log "done $name after $rounds action(s)"
    return 0
  done
}

# watch_pane — hook mode: one pane, exit WATCH_TTL s after the last ping.
# $PING is touched by the hook on every computer-use call; $PIDFILE lets the
# hook see that a watcher is already running and only extend it.
watch_pane() {
  local pid="$WATCH_PANE" name deadline now handled=0
  local key=${pid#%}
  local PING=$LOGDIR/cu-watch-$key.ping PIDFILE=$LOGDIR/cu-watch-$key.pid
  print -- $$ > "$PIDFILE"
  [[ -e $PING ]] || touch "$PING"
  name=$(tm display-message -p -t "$pid" '#S:#I.#P' 2>/dev/null) || {
    log "WARN watcher: pane $pid not found, exiting"; rm -f "$PIDFILE" "$PING"; return 1; }
  log "watcher started for $name ($pid) pid $$, ttl ${WATCH_TTL}s"
  while true; do
    handle_pane "$pid" "$name" && handled=1
    now=$(date +%s)
    deadline=$(( $(stat -f %m "$PING" 2>/dev/null || print $now) + WATCH_TTL ))
    (( now >= deadline )) && break
    tm has-session 2>/dev/null || { log "INFO watcher: tmux gone, exiting"; break; }
    sleep 1
  done
  if (( handled )); then log "watcher exit $name: dialogs handled"
  else log "INFO watcher exit $name: no dialog seen (app already granted, or the hook fired without a dialog)"; fi
  rm -f "$PIDFILE" "$PING"
}

main() {
  local -a panes
  local line pid name iter=0 npanes
  panes=("${(@f)$(tm list-panes -a -F '#{pane_id} #S:#I.#P' 2>/dev/null)}")
  npanes=${#panes[@]}; [[ -z "${panes[1]}" ]] && npanes=0
  log "started pid $$, $npanes panes, tmux=$TMUX_BIN sock=$TMUX_SOCK"
  while true; do
    touch "$HB"
    if panes=("${(@f)$(tm list-panes -a -F '#{pane_id} #S:#I.#P' 2>&1)}"); then
      for line in "${panes[@]}"; do
        [[ -z "$line" ]] && continue
        pid=${line%% *}; name=${line#* }
        handle_pane "$pid" "$name"
      done
    else
      (( iter % 60 == 0 )) && log "WARN tmux list-panes failed: ${panes[1]}"
    fi
    ((iter++))
    (( iter % 60 == 0 )) && trim_log
    sleep 1
  done
}

if [[ -n $WATCH_PANE ]]; then
  watch_pane
else
  main
fi

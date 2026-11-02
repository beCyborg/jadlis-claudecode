#!/bin/zsh
# cu-autoapprove-hook.sh — PreToolUse hook, matcher mcp__computer-use__.*
# Starts (or extends) a cu-autoapprove.sh watcher for THIS session's tmux pane,
# so the "Computer Use wants to control these apps" dialog is approved without
# an always-on daemon. Verified 2026-09-15: PreToolUse fires ~0.6 s before the
# dialog renders; PermissionRequest and Notification never fire for it.
#
# Must return fast and print nothing on stdout (PreToolUse stdout is parsed).
# The watcher is detached with all three fds redirected — an inherited pipe
# would keep Claude Code waiting for the hook until the watcher exits.

LOGDIR=$HOME/.claude/logs
LOG=$LOGDIR/cu-autoapprove.log
WATCHER=$HOME/.claude/scripts/cu-autoapprove.sh
TMUX_BIN=/opt/homebrew/bin/tmux
[[ -x $TMUX_BIN ]] || TMUX_BIN=$(command -v tmux)
TTL=${CU_WATCH_TTL:-90}
mkdir -p "$LOGDIR"

log() { print -r -- "$(date '+%F %T') $*" >> "$LOG" }

tool=$(/opt/homebrew/bin/jq -r '.tool_name // ""' 2>/dev/null)   # stdin JSON
tool=${tool#mcp__computer-use__}

# Pane: $TMUX_PANE is exported by tmux into the pane's shell and inherited by
# claude and its hooks. Fallback: the controlling tty of this process.
pane=${TMUX_PANE:-}
if [[ -z $pane ]]; then
  tty=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
  [[ -n $tty && $tty != '??' ]] && pane=$("$TMUX_BIN" list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null | awk -v t="/dev/$tty" '$2==t{print $1; exit}')
fi
if [[ -z $pane ]] || ! "$TMUX_BIN" display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
  log "WARN hook ($tool): no tmux pane for this session (TMUX_PANE='${TMUX_PANE:-}'), nothing to watch"
  exit 0
fi

key=${pane#%}
PING=$LOGDIR/cu-watch-$key.ping PIDFILE=$LOGDIR/cu-watch-$key.pid
touch "$PING"
if [[ -r $PIDFILE ]] && kill -0 "$(<$PIDFILE)" 2>/dev/null; then
  exit 0   # watcher alive; the touch above extended its deadline
fi
log "hook ($tool): starting watcher for $pane"
zsh "$WATCHER" --pane "$pane" --ttl "$TTL" </dev/null >/dev/null 2>&1 &!
exit 0

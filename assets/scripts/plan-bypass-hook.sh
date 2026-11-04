#!/bin/zsh
# plan-bypass-hook.sh — PostToolUse hook, matcher ExitPlanMode.
#
# A plan approved from the Remote Control app (iPhone) leaves the session in
# auto mode with the whole planning conversation still in context: the app
# has one "approve" button, while the terminal dialog offers "Yes, clear
# context and bypass permissions" (8 of 8 phone approvals went plan → auto,
# week to 2026-09-24). The terminal dialog has no keep-context auto option,
# so "auto mode on" right after ExitPlanMode means a phone approval.
#
# Hook mode (stdin = hook JSON):
#   1. If THIS session's tmux pane shows "auto mode on", cycle Shift+Tab until
#      it shows "bypass permissions on" (auto → manual → accept edits → plan →
#      bypass). Runs synchronously: the model makes no tool call until the
#      hook returns, so the modes passed on the way never apply to anything.
#      Every press waits for the mode line to change — no overshoot.
#   2. Then, unless PLAN_CLEAR_ON_REMOTE=0: write a state file, start this
#      script with --relaunch through `tmux run-shell -b` (lives in the tmux
#      server, outside Claude's process tree) and print
#      {"continue": false, "stopReason": "plan-clear: …"} so the turn stops
#      before the model implements anything in the old context.
#   The terminal "clear context" option denies ExitPlanMode, so PostToolUse
#   never fires on it (binary 2.1.286) — no double clear.
#
# Relaunch mode (--relaunch <state file>): wait until the pane is idle with the
# plan-clear marker on screen → type /clear → wait for the reset → make sure
# the mode is bypass → type one line "Implement the approved plan in <file>…
# read the full transcript at: <path>" (the same pointer the native clear
# option adds) → Enter. The prompt does not start with "Implement the
# following plan:" on purpose: rename-topic-from-prompt.sh then names the
# session from the plan file (layer 1) instead of parsing the line as a plan.
# Nothing is typed unless the input line is empty (dim placeholder text such
# as `Try "…"` counts as empty).
#
# Failure is benign: hook mode stays silent (exit 0, empty stdout) when there
# is no pane or the screen is not "auto mode"; if the relaunch fails after the
# turn was stopped, the session waits with the plan-clear message and a plain
# "реализуй план" continues in the old context.
# Test knob: PLAN_BYPASS_REMOTE_MODE (default "auto mode") — the mode text that
# counts as a phone approval.

export LC_ALL=en_US.UTF-8

LOGDIR=$HOME/.claude/logs
LOG=$LOGDIR/plan-bypass.log
STATEDIR=$HOME/.claude/state/plan-clear
TMUX_BIN=/opt/homebrew/bin/tmux
[[ -x $TMUX_BIN ]] || TMUX_BIN=$(command -v tmux)
JQ=/opt/homebrew/bin/jq
[[ -x $JQ ]] || JQ=$(command -v jq)
SELF=${0:A}
MAX_PRESSES=${PLAN_BYPASS_MAX:-8}   # 4 needed from auto; the rest covers refused keys
REMOTE_MODE=${PLAN_BYPASS_REMOTE_MODE:-auto mode}
APPEAR_WAIT=3                       # s for the prompt box to come back after the dialog
CHANGE_WAIT=1.5                     # s for one press to show up on the mode line
MARKER='plan-clear:'
STOP_REASON="$MARKER очищаю контекст, реализация плана начнётся в чистом окне"
mkdir -p "$LOGDIR"

log() { print -r -- "$(date '+%F %T') $*" >> "$LOG" }

pane='' sid='?'

# Screen layout under the transcript (capture-pane, no colours):
#   ✳ Мудрю… (running UserPromptSubmit hook · 2s)   ← spinner, only while busy
#   ──── <session title> ─                           ← top border (may hold text)
#   ❯ <input>                                        ← input line(s)
#   ────────────                                     ← bottom border (─ only)
#     Jadlis | 0% Opus 5.5/low | …                   ← statusline
#     ⏸ plan mode on (shift+tab to cycle) · …        ← mode line
# Only lines below the bottom border are read for the mode: the transcript
# above can quote these very words.
RE_BORDER='^─+[[:space:]]*$'
RE_TOP='^─'
RE_SPIN='…[[:space:]]*\([^)]*[0-9]+s'
RE_MODE='^[[:space:]]*(⏵⏵|⏸) ([a-z'"'"' ]+) on( \(|  | ·|$)'

# bottom_border <lines…> → index of the last ─-only line, 0 if none
bottom_border() {
  local i
  for (( i = $#; i > 0; i-- )); do
    [[ ${@[i]} =~ $RE_BORDER ]] && { print -r -- $i; return }
  done
  print -r -- 0
}

# mode_now → the mode text from the status line under the prompt box:
#   "bypass permissions", "auto mode", "accept edits", "plan mode", "manual mode"…
#   "none"  the prompt box is there but no mode line under it
#   ""      no prompt box on screen (a dialog is open) — never press keys then
mode_now() {
  local -a lines; local i b
  lines=("${(@f)$("$TMUX_BIN" capture-pane -p -t "$pane" 2>/dev/null)}")
  b=$(bottom_border "${lines[@]}")
  (( b )) || { print -r -- ""; return }
  for (( i = b + 1; i <= ${#lines}; i++ )); do
    if [[ ${lines[i]} =~ $RE_MODE ]]; then print -r -- "${match[2]}"; return; fi
  done
  print -r -- "none"
}

# wait_mode_change <old> <seconds> → prints the new mode, or the old one on timeout
wait_mode_change() {
  local old=$1 m; local -F t=0
  while (( t < $2 )); do
    sleep 0.2; (( t += 0.2 ))
    m=$(mode_now)
    [[ $m != "$old" ]] && { print -r -- "$m"; return }
  done
  print -r -- "$old"
}

# cycle_to_bypass <current mode> → Shift+Tab until "bypass permissions"; 0 = reached
cycle_to_bypass() {
  local m=$1 new presses=0
  while (( presses < MAX_PRESSES )); do
    "$TMUX_BIN" send-keys -t "$pane" BTab 2>/dev/null || { log "WARN $sid: send-keys failed"; return 1 }
    (( presses++ ))
    new=$(wait_mode_change "$m" "$CHANGE_WAIT")
    if [[ -z $new ]]; then
      log "WARN $sid: prompt box vanished after press $presses (was '$m'), stopping"
      return 1
    fi
    [[ $new == "$m" ]] && log "$sid: press $presses not taken, mode still '$m'"
    m=$new
    if [[ $m == "bypass permissions" ]]; then
      log "$sid: switched to bypass in $presses presses"
      return 0
    fi
  done
  log "WARN $sid: bypass not reached after $presses presses, mode '$m'"
  return 1
}

# box_state → "idle" | "busy" (spinner above the box) | "typed" (text in the
# input) | "" (no prompt box). Dim text in the input line is a placeholder.
box_state() {
  local -a plain colour; local i b t=0 input
  plain=("${(@f)$("$TMUX_BIN" capture-pane -p -t "$pane" 2>/dev/null)}")
  b=$(bottom_border "${plain[@]}")
  (( b > 1 )) || { print -r -- ""; return }
  for (( i = b - 1; i > 0; i-- )); do
    [[ ${plain[i]} =~ $RE_TOP ]] && { t=$i; break }
  done
  (( t )) || { print -r -- ""; return }
  for (( i = t - 1; i > 0 && i >= t - 8; i-- )); do
    [[ ${plain[i]} =~ $RE_SPIN ]] && { print -r -- busy; return }
  done
  # Same rows with colours: drop dim runs (ESC[2m … ESC[0m/ESC[22m), then all SGR.
  colour=("${(@f)$("$TMUX_BIN" capture-pane -p -e -t "$pane" 2>/dev/null)}")
  input=''
  for (( i = t + 1; i < b; i++ )); do input+=${colour[i]}; done
  input=$(print -r -- "$input" | /usr/bin/perl -CS -pe 's/\e\[2m.*?(\e\[(0|22)?m|$)//g; s/\e\[[0-9;]*m//g; s/\x{276F}//g; s/[\s\x{a0}]+//g')
  [[ -n $input ]] && { print -r -- typed; return }
  print -r -- idle
}

# pane_alive → $pane names a live pane (display-message exits 0 even for a
# missing pane id, so compare its output).
pane_alive() { [[ -n $pane && $("$TMUX_BIN" display-message -p -t "$pane" '#{pane_id}' 2>/dev/null) == "$pane" ]] }

marker_on_screen() { "$TMUX_BIN" capture-pane -p -t "$pane" 2>/dev/null | /usr/bin/grep -qF -- "$MARKER" }

# ---------------------------------------------------------------- relaunch mode
relaunch() {
  local state=$1 plan tpath st prompt
  local -F t
  pane=$("$JQ" -r '.pane // empty' "$state" 2>/dev/null)
  sid=$("$JQ" -r '.sid // "?"' "$state" 2>/dev/null)
  plan=$("$JQ" -r '.plan // empty' "$state" 2>/dev/null)
  tpath=$("$JQ" -r '.transcript // empty' "$state" 2>/dev/null)
  rm -f -- "$state"
  if [[ -z $plan ]] || ! pane_alive; then
    log "WARN $sid: relaunch: bad state (pane='$pane' plan='$plan'), nothing typed"
    return
  fi

  # 1. The stopped turn: marker printed, no spinner, empty input.
  t=0; st=''
  while (( t < 30 )); do
    marker_on_screen && st=$(box_state) && [[ $st == idle ]] && break
    sleep 0.3; (( t += 0.3 ))
  done
  if [[ $st != idle ]]; then
    log "WARN $sid: relaunch: pane not idle after 30s (state '$st'), nothing typed"
    return
  fi
  sleep 0.5
  st=$(box_state)
  [[ $st == idle ]] || { log "WARN $sid: relaunch: pane became '$st' before /clear, nothing typed"; return }

  # 2. /clear — the suggestion menu highlights /clear for the exact name.
  "$TMUX_BIN" send-keys -t "$pane" -l '/clear' && sleep 0.4 && "$TMUX_BIN" send-keys -t "$pane" Enter \
    || { log "WARN $sid: relaunch: send-keys /clear failed"; return }
  t=0; st=''
  while (( t < 15 )); do
    sleep 0.3; (( t += 0.3 ))
    st=$(box_state)
    [[ $st == idle ]] || continue
    marker_on_screen || break
    if (( t >= 4 )); then log "$sid: relaunch: marker still on screen after /clear, going on"; break; fi
  done
  if [[ $st != idle ]]; then
    log "WARN $sid: relaunch: pane not idle after /clear (state '$st'), prompt not typed"
    return
  fi
  log "$sid: relaunch: context cleared"

  # 3. Mode: /clear is expected to keep bypass; fix it if not.
  m=$(mode_now)
  [[ $m == "bypass permissions" ]] || { log "$sid: relaunch: mode after /clear '$m', cycling"; cycle_to_bypass "$m" }

  # 4. The implementation prompt, one line, typed (not pasted).
  prompt="Implement the approved plan in $plan. Read the plan file first."
  [[ -n $tpath ]] && prompt+=" If you need specific details from before exiting plan mode (like exact code snippets, error messages, or content you generated), read the full transcript at: $tpath"
  st=$(box_state)
  [[ $st == idle ]] || { log "WARN $sid: relaunch: pane became '$st' before the prompt, not typed"; return }
  "$TMUX_BIN" send-keys -t "$pane" -l -- "$prompt" && sleep 0.5 && "$TMUX_BIN" send-keys -t "$pane" Enter \
    || { log "WARN $sid: relaunch: send-keys prompt failed"; return }

  # 5. Confirm the turn started.
  t=0
  while (( t < 8 )); do
    sleep 0.3; (( t += 0.3 ))
    [[ $(box_state) == busy ]] && { log "$sid: relaunched in a clean context, plan $plan"; return }
  done
  log "WARN $sid: relaunch: no spinner 8s after the prompt (state '$(box_state)')"
}

if [[ $1 == --relaunch ]]; then
  relaunch "$2"
  exit 0
fi
# Debug: what the relaunch logic sees in a pane.
if [[ $1 == --probe ]]; then
  pane=$2
  print -r -- "box='$(box_state)' mode='$(mode_now)' marker=$(marker_on_screen && print yes || print no)"
  exit 0
fi

# -------------------------------------------------------------------- hook mode
input=$(cat)
hook_mode=$(print -r -- "$input" | "$JQ" -r '.permission_mode // "?"' 2>/dev/null)
sid=$(print -r -- "$input" | "$JQ" -r '.session_id // "?"' 2>/dev/null)
sid=${sid[1,8]}
plan_file=$(print -r -- "$input" | "$JQ" -r '.tool_response.filePath // .tool_input.planFilePath // empty' 2>/dev/null)
transcript=$(print -r -- "$input" | "$JQ" -r '.transcript_path // empty' 2>/dev/null)

# Pane: $TMUX_PANE is exported by tmux into the pane's shell and inherited by
# claude and its hooks. Fallback: the controlling tty of this process.
pane=${TMUX_PANE:-}
if [[ -z $pane ]]; then
  tty=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
  [[ -n $tty && $tty != '??' ]] && pane=$("$TMUX_BIN" list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null | awk -v t="/dev/$tty" '$2==t{print $1; exit}')
fi
if ! pane_alive; then
  log "WARN $sid: no tmux pane (TMUX_PANE='${TMUX_PANE:-}'), hook_mode=$hook_mode, nothing to do"
  exit 0
fi

m=$(mode_now)
typeset -F t=0
while [[ -z $m ]] && (( t < APPEAR_WAIT )); do
  sleep 0.2; (( t += 0.2 )); m=$(mode_now)
done
name=$("$TMUX_BIN" display-message -p -t "$pane" '#S' 2>/dev/null)
log "$sid ($name $pane): plan approved, hook_mode=$hook_mode, screen='$m'"

if [[ $m != "$REMOTE_MODE" ]]; then
  [[ -z $m ]] && log "WARN $sid: prompt box not visible after ${APPEAR_WAIT}s, not touching the pane"
  exit 0
fi

cycle_to_bypass "$m"

# Clean-context relaunch (phone approvals only reach this point).
[[ ${PLAN_CLEAR_ON_REMOTE:-1} == 0 ]] && { log "$sid: plan-clear off (PLAN_CLEAR_ON_REMOTE=0)"; exit 0 }
if [[ -z $plan_file ]]; then
  log "WARN $sid: no plan file path in hook input, context kept"
  exit 0
fi
mkdir -p "$STATEDIR"
state=$STATEDIR/$sid.json
"$JQ" -n --arg pane "$pane" --arg sid "$sid" --arg plan "$plan_file" --arg transcript "$transcript" \
  '{pane: $pane, sid: $sid, plan: $plan, transcript: $transcript, at: (now | todate)}' > "$state" 2>/dev/null
if ! "$TMUX_BIN" run-shell -b "/bin/zsh '$SELF' --relaunch '$state' >/dev/null 2>&1; true" 2>/dev/null; then
  log "WARN $sid: tmux run-shell failed, context kept"
  rm -f -- "$state"
  exit 0
fi
log "$sid: relaunch scheduled, turn stopped"
"$JQ" -nc --arg r "$STOP_REASON" '{continue: false, stopReason: $r}'
exit 0

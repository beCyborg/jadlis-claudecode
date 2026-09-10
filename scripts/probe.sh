#!/bin/sh
# probe.sh — read-only probe of the machine. Changes nothing, installs nothing.
#
# Prints a machine-readable list, one `key=value` per line:
#   <check>=PASS|FAIL          — the check itself
#   <check>.info=<text>        — version or path, only when known
# The hub and the /claudecode skill both parse this; keep the key names stable.
#
# Every path is derived from $HOME, so the probe can run under a throwaway HOME.
set -u

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
VAULT="$HOME/Jadlis"

say()  { printf '%s=%s\n' "$1" "$2"; }
info() { [ -n "${2:-}" ] && printf '%s.info=%s\n' "$1" "$2"; return 0; }

have() { command -v "$1" >/dev/null 2>&1; }

check_cmd() {   # $1 key, $2 command, $3 version args
	if have "$2"; then
		say "$1" PASS
		[ -n "${3:-}" ] && info "$1" "$("$2" $3 2>/dev/null | head -1 | cut -c1-60)"
	else
		say "$1" FAIL
	fi
}

# --- base tools -------------------------------------------------------------
check_cmd homebrew brew --version
check_cmd claude   claude --version
check_cmd git      git --version
check_cmd jq       jq --version
check_cmd node     node --version
check_cmd python313 python3.13 --version
check_cmd uv       uv --version
check_cmd poppler  pdftotext -v
check_cmd tmux     tmux -V

# native install (`curl … install.sh | bash`) puts the launcher in ~/.local/bin
if [ -x "$HOME/.local/bin/claude" ]; then
	say claude_native PASS
	info claude_native "$HOME/.local/bin/claude"
else
	say claude_native FAIL
fi

# --- terminal ---------------------------------------------------------------
if [ -d /Applications/iTerm.app ] || [ -d "$HOME/Applications/iTerm.app" ]; then
	say iterm2 PASS
else
	say iterm2 FAIL
fi

font=""
for d in "$HOME/Library/Fonts" /Library/Fonts; do
	[ -d "$d" ] || continue
	f=$(ls "$d" 2>/dev/null | grep -i '^JetBrainsMono.*Nerd' | head -1)
	[ -n "$f" ] && { font="$d/$f"; break; }
done
if [ -n "$font" ]; then say font_jetbrains PASS; info font_jetbrains "$font"; else say font_jetbrains FAIL; fi

if [ -f "$HOME/.tmux.conf" ] && grep -q 'allow-passthrough on' "$HOME/.tmux.conf" 2>/dev/null; then
	say tmux_conf PASS
else
	say tmux_conf FAIL
fi

PROFILE="$HOME/Library/Application Support/iTerm2/DynamicProfiles/jadlis.json"
if [ -f "$PROFILE" ]; then
	say iterm_profile PASS
	info iterm_profile "$PROFILE"
else
	say iterm_profile FAIL
fi

if grep -q '^# >>> jadlis-claudecode >>>' "$HOME/.zshrc" 2>/dev/null; then
	say zshrc_block PASS
else
	say zshrc_block FAIL
fi

# --- ~/.claude --------------------------------------------------------------
# «merged» marker: the template's own output style. Nothing else sets it.
if [ -f "$CLAUDE_HOME/settings.json" ] \
   && have jq \
   && jq -e '.outputStyle == "Jadlis"' "$CLAUDE_HOME/settings.json" >/dev/null 2>&1; then
	say settings_merged PASS
else
	say settings_merged FAIL
fi

hooks_ok=PASS
for h in session-start-title.sh rename-topic-from-prompt.sh _rename-apply.sh; do
	[ -x "$CLAUDE_HOME/hooks/$h" ] || hooks_ok=FAIL
done
say hooks "$hooks_ok"

[ -x "$CLAUDE_HOME/statusline-command.sh" ] && say statusline PASS || say statusline FAIL
[ -f "$CLAUDE_HOME/output-styles/jadlis.md" ] && say output_style PASS || say output_style FAIL
[ -f "$CLAUDE_HOME/rules/routing.md" ] && say rules PASS || say rules FAIL

scripts_ok=PASS
for s in claude-usage-fetch.sh tools-autoupdate.sh; do
	[ -x "$CLAUDE_HOME/scripts/$s" ] || scripts_ok=FAIL
done
say claude_scripts "$scripts_ok"

# --- vault ------------------------------------------------------------------
[ -d "$VAULT" ] && say jadlis_dir PASS || say jadlis_dir FAIL

info macos "$(sw_vers -productVersion 2>/dev/null || echo unknown)"
info arch "$(uname -m)"
exit 0

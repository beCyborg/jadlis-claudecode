#!/bin/sh
# apply-claude-home.sh — copy the owner's ~/.claude files into the recipient's $HOME/.claude.
#
# Copies: CLAUDE.md, rules/*.md, output-styles/jadlis.md, hooks/*.sh (chmod +x),
#         statusline-command.sh (chmod +x), scripts/*.sh (chmod +x).
# settings.json is NOT touched here — that is apply-settings.sh (it merges, it does not copy).
#
# A file that already exists and differs is left alone and reported as DIFFERS; --force
# overwrites it after a backup. So a second run changes nothing.
#
# Usage: apply-claude-home.sh [--plan] [--force] [--assets DIR]
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ASSETS="${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/.." && pwd)}/assets"
MODE=apply
FORCE=0

while [ $# -gt 0 ]; do
	case "$1" in
		--plan)   MODE=plan; shift ;;
		--force)  FORCE=1; shift ;;
		--assets) ASSETS="$2"; shift 2 ;;
		*) printf 'apply-claude-home.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
	esac
done

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -d "$ASSETS" ] || { printf 'apply-claude-home.sh: no assets at %s\n' "$ASSETS" >&2; exit 1; }

DIFFERS=0

place() {   # $1 source, $2 destination relative to $CLAUDE_HOME, $3 exec (1|0)
	_src="$ASSETS/$1"
	_dst="$CLAUDE_HOME/$2"
	_key=$(printf '%s' "$2" | tr '/.' '__')
	[ -f "$_src" ] || { printf '%s=MISSING-SOURCE\n' "$_key"; return 0; }

	if [ -f "$_dst" ] && cmp -s "$_src" "$_dst"; then
		printf '%s=UNCHANGED\n' "$_key"
	elif [ -f "$_dst" ] && [ "$FORCE" = 0 ]; then
		printf '%s=DIFFERS\n' "$_key"
		DIFFERS=$((DIFFERS + 1))
	elif [ "$MODE" = plan ]; then
		printf '%s=WOULD-WRITE\n' "$_key"
	else
		mkdir -p "$(dirname "$_dst")"
		if [ -f "$_dst" ]; then cp "$_dst" "$_dst.bak-$(date +%Y%m%d-%H%M%S)"; fi
		cp "$_src" "$_dst"
		printf '%s=WRITTEN\n' "$_key"
	fi

	if [ "$3" = 1 ] && [ -f "$_dst" ] && [ "$MODE" != plan ]; then chmod +x "$_dst"; fi
	return 0
}

if [ "$MODE" != plan ]; then
	mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/rules" "$CLAUDE_HOME/output-styles" "$CLAUDE_HOME/scripts"
fi

place CLAUDE.md                CLAUDE.md                    0
place rules/routing.md         rules/routing.md             0
place rules/bash-gotchas.md    rules/bash-gotchas.md        0
place output-styles/jadlis.md  output-styles/jadlis.md      0
place statusline-command.sh    statusline-command.sh        1

for h in session-start-title.sh rename-topic-from-prompt.sh _rename-apply.sh; do
	place "hooks/$h" "hooks/$h" 1
done

for s in claude-usage-fetch.sh tools-autoupdate.sh; do
	place "scripts/$s" "scripts/$s" 1
done

printf 'claude_home.path=%s\n' "$CLAUDE_HOME"
printf 'claude_home.differs=%s\n' "$DIFFERS"
exit 0

#!/bin/sh
# apply-shell.sh — the terminal half: $HOME/.tmux.conf and the `cld` block in $HOME/.zshrc.
#
# .zshrc is never rewritten: the block lives between two markers and is replaced in place,
# so running this twice leaves exactly one block.
#   # >>> jadlis-claudecode >>>
#   … assets/zshrc-jadlis.zsh …
#   # <<< jadlis-claudecode <<<
#
# .tmux.conf: written when absent. Present and different → left alone and reported, unless
# --force (the previous file is backed up).
#
# Usage: apply-shell.sh [--plan] [--force] [--assets DIR]
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
		*) printf 'apply-shell.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
	esac
done

BEGIN='# >>> jadlis-claudecode >>>'
END='# <<< jadlis-claudecode <<<'
ZSHRC="$HOME/.zshrc"
TMUXCONF="$HOME/.tmux.conf"
SRC_TMUX="$ASSETS/tmux.conf"
SRC_ZSH="$ASSETS/zshrc-jadlis.zsh"

[ -f "$SRC_TMUX" ] || { printf 'apply-shell.sh: no %s\n' "$SRC_TMUX" >&2; exit 1; }
[ -f "$SRC_ZSH" ]  || { printf 'apply-shell.sh: no %s\n' "$SRC_ZSH" >&2; exit 1; }

backup() {   # $1 file, $2 key
	_b="$1.bak-$(date +%Y%m%d-%H%M%S)"
	cp "$1" "$_b"
	printf '%s.backup=%s\n' "$2" "$_b"
}

# --- ~/.tmux.conf -----------------------------------------------------------
if [ ! -f "$TMUXCONF" ]; then
	if [ "$MODE" = plan ]; then
		echo "tmux_conf=WOULD-CREATE"
	else
		cp "$SRC_TMUX" "$TMUXCONF"
		echo "tmux_conf=WRITTEN"
	fi
elif cmp -s "$SRC_TMUX" "$TMUXCONF"; then
	echo "tmux_conf=UNCHANGED"
elif [ "$FORCE" = 1 ] && [ "$MODE" != plan ]; then
	backup "$TMUXCONF" tmux_conf
	cp "$SRC_TMUX" "$TMUXCONF"
	echo "tmux_conf=OVERWRITTEN"
else
	echo "tmux_conf=DIFFERS"
	diff -u "$TMUXCONF" "$SRC_TMUX" || true
fi

# --- ~/.zshrc block ---------------------------------------------------------
BLOCK=$(mktemp -t jc-zshblock)
NEWRC=$(mktemp -t jc-zshrc)
trap 'rm -f "$BLOCK" "$NEWRC"' EXIT

{
	printf '%s\n' "$BEGIN"
	cat "$SRC_ZSH"
	printf '%s\n' "$END"
} > "$BLOCK"

if [ -f "$ZSHRC" ]; then
	if grep -q "^$BEGIN\$" "$ZSHRC"; then
		# replace what is between the markers, keep everything else byte for byte
		awk -v b="$BEGIN" -v e="$END" -v f="$BLOCK" '
			$0 == b { skip = 1; while ((getline line < f) > 0) print line; close(f); next }
			$0 == e { skip = 0; next }
			!skip   { print }
		' "$ZSHRC" > "$NEWRC"
	else
		cat "$ZSHRC" > "$NEWRC"
		# one blank line between the recipient's own content and our block
		if [ -n "$(tail -c 1 "$NEWRC")" ]; then printf '\n' >> "$NEWRC"; fi
		printf '\n' >> "$NEWRC"
		cat "$BLOCK" >> "$NEWRC"
	fi
else
	cat "$BLOCK" > "$NEWRC"
fi

if [ -f "$ZSHRC" ] && cmp -s "$ZSHRC" "$NEWRC"; then
	echo "zshrc_block=UNCHANGED"
elif [ "$MODE" = plan ]; then
	echo "zshrc_block=WOULD-CHANGE"
	diff -u "${ZSHRC:-/dev/null}" "$NEWRC" 2>/dev/null || true
else
	if [ -f "$ZSHRC" ]; then backup "$ZSHRC" zshrc; fi
	cp "$NEWRC" "$ZSHRC"
	echo "zshrc_block=WRITTEN"
fi

printf 'zshrc_block.count=%s\n' "$(grep -c "^$BEGIN\$" "$ZSHRC" 2>/dev/null || echo 0)"
exit 0

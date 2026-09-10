#!/bin/sh
# apply-iterm.sh — install the Jadlis iTerm2 Dynamic Profile.
#
# Writes assets/iterm2-profile.json to
#   $HOME/Library/Application Support/iTerm2/DynamicProfiles/jadlis.json
# with the literal `$HOME/Jadlis` replaced by the real path: a dynamic profile is plain
# JSON and iTerm2 does no variable expansion in "Working Directory".
#
# Making it the default profile is a separate, opt-in step (--set-default):
#   defaults write com.googlecode.iterm2 "Default Bookmark Guid" <Guid from the JSON>
# The key name was verified against the machine's own plist
# (/usr/libexec/PlistBuddy -c 'Print "Default Bookmark Guid"' …/com.googlecode.iterm2.plist).
# `defaults` talks to cfprefsd and resolves the home directory from the login account, not
# from $HOME — so under a throwaway HOME the flag refuses to run instead of touching the
# real user's preferences.
#
# Usage: apply-iterm.sh [--plan] [--set-default] [--assets DIR]
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ASSETS="${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/.." && pwd)}/assets"
MODE=apply
SET_DEFAULT=0

while [ $# -gt 0 ]; do
	case "$1" in
		--plan)        MODE=plan; shift ;;
		--set-default) SET_DEFAULT=1; shift ;;
		--assets)      ASSETS="$2"; shift 2 ;;
		*) printf 'apply-iterm.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
	esac
done

SRC="$ASSETS/iterm2-profile.json"
DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
DST="$DIR/jadlis.json"
VAULT="$HOME/Jadlis"

[ -f "$SRC" ] || { printf 'apply-iterm.sh: no %s\n' "$SRC" >&2; exit 1; }

TMP=$(mktemp -t jc-iterm)
trap 'rm -f "$TMP"' EXIT

# $HOME/Jadlis → the real path. sed with | as the delimiter: a home directory has slashes.
sed "s|\$HOME/Jadlis|$VAULT|g" "$SRC" > "$TMP"

if command -v jq >/dev/null 2>&1; then
	jq -e . "$TMP" >/dev/null || { echo "apply-iterm.sh: profile is not valid JSON" >&2; exit 1; }
	GUID=$(jq -r '.Profiles[0].Guid // empty' "$TMP")
	WD=$(jq -r '.Profiles[0]."Working Directory" // empty' "$TMP")
else
	GUID=$(sed -n 's/.*"Guid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP" | head -1)
	WD="$VAULT"
fi
printf 'iterm_profile.guid=%s\n' "${GUID:-unknown}"
printf 'iterm_profile.workdir=%s\n' "${WD:-unknown}"

if [ "$MODE" = plan ]; then
	if [ -f "$DST" ] && cmp -s "$TMP" "$DST"; then
		echo "iterm_profile=UNCHANGED"
	else
		echo "iterm_profile=WOULD-WRITE"
		printf 'iterm_profile.path=%s\n' "$DST"
	fi
	exit 0
fi

mkdir -p "$DIR"
if [ -f "$DST" ] && cmp -s "$TMP" "$DST"; then
	echo "iterm_profile=UNCHANGED"
else
	cp "$TMP" "$DST"
	echo "iterm_profile=WRITTEN"
fi
printf 'iterm_profile.path=%s\n' "$DST"

# --- default profile --------------------------------------------------------
if [ "$SET_DEFAULT" = 0 ]; then
	printf 'iterm_default=SKIPPED\n'
	printf 'iterm_default.command=defaults write com.googlecode.iterm2 "Default Bookmark Guid" %s\n' "${GUID:-<Guid>}"
	exit 0
fi

LOGIN_HOME=$(eval echo "~$(id -un)")
if [ "$HOME" != "$LOGIN_HOME" ]; then
	printf 'iterm_default=REFUSED (HOME=%s is not the login home %s; `defaults` would write the real user preferences)\n' "$HOME" "$LOGIN_HOME"
	exit 0
fi
[ -n "$GUID" ] || { echo "iterm_default=FAILED (no Guid in the profile)"; exit 0; }

PREV=$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || echo "")
printf 'iterm_default.previous=%s\n' "${PREV:-none}"
defaults write com.googlecode.iterm2 "Default Bookmark Guid" "$GUID"
printf 'iterm_default=SET %s\n' "$GUID"
exit 0

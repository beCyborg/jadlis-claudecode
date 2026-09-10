#!/bin/sh
# apply-settings.sh — deep-merge assets/settings.template.json OVER the recipient's
# $HOME/.claude/settings.json with jq.
#
# Merge rules:
#   * the template wins for every key it defines (jq `*` merges objects in depth);
#   * keys only the recipient has survive, including `pluginSecrets`, `enabledPlugins`
#     and `pluginConfigs` — the template never mentions them;
#   * `env` merges key by key (deep `*`), so the recipient's own variables stay;
#   * `permissions.allow` and `permissions.deny` are unioned, not replaced — replacing
#     `deny` would silently widen permissions the recipient had narrowed on purpose.
#
# Usage:
#   apply-settings.sh              apply (backup kept next to the file)
#   apply-settings.sh --plan       print the unified diff, change nothing
#   apply-settings.sh --assets DIR use another assets directory
#
# Idempotent: a second run produces the same file and writes no backup.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ASSETS="${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/.." && pwd)}/assets"
MODE=apply

while [ $# -gt 0 ]; do
	case "$1" in
		--plan)   MODE=plan; shift ;;
		--apply)  MODE=apply; shift ;;
		--assets) ASSETS="$2"; shift 2 ;;
		*) printf 'apply-settings.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
	esac
done

TPL="$ASSETS/settings.template.json"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CFG="$CLAUDE_HOME/settings.json"

command -v jq >/dev/null 2>&1 || { echo "apply-settings.sh: jq is required" >&2; exit 1; }
[ -f "$TPL" ] || { printf 'apply-settings.sh: no template at %s\n' "$TPL" >&2; exit 1; }
jq -e . "$TPL" >/dev/null || { echo "apply-settings.sh: template is not valid JSON" >&2; exit 1; }

mkdir -p "$CLAUDE_HOME"
CUR=$(mktemp -t jc-settings-cur)
NEW=$(mktemp -t jc-settings-new)
trap 'rm -f "$CUR" "$NEW" "$CUR.s" "$NEW.s" "$NEW.diff"' EXIT

if [ -s "$CFG" ] && jq -e . "$CFG" >/dev/null 2>&1; then
	cp "$CFG" "$CUR"
else
	echo '{}' > "$CUR"
fi

jq -s '
	def uniqarr(a; b): (((a // []) + (b // [])) | unique);
	.[0] as $cur | .[1] as $tpl
	| ($cur * $tpl)
	| uniqarr($cur.permissions.allow; $tpl.permissions.allow) as $allow
	| uniqarr($cur.permissions.deny;  $tpl.permissions.deny)  as $deny
	| (if ($allow | length) > 0 then .permissions.allow = $allow else . end)
	| (if ($deny  | length) > 0 then .permissions.deny  = $deny  else . end)
' "$CUR" "$TPL" > "$NEW"

jq -e . "$NEW" >/dev/null || { echo "apply-settings.sh: merge produced invalid JSON, nothing written" >&2; exit 1; }

jq -S . "$CUR" > "$CUR.s"
jq -S . "$NEW" > "$NEW.s"
if diff -u "$CUR.s" "$NEW.s" > "$NEW.diff" 2>/dev/null; then
	CHANGED=0
else
	CHANGED=1
fi

if [ "$MODE" = plan ]; then
	if [ "$CHANGED" = 0 ]; then
		echo "settings=UNCHANGED"
	else
		echo "settings=WOULD-CHANGE"
		sed -e "s|$CUR.s|current settings.json|" -e "s|$NEW.s|after merge|" "$NEW.diff"
	fi
	exit 0
fi

if [ "$CHANGED" = 0 ]; then
	echo "settings=UNCHANGED"
else
	if [ -s "$CFG" ]; then
		BAK="$CFG.bak-$(date +%Y%m%d-%H%M%S)"
		cp "$CFG" "$BAK"
		printf 'settings.backup=%s\n' "$BAK"
	fi
	cp "$NEW" "$CFG"
	echo "settings=WRITTEN"
fi

jq -e . "$CFG" >/dev/null && printf 'settings.model=%s\n' "$(jq -r '.model // "?"' "$CFG")"
exit 0

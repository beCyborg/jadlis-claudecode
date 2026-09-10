#!/usr/bin/env python3
"""export-owner.py — export the owner's Claude Code / terminal setup into plugin assets.

Owner-side dev tool for jadlis-claudecode (lives in tools/ of that repo).
Usage: python3 tools/export-owner.py [--out assets]

Produces (under --out):
  settings.template.json   ~/.claude/settings.json minus secrets, personal MCP, plugin state
  CLAUDE.md                global CLAUDE.md as is
  rules/routing.md         routing without personal MCP lines
  rules/bash-gotchas.md    as is
  output-styles/jadlis.md  as is
  hooks/*.sh               session-start-title, rename-topic-from-prompt, _rename-apply
  statusline-command.sh, scripts/claude-usage-fetch.sh, scripts/tools-autoupdate.sh
  tmux.conf                ~/.tmux.conf as is
  zshrc-jadlis.zsh         the cld block (no cld2/cldday/cldweek)
  iterm2-profile.json      iTerm2 Dynamic Profile built from the owner's "Default" bookmark
Every text file is scanned: the owner's absolute home path → error, e-mail → error.
"""
from __future__ import annotations
import argparse, getpass, json, plistlib, re, shutil, subprocess, sys
from pathlib import Path

HOME = Path.home()
CC = HOME / ".claude"

# settings.json → template ------------------------------------------------------
DROP_TOP = {"enabledPlugins", "pluginConfigs", "extraKnownMarketplaces", "feedbackSurveyRate"}
# env variables whose NAME says the value is private (a host, a mailbox, any kind of key)
ENV_DROP_RE = re.compile(r"(_API_KEY|_KEY|_TOKEN|_SECRET|_EMAIL|_MAILTO|_IP|_HOST)$")
ENV_DROP: set[str] = set()
ALLOW_DROP_RE = re.compile(r"^(mcp__(reddit|ticktick|hn|substack|producthunt|hevy|playwright|firecrawl|brave-search|exa)__|Bash\(~/\.claude-code-docs)")
ALLOW_RENAME = {"mcp__plugin_browser_playwright__*": "mcp__plugin_jadlis-browser_playwright__*"}
# routing.md lines that name the owner's personal tools (dropped)
ROUTING_DROP_RE = re.compile(r"Reddit|Twitter|Вастрик|HN / Substack|/yandex-search|RU web|Claude Code docs")
# command forms that changed with the 2026-09-10 rename (plugin jadlis-<x>, bare command <x>)
TEXT_FIX = {"/browser:browser": "/browser", "/computer-use:computer-use": "/computer-use",
            f"-a {getpass.getuser()}": '-a "$USER"'}
def fix(s: str) -> str:
    for k, v in TEXT_FIX.items():
        s = s.replace(k, v)
    return s



def settings_template(src: dict) -> dict:
    out = {k: v for k, v in src.items() if k not in DROP_TOP}
    env = {k: v for k, v in src.get("env", {}).items() if not ENV_DROP_RE.search(k) and k not in ENV_DROP}
    out["env"] = env
    perms = dict(src.get("permissions", {}))
    allow = []
    for a in perms.get("allow", []):
        if ALLOW_DROP_RE.match(a):
            continue
        allow.append(ALLOW_RENAME.get(a, a))
    perms["allow"] = allow
    out["permissions"] = perms
    hooks = {}
    for ev, entries in src.get("hooks", {}).items():
        kept = []
        for e in entries:
            hs = [h for h in e.get("hooks", []) if "claude-docs-helper" not in h.get("command", "")]
            # firecrawl PDF guard is shipped by jadlis-search (its own hooks.json) — not here
            if "firecrawl" in e.get("matcher", ""):
                continue
            if hs:
                kept.append({**e, "hooks": hs})
        if kept:
            hooks[ev] = kept
    out["hooks"] = hooks
    sl = dict(out.get("statusLine", {}))
    if "command" in sl:
        sl["command"] = sl["command"].replace(str(HOME), "~")
    out["statusLine"] = sl
    # skillOverrides are owner-specific (his private skills) — keep only entries for built-ins
    so = src.get("skillOverrides", {})
    out["skillOverrides"] = {k: v for k, v in so.items() if k in {"init", "run", "simplify", "security-review", "fewer-permission-prompts", "keybindings-help"}}
    return out


def zshrc_block(text: str) -> str:
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("_tmux_server_alive()"))
    end = next(i for i, l in enumerate(lines) if l.startswith("# cld2 —"))
    block = lines[start:end]
    return "# jadlis-claudecode — terminal block (cld). Source: owner's ~/.zshrc, exported by tools/export-owner.py\n" \
           "alias cc='cld'\n" + "\n".join(block).rstrip() + "\n"


def json_safe(v):
    """Drop what JSON cannot carry: bytes, and non-finite floats (iTerm2 knobs hold Infinity).

    A dynamic profile is parsed with NSJSONSerialization, which rejects `Infinity`; the
    plist keeps it as a real float. 1e6 is "no limit" for a status-bar component width.
    """
    if isinstance(v, dict):
        return {k: json_safe(x) for k, x in v.items() if not isinstance(x, bytes)}
    if isinstance(v, list):
        return [json_safe(x) for x in v if not isinstance(x, bytes)]
    if isinstance(v, float) and (v != v or v in (float("inf"), float("-inf"))):
        return 1000000
    return v


def iterm_profile() -> dict:
    plist = plistlib.loads(subprocess.run(["plutil", "-convert", "xml1", "-o", "-", str(HOME / "Library/Preferences/com.googlecode.iterm2.plist")], capture_output=True, check=True).stdout)
    bm = next(b for b in plist["New Bookmarks"] if b.get("Name") == "Default")
    prof = {k: json_safe(v) for k, v in bm.items() if not isinstance(v, bytes)}
    prof["Name"] = "Jadlis"
    prof["Guid"] = "6A1D1D2E-0000-4A4A-9C9C-JADLIS000001"
    prof["Working Directory"] = "$HOME/Jadlis"  # replaced at install time
    prof["Custom Directory"] = "Yes"
    return {"Profiles": [prof]}


def scan(path: Path) -> list[str]:
    hits = []
    try:
        t = path.read_text(encoding="utf-8")
    except Exception:
        return hits
    for i, l in enumerate(t.splitlines(), 1):
        if str(HOME) in l:
            hits.append(f"{path}:{i}: absolute owner path")
        if re.search(r"[\w.+-]+@[\w-]+\.[a-z]{2,}", l) and "privacy-ok" not in l and "@jadlis" not in l:
            hits.append(f"{path}:{i}: e-mail")
        if re.search(r"\bsk[_-][A-Za-z0-9]{8,}|\bghp_[A-Za-z0-9]{10,}", l):
            hits.append(f"{path}:{i}: key-like token")
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--out", default="assets"); a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    (out / "settings.template.json").write_text(json.dumps(settings_template(json.loads((CC / "settings.json").read_text())), ensure_ascii=False, indent=2) + "\n")
    (out / "CLAUDE.md").write_text(fix((CC / "CLAUDE.md").read_text()))
    (out / "rules").mkdir(exist_ok=True)
    routing = [l for l in (CC / "rules/routing.md").read_text().splitlines() if not ROUTING_DROP_RE.search(l)]
    (out / "rules/routing.md").write_text(fix("\n".join(routing)) + "\n")
    (out / "rules/bash-gotchas.md").write_text(fix((CC / "rules/bash-gotchas.md").read_text().replace(str(HOME), "~")))
    (out / "output-styles").mkdir(exist_ok=True); shutil.copy(CC / "output-styles/jadlis.md", out / "output-styles/jadlis.md")
    (out / "hooks").mkdir(exist_ok=True)
    for h in ("session-start-title.sh", "rename-topic-from-prompt.sh", "_rename-apply.sh"):
        shutil.copy(CC / "hooks" / h, out / "hooks" / h)
    shutil.copy(CC / "statusline-command.sh", out / "statusline-command.sh")
    (out / "scripts").mkdir(exist_ok=True)
    for s in ("claude-usage-fetch.sh", "tools-autoupdate.sh"):
        shutil.copy(CC / "scripts" / s, out / "scripts" / s)
    shutil.copy(HOME / ".tmux.conf", out / "tmux.conf")
    (out / "zshrc-jadlis.zsh").write_text(zshrc_block((HOME / ".zshrc").read_text()))
    (out / "iterm2-profile.json").write_text(json.dumps(iterm_profile(), ensure_ascii=False, indent=2) + "\n")
    hits = [h for p in out.rglob("*") if p.is_file() for h in scan(p)]
    for h in hits:
        print("HIT", h)
    print(f"exported to {out}; {len(hits)} privacy hits")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())

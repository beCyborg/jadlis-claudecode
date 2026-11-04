#!/usr/bin/env python3
"""export-owner.py — export the owner's Claude Code / terminal setup into three repos.

Owner-side dev tool for jadlis-claudecode (lives in tools/ of that repo).
Usage: python3 tools/export-owner.py [--out assets] [--claude-md-repo DIR] [--styles-repo DIR]

Produces under --out (the jadlis-claudecode plugin):
  settings.template.json   ~/.claude/settings.json minus secrets, personal MCP, plugin state
  hooks/                   session-start-title, rename-topic-from-prompt, _rename-apply, bash-traps.py
  statusline-command.sh, scripts/: claude-usage-fetch.sh, tools-autoupdate.sh, ste-ru-lint.py, session-title.sh,
                           cu-autoapprove.sh + cu-autoapprove-hook.sh (computer-use dialog auto-approve in tmux),
                           plan-bypass-hook.sh (phone plan approval → bypass + clean context)
Produces under --claude-md-repo (default ~/jadlis-claude-md):
  CLAUDE.md                global CLAUDE.md minus owner-only sections (Codex, permissions, dictation)
  rules/routing.md         routing without personal tools; operator agents → plugin commands
  rules/bash-gotchas.md    minus the owner's Keychain/profile-B bullets
  scripts/ste-ru-lint.py   the writing-rules linter CLAUDE.md points at (same file as in the plugin)
Produces under --styles-repo (default ~/jadlis-output-styles):
  jadlis.md as is; jadlis-voice.md without the owner's play-button mod
  tmux.conf                ~/.tmux.conf as is
  zshrc-jadlis.zsh         the cld + tld block on plain `claude` (no profile B, no spawner, no cldday)
  iterm2-profile.json      iTerm2 Dynamic Profile built from the owner's "Default" bookmark
Every text file is scanned: the owner's absolute home path, login name, e-mail → error.
settings.json is read from the live profile: $CLAUDE_CONFIG_DIR, else ~/.claude-B (the owner's
only profile since 2026-09-30), else ~/.claude. --settings overrides.
"""
from __future__ import annotations
import argparse, getpass, json, os, plistlib, re, shutil, subprocess, sys
from pathlib import Path

HOME = Path.home()
CC = HOME / ".claude"
LIVE = Path(os.environ["CLAUDE_CONFIG_DIR"]) if os.environ.get("CLAUDE_CONFIG_DIR") else \
    (HOME / ".claude-B" if (HOME / ".claude-B/settings.json").exists() else CC)
USER = getpass.getuser()

# settings.json → template ------------------------------------------------------
DROP_TOP = {"enabledPlugins", "pluginConfigs", "extraKnownMarketplaces", "feedbackSurveyRate", "deniedMcpServers"}
# the template's own pins: the owner's live profile may hold a manual experiment (model "fable")
PIN = {"model": "claude-opus-5-5"}
# a recipient has no play-button mod, so Jadlis Voice would print a visible voice block under
# every answer — the template keeps the text style on and leaves Voice one /output-style away
PIN["outputStyle"] = "Jadlis"
# hooks the plugin ships; every other hook command in the owner's settings is his own infra
KEEP_HOOK_RE = re.compile(r"session-start-title\.sh|rename-topic-from-prompt\.sh|bash-traps\.py|ste-ru-lint\.py|cu-autoapprove-hook\.sh|plan-bypass-hook\.sh")
# env variables whose NAME says the value is private (a host, a mailbox, any kind of key)
ENV_DROP_RE = re.compile(r"(_API_KEY|_KEY|_TOKEN|_SECRET|_EMAIL|_MAILTO|_IP|_HOST)$")
ENV_DROP: set[str] = set()
ALLOW_DROP_RE = re.compile(r"^(mcp__(reddit|ticktick|hn|substack|producthunt|hevy|playwright|firecrawl|brave-search|exa)__|Bash\(~/\.claude-code-docs|Bash\(~/\.claude/scripts/docs-mirror)")
# deny rules for MCP servers and CLIs only the owner has
DENY_DROP_RE = re.compile(r"^(mcp__(21st|grok-mcp|twitterapi-mcp)__|Bash\((npx|pnpm|21st)\b|Bash\(.*grok|Bash\(.*(himalaya|smtplib|send\.toml|k02-mail|jm send))")
ALLOW_RENAME = {"mcp__plugin_browser_playwright__*": "mcp__plugin_jadlis-browser_playwright__*"}
# routing.md lines that name the owner's personal tools (dropped)
ROUTING_DROP_RE = re.compile(r"Screen time|Reddit|Twitter|Вастрик|HN / Substack|/yandex-search|RU web|Claude Code docs|^- Telegram|^- Operator runs")
# routing lines rewritten for the recipient: the owner routes through his own agents and accounts
ROUTING_REPLACE = {
    "- PDF →": "- PDF → `pdf-fetch.sh` from jadlis-search, then Read (path and escalation → /jadlis-search:search body); its hook blocks Firecrawl on PDF URLs (billed per page).",
    "- GitHub →": "- GitHub → `gh` / `gh api`: commit/push/PR → `/commit-commands:*`; PR review → `/code-review` (ultra for cloud). Never scrape GitHub via Brave.",
    "- Logged-in browser": "- Logged-in browser / interactive web UI → /jadlis-browser:browser (Playwright MCP). Not for public scraping (→ Firecrawl).",
    "- Native macOS apps": "- Native macOS apps, cross-app desktop → /jadlis-computer-use:computer-use, LAST resort: app MCP/CLI/API → /jadlis-browser:browser (web) → computer-use. Web tasks never via computer-use; terminal → Bash.",
}
# CLAUDE.md: sections (heading text) that hold the owner's own setup; a dropped heading takes its subsections
CLAUDE_DROP_SECTIONS = {"Scope", "Permissions", "Pasted input (dictation)", "Codex only"}
CLAUDE_LINE_DROP_RE = re.compile(r"^(Canonical source:|`/Users/.*AGENTS\.md`|The sections below apply only in Claude Code|Never write to ~/Jadlis/Система/Memory)")
CLAUDE_TEXT_FIX = {
    "# Shared Global Instructions": "# Global Instructions",
    "## Common — Claude Code and Codex": "## Common",
    "## Claude Code only": "## Claude Code",
    "; terminal visuals hands-off.": ".",
    "(see Pasted input → risky actions)": "(delete, send outward, payments, secrets)",
    "(e.g. day/week-relaunch approvals of tasks, carry-overs, focus)": "(e.g. approval of tasks or carry-overs)",
    "3.5% of my turn ends": "3.5% of the author's turn ends",
    " (23.08–23.09, `~/.claude/scripts/stop-rate.py`)": "",
    " (memory `models-and-effort`)": "",
    "invoke the matching skill (/github, /jadlis-search:search); logged-in browser work → the `browser-operator` subagent.":
        "invoke the matching skill (/jadlis-search:search); logged-in browser work → /jadlis-browser:browser.",
}
# bash-gotchas bullets about the owner's Keychain, profile B and Shortcuts
GOTCHA_DROP_RE = re.compile(r"on profile B|B blob|fresh-user simulation|writes `pluginSecrets` INTO|CLAUDE_CONFIG_DIR=~/\.claude-B claude plugin|^- `shortcuts sign")
GOTCHA_TEXT_FIX = {f"com.{USER}.": "com.<you>.", f"publish.obsidian.md/{USER}/": "publish.obsidian.md/<site>/"," Unquoted `=` words no longer break Bash: `setopt NO_EQUALS` under `$CLAUDECODE` in `~/.zshenv`.": ""}
# Jadlis Voice: the owner's Mac hides the voice block behind a play button (personal mod
# jadlis-voice-play, not shipped) — a recipient sees the block and selects it for TTS
VOICE_TEXT_FIX = {
    "— the Mac terminal hides that block behind a play button (mod jadlis-voice), the phone shows it for selection and the system voice":
        "— the reader selects that block and has a TTS voice read it aloud",
    "On the Mac the block is hidden and read by an expressive TTS voice (ElevenLabs Eleven v4, voice Nikolay, played at ×1.25); on the phone the reader selects it and has it read aloud.":
        "The reader selects the block and has it read aloud by an expressive TTS voice (ElevenLabs Eleven v4).",
}
# command forms that changed with the 2026-09-10 rename (plugin jadlis-<x>, bare command <x>)
TEXT_FIX = {"/browser:browser": "/browser", "/computer-use:computer-use": "/computer-use",
            f"-a {getpass.getuser()}": '-a "$USER"'}
def fix(s: str) -> str:
    for k, v in TEXT_FIX.items():
        s = s.replace(k, v)
    return s



def rename_hook(text: str) -> str:
    """Drop the owner's K02 staff naming (tmux nt-* sessions) from rename-topic-from-prompt.sh."""
    lines, out, skip = text.splitlines(), [], False
    for l in lines:
        if l.startswith("# Сотрудники NamedTop"):
            skip = True
        if skip:
            if l == "}":
                skip = False
            continue
        if l.strip().startswith("nt-*)"):
            continue
        out.append(l)
    s = "\n".join(out) + "\n"
    assert "namedtop" not in s.lower(), "rename hook still mentions NamedTop"
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
    perms["deny"] = [d for d in perms.get("deny", []) if not DENY_DROP_RE.match(d) and str(HOME) not in d]
    perms["ask"] = [d for d in perms.get("ask", []) if not DENY_DROP_RE.match(d) and str(HOME) not in d]
    if not perms["ask"]:
        perms.pop("ask")
    hooks = {}
    for ev, entries in src.get("hooks", {}).items():
        kept = []
        for e in entries:
            hs = [h for h in e.get("hooks", []) if KEEP_HOOK_RE.search(h.get("command", ""))]
            if hs:
                kept.append({**e, "hooks": hs})
        if kept:
            hooks[ev] = kept
    out["hooks"] = hooks
    out.update(PIN)
    sl = dict(out.get("statusLine", {}))
    if "command" in sl:
        sl["command"] = sl["command"].replace(str(HOME), "~")
    out["statusLine"] = sl
    # skillOverrides are owner-specific (his private skills) — keep only entries for built-ins
    so = src.get("skillOverrides", {})
    out["skillOverrides"] = {k: v for k, v in so.items() if k in {"init", "run", "simplify", "security-review", "fewer-permission-prompts", "keybindings-help"}}
    return out


def zshrc_block(text: str) -> str:
    """The owner's cld block, moved onto plain `claude`.

    The owner runs cld through ~/bin/claude-b (profile B) with a phone spawner on the side;
    a recipient has one profile, so the runner is `claude` and the session name has no _B.
    """
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("_tmux_server_alive()"))
    end = next(i for i, l in enumerate(lines) if l.startswith("# Claude Code behavior settings"))
    block, skip = [], False
    for l in lines[start:end]:
        if l.startswith("  # Дежурная сессия"):
            skip = True
        if skip:
            if "cld-spawn.sh" in l:
                skip = False
            continue
        block.append(l)
    body = "\n".join(block)
    cld_start = body.index("# cld — ")
    body = body[:cld_start] + (
        "# cld — всегда создаёт новую Claude Code session с auto-incremented suffix\n"
        "# (base, base_2, base_3, ...). base = имя проекта из git remote или basename($PWD).\n"
        "cld() {\n"
        "  _cld_spawn claude \"$(_cld_session_name)\" \"$@\"\n"
        "}\n")
    assert "claude-b" not in body and "cld-spawn" not in body, "zshrc block still holds owner-only lines"
    tl = text.splitlines()
    t0 = next(i for i, l in enumerate(tl) if l.startswith("# tld — "))
    t1 = next(i for i in range(t0, len(tl)) if tl[i] == "}")
    return "# jadlis-claudecode — terminal block (cld, tld). Source: owner's ~/.zshrc, exported by tools/export-owner.py\n" \
           "alias cc='cld'\n" + body.rstrip() + "\n\n" + "\n".join(tl[t0:t1 + 1]) + "\n"


def claude_md(text: str) -> str:
    out, drop_level = [], 0
    for l in text.splitlines():
        m = re.match(r"^(#{2,6}) (.+?)\s*$", l)
        if m:
            level = len(m.group(1))
            if drop_level and level > drop_level:
                continue
            drop_level = level if m.group(2) in CLAUDE_DROP_SECTIONS else 0
            if drop_level:
                continue
        elif drop_level:
            continue
        if CLAUDE_LINE_DROP_RE.match(l):
            continue
        out.append(l)
    s = "\n".join(out)
    for k, v in CLAUDE_TEXT_FIX.items():
        s = s.replace(k, v)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return fix(s).rstrip() + "\n"


def routing_md(text: str) -> str:
    out = []
    for l in text.splitlines():
        if ROUTING_DROP_RE.search(l):
            continue
        out.append(next((v for k, v in ROUTING_REPLACE.items() if l.startswith(k)), l))
    return fix("\n".join(out)) + "\n"


def gotchas_md(text: str) -> str:
    out = [l for l in text.splitlines() if not GOTCHA_DROP_RE.search(l)]
    s = "\n".join(out)
    for k, v in GOTCHA_TEXT_FIX.items():
        s = s.replace(k, v)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return fix(s.replace(str(HOME), "~")) + "\n"


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
    # Cmd+click on a path runs the owner's own opener script, which is not shipped → iTerm2 default
    if str(HOME) in json.dumps(prof.get("Semantic History", {})):
        prof.pop("Semantic History")
    prof["Name"] = "Jadlis"
    prof["Guid"] = "6A1D1D2E-0000-4A4A-9C9C-JADLIS000001"
    prof["Working Directory"] = "$HOME/Jadlis"  # replaced at install time
    prof["Custom Directory"] = "Yes"
    return {"Profiles": [prof]}


SKIP_SCAN_DIRS = {".git", "node_modules", "__pycache__", "img"}   # same as the hub's privacy-grep.py


def scan_tree(root: Path) -> list[str]:
    return [h for p in root.rglob("*")
            if p.is_file() and not SKIP_SCAN_DIRS.intersection(p.relative_to(root).parts)
            for h in scan(p)]


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
        if re.search(rf"(?<![A-Za-z]){re.escape(USER)}\b", l):
            hits.append(f"{path}:{i}: owner login name")
        if re.search(r"namedtop|\bK02\b", l, re.I):
            hits.append(f"{path}:{i}: owner's work project")
        if re.search(r"\bsk[_-][A-Za-z0-9]{8,}|\bghp_[A-Za-z0-9]{10,}", l):
            hits.append(f"{path}:{i}: key-like token")
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets")
    ap.add_argument("--claude-md-repo", default=str(HOME / "jadlis-claude-md"))
    ap.add_argument("--styles-repo", default=str(HOME / "jadlis-output-styles"))
    ap.add_argument("--settings")
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    md = Path(a.claude_md_repo).expanduser(); st = Path(a.styles_repo).expanduser()
    for d in (md, st):
        if not (d / ".git").is_dir():
            print(f"export-owner.py: {d} is not a git repo — clone or init it first", file=sys.stderr)
            return 2

    # --- jadlis-claudecode: settings, hooks, scripts, terminal ---------------------------
    ap_settings = Path(a.settings) if a.settings else LIVE / "settings.json"
    (out / "settings.template.json").write_text(json.dumps(settings_template(json.loads(ap_settings.read_text())), ensure_ascii=False, indent=2) + "\n")
    # instructions and styles moved to their own repos in 2.0.0 — never ship them here again
    for old in ("CLAUDE.md", "rules", "output-styles"):
        p = out / old
        if p.is_dir():
            shutil.rmtree(p)
        elif p.exists():
            p.unlink()
    (out / "hooks").mkdir(exist_ok=True)
    for h in ("session-start-title.sh", "_rename-apply.sh", "bash-traps.py"):
        shutil.copy(CC / "hooks" / h, out / "hooks" / h)
    rh = out / "hooks/rename-topic-from-prompt.sh"
    rh.write_text(rename_hook((CC / "hooks/rename-topic-from-prompt.sh").read_text()))
    rh.chmod(0o755)
    shutil.copy(CC / "statusline-command.sh", out / "statusline-command.sh")
    (out / "scripts").mkdir(exist_ok=True)
    for sc in ("claude-usage-fetch.sh", "tools-autoupdate.sh", "ste-ru-lint.py", "cu-autoapprove.sh", "cu-autoapprove-hook.sh", "plan-bypass-hook.sh"):
        shutil.copy(CC / "scripts" / sc, out / "scripts" / sc)
    # headless session namer called by rename-topic-from-prompt.sh; its PATH and claude binary are absolute
    (out / "scripts/session-title.sh").write_text((CC / "scripts/session-title.sh").read_text().replace(str(HOME), "$HOME"))
    shutil.copy(HOME / ".tmux.conf", out / "tmux.conf")
    (out / "zshrc-jadlis.zsh").write_text(zshrc_block((HOME / ".zshrc").read_text()))
    (out / "iterm2-profile.json").write_text(json.dumps(iterm_profile(), ensure_ascii=False, indent=2) + "\n")

    # --- jadlis-claude-md: instructions, rules, the linter they point at --------------------
    (md / "CLAUDE.md").write_text(claude_md((CC / "CLAUDE.md").read_text()))
    (md / "rules").mkdir(exist_ok=True)
    (md / "rules/routing.md").write_text(routing_md((CC / "rules/routing.md").read_text()))
    (md / "rules/bash-gotchas.md").write_text(gotchas_md((CC / "rules/bash-gotchas.md").read_text()))
    (md / "scripts").mkdir(exist_ok=True)
    shutil.copy(CC / "scripts/ste-ru-lint.py", md / "scripts/ste-ru-lint.py")

    # --- jadlis-output-styles: both styles, Voice without the owner's play-button mod ------
    shutil.copy(CC / "output-styles/jadlis.md", st / "jadlis.md")
    voice = (CC / "output-styles/jadlis-voice.md").read_text()
    for k, v in VOICE_TEXT_FIX.items():
        assert k in voice, f"jadlis-voice.md changed, VOICE_TEXT_FIX is stale: {k[:60]}"
        voice = voice.replace(k, v)
    (st / "jadlis-voice.md").write_text(voice)

    hits = [h for root in (out, md, st) for h in scan_tree(root)]
    for h in hits:
        print("HIT", h)
    print(f"exported to {out}, {md}, {st}; {len(hits)} privacy hits")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())

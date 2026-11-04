#!/usr/bin/env python3
"""PreToolUse(Bash) hook: fix or block the deterministic traps from ~/.claude/rules/bash-gotchas.md.

Decided 2026-10-02 (vault note «Моды Claude Code — что нам дают»): text rules stop tool-choice
mistakes within a day or two, but not traps that fire while a command is being composed.
A classic hook was chosen over a Claude mod: same power here (updatedInput, agent_id),
stable API, no worktree-isolation bug (#92533).

Rewrites (the command still runs, Claude gets a one-line note):
  - `codex exec` with no stdin redirect      -> append `< /dev/null` (hangs until timeout otherwise)
  - `find /tmp…`                              -> `find /private/tmp…` (BSD find does not follow the symlink)
  - `obsidian` inside a `while … read` loop   -> append `< /dev/null` (it swallows the loop's input)
Blocks (deny with the reason):
  - `gh gist create`                          -> the gist + URL-shortener combo got beCyborg suspended (29.09)
  - osascript telling iTerm2 to create a window -> hung iTerm2 and the tmux server (30.09)
  - recursive grep / xargs grep over ~/.claude/projects -> 28 min at 100% CPU (23.09)

Escape hatch: a `# traps-ok` comment in the command, or BASH_TRAPS_OFF=1 in the environment.
Any internal error -> exit 0 with no output (the command runs unchanged). Log: ~/.claude/logs/bash-traps.log
"""
import json
import os
import re
import shlex
import sys
import time

LOG = os.path.expanduser("~/.claude/logs/bash-traps.log")
SEPARATORS = ("&&", "||", ";", "|", "&", "\n", "(", ")")
WRAPPERS = {"env", "command", "nohup", "time", "exec", "builtin", "caffeinate"}
KEYWORDS = {"do", "then", "else", "elif", "{", "!"}
PROJECTS_ROOT = re.compile(r"^(~|\$HOME|/Users/[^/]+)/\.claude/projects/?(\*(\.jsonl)?)?/?$")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def heredoc_spans(cmd):
    """Spans of here-document bodies (their text is data, never commands)."""
    spans = []
    for m in HEREDOC.finditer(cmd):
        body_start = cmd.find("\n", m.end())
        if body_start == -1:
            continue
        end_re = re.compile(r"^\t*" + re.escape(m.group(2)) + r"[ \t]*$", re.M)
        end = end_re.search(cmd, body_start + 1)
        spans.append((body_start + 1, end.end() if end else len(cmd)))
    return spans


def segments(cmd):
    """Top-level simple commands as (start, end, prev_sep) spans; quotes and here-doc bodies respected."""
    skip = heredoc_spans(cmd)
    out, start, i, quote, prev = [], 0, 0, None, None
    n = len(cmd)
    while i < n:
        hit = next((e for s, e in skip if s <= i < e), None)
        if hit is not None:
            i = start = hit
            continue
        c = cmd[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if c in "'\"":
            quote = c
            i += 1
            continue
        if c == "#" and (i == 0 or cmd[i - 1] in " \t\n;&|("):
            nl = cmd.find("\n", i)
            i = n if nl == -1 else nl
            continue
        sep = next((s for s in SEPARATORS if cmd.startswith(s, i)), None)
        redirect_amp = sep == "&" and (cmd.startswith("&>", i) or (i > 0 and cmd[i - 1] in "<>"))
        if sep and not redirect_amp and not (sep == "|" and i > 0 and cmd[i - 1] == ">"):
            out.append((start, i, prev))
            prev = sep
            i += len(sep)
            start = i
            continue
        i += 1
    out.append((start, n, prev))
    return [(s, e, p) for s, e, p in out if cmd[s:e].strip()]


def words(text):
    try:
        return shlex.split(text, comments=True)
    except ValueError:
        return []


def command_words(ws):
    """Drop leading VAR=value assignments and wrapper commands; keep the rest."""
    i = 0
    while i < len(ws):
        w = ws[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w) or w in WRAPPERS or w in KEYWORDS or w.startswith("-") and i > 0 and ws[i - 1] in WRAPPERS:
            i += 1
            continue
        break
    return ws[i:]


def base(word):
    return word.rsplit("/", 1)[-1]


def has_stdin(text):
    """An unquoted `<` redirect (incl. here-doc / here-string) inside one segment."""
    q = None
    for i, c in enumerate(text):
        if q:
            if c == q:
                q = None
            continue
        if c in "'\"":
            q = c
        elif c == "<" and not (i + 1 < len(text) and text[i + 1] == "("):
            return True
    return False


def is_codex_exec(ws):
    for i, w in enumerate(ws[:-1]):
        if base(w) == "codex" and ws[i + 1] == "exec":
            return True
    return False


def check(cmd):
    """Return (new_command_or_None, notes, deny_reason_or_None)."""
    segs = segments(cmd)
    inserts, notes = [], []
    new = cmd
    loop = re.search(r"\bwhile\b[^\n]*\bread\b", cmd) is not None

    for s, e, prev in segs:
        text = cmd[s:e]
        ws = command_words(words(text))
        if not ws:
            continue
        head = base(ws[0])
        lower = text.lower()

        if head == "gh" and ws[1:3] == ["gist", "create"]:
            return None, [], ("bash-traps: `gh gist create` is blocked — a gist plus a URL shortener got the "
                              "beCyborg account suspended within a minute (29.09.2026). Files for a phone or "
                              "another PC go to Obsidian Publish. Add `# traps-ok` only if the owner asked for a gist.")
        if head in ("grep", "egrep", "fgrep", "ggrep") or (head == "xargs" and any(base(w) in ("grep", "egrep") for w in ws[1:])):
            recursive = head == "xargs" or any(re.match(r"^-[A-Za-z]*[rR]", w) or w in ("--recursive", "--dereference-recursive") for w in ws[1:])
            narrowed = re.search(r"--changed-within|-mtime|-mmin|-newer", cmd) is not None
            hits_root = (any(PROJECTS_ROOT.match(w) for w in ws[1:]) if head != "xargs"
                         else any(PROJECTS_ROOT.match(w) for w in words(cmd)) and not narrowed)
            if recursive and hits_root:
                return None, [], ("bash-traps: recursive grep over ~/.claude/projects is blocked — ~9 GB of session "
                                  "logs, it once ran 28 min at 100% CPU (23.09.2026). Use "
                                  "`fd --changed-within 7d -e jsonl . ~/.claude/projects | xargs rg …` with a bounded pattern.")

        if is_codex_exec(ws) and prev != "|" and not has_stdin(text):
            inserts.append((e, " < /dev/null"))
            notes.append("codex exec: appended `< /dev/null` (the Bash tool never closes stdin, codex waits for EOF)")
        if head == "obsidian" and loop and not has_stdin(text):
            inserts.append((e, " < /dev/null"))
            notes.append("obsidian in a while-read loop: appended `< /dev/null` (it would swallow the loop's input)")
        if head == "find" and any(w == "/tmp" or w.startswith("/tmp/") for w in ws[1:]):
            fixed = re.sub(r"(^|\s)(['\"]?)/tmp(?=[/'\"\s]|$)", r"\1\2/private/tmp", text)
            if fixed != text:
                inserts.append((s, ("replace", e, fixed)))
                notes.append("find /tmp: rewrote to /private/tmp (BSD find does not follow the /tmp symlink)")

    osa = next((cmd[s:] for s, e, _ in segs if command_words(words(cmd[s:e]))[:1] == ["osascript"]), "")
    if osa and re.search(r"iterm", osa, re.I) and re.search(r"create\s+window", osa, re.I):
        return None, [], ("bash-traps: osascript creating an iTerm2 window is blocked — from a tmux-hosted session "
                          "it hung iTerm2 and the tmux server on 30.09.2026, and recovery kills every session. "
                          "Test terminal behaviour in a detached `tmux new-session -d` + `capture-pane`.")

    if not inserts:
        return None, [], None
    for pos, what in sorted(inserts, key=lambda x: x[0], reverse=True):
        if isinstance(what, tuple):
            _, end, fixed = what
            new = new[:pos] + fixed + new[end:]
        else:
            head, tail = new[:pos].rstrip(), new[pos:]
            new = head + what + (" " if tail and not tail[0].isspace() and tail[0] not in ";)" else "") + tail
    return new, notes, None


def log(entry):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def main():
    try:
        data = json.load(sys.stdin)
        if data.get("tool_name") != "Bash" or os.environ.get("BASH_TRAPS_OFF") == "1":
            return 0
        tool_input = data.get("tool_input") or {}
        cmd = tool_input.get("command") or ""
        if "# traps-ok" in cmd:
            return 0
        new, notes, deny = check(cmd)
        if not deny and not new:
            return 0
        entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "session": data.get("session_id"),
                 "agent": data.get("agent_id"), "action": "deny" if deny else "rewrite",
                 "notes": [deny] if deny else notes, "cmd": cmd[:300]}
        log(entry)
        if deny:
            out = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                          "permissionDecision": "deny",
                                          "permissionDecisionReason": deny}}
        else:
            out = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                          "updatedInput": dict(tool_input, command=new),
                                          "additionalContext": "bash-traps: " + "; ".join(notes)}}
        sys.stdout.write(json.dumps(out, ensure_ascii=False))
        return 0
    except Exception:  # fail open: never break a command because the guard broke
        return 0


if __name__ == "__main__":
    sys.exit(main())

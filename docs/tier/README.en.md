[Русский](README.md) · English

# Tier 0 — your workplace

A subscription, an app, one command. At the end Claude Code is set up one to one with my
machine: the language, the answer-shaping rules, memory, the terminal and the folder
where the notes live.

## Why

Eighty percent of the result comes from context about your life; twenty from the task
itself. Without that context the agent guesses — and gets it convincingly wrong.

Tier 0 builds the place where the context accumulates: a configured Claude Code, memory
switched on, the `~/Jadlis` working folder and a terminal that opens right inside it.
Everything else on the route sits on top of it.

The `jadlis-claudecode` plugin does this with one command, not with a twenty-step manual.

## What it looks like

![A computer on a desk, robotic arms reaching out of the screen to handle a calendar, a chart, an envelope and a folder](https://github.com/beCyborg/jadlis-hub/blob/main/docs/img/hub-12.webp?raw=1)

What `/claudecode` shows before writing settings:

```diff
--- current ~/.claude/settings.json
+++ after merge
+  "model": "opus[1m]",
+  "language": "Russian",
+  "outputStyle": "Jadlis",
+  "effortLevel": "high",
+  "autoMemoryEnabled": true,
+  "permissions": { "defaultMode": "bypassPermissions" }

Apply? A backup stays next to it: settings.json.bak-20260910-181500
```

## Install

Three steps before the plugin, then one command.

1. **A Claude subscription.** You need the **Max** plan: the settings template sets
   `model: "opus[1m]"` — Opus with a 1M-token window — and on Pro that model burns usage
   credits. Terms and pricing live on claude.ai.
2. **The Claude Code desktop app.** Download it from the
   [install page](https://code.claude.com/docs/en/desktop-quickstart), sign in, open the
   **Code** tab and pick a folder.
3. **The `claude` CLI.** The app does **not** install it — and `claude plugin …`
   commands need it. `/claudecode` installs it itself, or do it by hand:
   `curl -fsSL https://claude.ai/install.sh | bash`.

Then paste this block into Claude Code as is:

```text
You are an installer. Run exactly these steps and nothing else:
1. Bash: claude plugin marketplace add https://github.com/beCyborg/jadlis-hub
2. Bash: claude plugin install jadlis-claudecode@jadlis
3. Tell me: "Type /claudecode"
Read nothing, create nothing, install nothing beyond this.
```

By hand — the same two commands in a terminal:

```bash
claude plugin marketplace add https://github.com/beCyborg/jadlis-hub
claude plugin install jadlis-claudecode@jadlis
```

The full HTTPS URL is required: the short `owner/repo` form clones over SSH, and a new
user usually has no SSH key.

## Usage

One command. It asks first and shows a diff before changing anything.

```text
/claudecode          # the whole route: probe → dependencies → terminal → ~/Jadlis → ~/.claude → wrap-up
/claudecode статус   # the PASS/FAIL probe only, installs nothing and changes nothing
```

Three runs:

- Clean Mac: `/claudecode`, then step by step.
- Claude Code already configured, only the terminal is missing: run `/claudecode` and
  answer "skip" at step 5 — the settings merge touches nothing without an explicit yes.
- You need the notes folder and its structure: that is the next plugin, `/jadlis-obsidian`.

**Check it with one action.** Open a new iTerm2 tab. It should open in `~/Jadlis`; type
`cld` and a tmux session named after the folder comes up with Claude Code running in it.
It worked — tier 0 is closed, next is `/jadlis-hub`.

## Limits and cost

What tier 0 does **not** do:

- It does not buy the subscription or install the app for you — those are steps 1–2 above.
- It does not build the methodology folder structure and does not create metrics.
- It does not create API keys: those live in the macOS Keychain and arrive later.
- It never silently overwrites an existing `settings.json`, `.zshrc` or `~/.tmux.conf` —
  it merges, appends between markers, or asks.
- It does not work outside macOS: the iTerm2 dynamic profile, `defaults` and Homebrew
  are Mac things.

Cost: you need a Claude Max subscription and macOS. Homebrew, git, jq, Node.js,
python@3.13, uv, poppler, tmux, iTerm2 and the font are free. Tier 0 makes no paid
requests at all.

## Desktop or terminal

This tier installs the terminal route, because everything else stands on it: `cld`, tmux
sessions, the status line and scheduled runs of the rituals.

Shared by both: the same `CLAUDE.md`, `~/.claude/settings.json`, MCP servers, hooks,
skills, plugins and models. Configure it in one, it works in the other.

| Terminal only | Desktop only |
|---|---|
| the `bypassPermissions` mode with no dialogs | Dispatch sessions in the sidebar |
| `--print` and the Agent SDK — your own scheduled runs (`launchd`, `cron`) | scheduled tasks inside the app |
| the status line and terminal dialog commands (`/permissions`, `/config`, `/keybindings`) | chat, diff, terminal, file and browser panes |
| agent teams | a separate git worktree per parallel session |
| Remote Control — the session runs on your machine, you continue it from your phone | attachments: images and PDFs straight into the prompt |

Separately: the app does **not** install the `claude` CLI. It ships its own embedded
engine, but `claude …` commands in Bash come from a separate install — `/claudecode`
handles that.

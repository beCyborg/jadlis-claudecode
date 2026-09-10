## Language
- Chat replies and vault deliverables (notes, plans, research, reports) — Russian.
- Code, identifiers, commit messages, CLI commands — English.
- Configuration text (CLAUDE.md, rules, skill/agent/workflow descriptions), MEMORY.md index and memory notes — English.
Why: output language drifted to English in long sessions; English config halves startup-context tokens (2026-09-06).

## Change plans (plan mode)
An implementation plan that may go to /verif uses exactly these headings — the skill parses them:
Context · Evidence (file:line + what is there) · Assumptions (Safe/Risky/Dangerous + what breaks) · Alternatives Considered · Risk Assessment (at zero / at scale / mid-stream / on-failure / adversarial) · Verification (+ "where I'm unsure what to check") · References.
Section size ∝ change size; a small fix needs Context + Evidence + Verification. Everyday plans (moving, clinic, trip) skip this frame.

## Tool routing
Canon — ~/.claude/rules/routing.md (always loaded). Unsure which tool → invoke the matching skill (/github, /browser, /search).

## Subagents, Workflow, deep-research
Standing request: use subagents, the Workflow tool and deep-research wherever a skill or an accepted plan provides for them; no per-launch permission needed. Why: Claude Code's Opus 5 delegation instruction requires an explicit user request (CC 2.1.245, anthropics/claude-code#80988) — this is that request.
Bulk edits and generation (many files, note batches, memory packing) go to Opus 5 subagents; Fable plans, reviews and decides. Why: on the Max plan Fable burns ~2× the window of Opus and is capped at 50% of the weekly quota.
This standing request does not go into leaf agents (advisor-*, researcher-*, orchestrator-*): they must not spawn nested agents. An orchestrator subagent that should fan out needs it asked for explicitly in its task prompt.
In plan mode subagents are read-only: ask them for inline reports, or launch them before EnterPlanMode. Why: plan-mode agents cannot write files (2026-09-05). Agents launched before a plan interrupt keep running and writing files — before re-running a plan step check `ListAgents` and `ls -la` the target workDir, and give duplicates different output filenames.
Recon agents fabricate CLI/model/version facts — run the command yourself before recording them.

## Permissions
`permissions.defaultMode` = `bypassPermissions` is a deliberate choice after a full research round (July 2026) — do not propose auto mode; `/doctor` will offer it, decline. Revisit only on new inputs (an injection incident, a container, the user asking).

## Memory
Auto memory is for facts that survive sessions and are not derivable from files: who the user is, corrections and confirmed approaches (with why), project decisions, external pointers.
Not memory — route these instead:
- Tool, CLI and MCP gotchas → the owning skill body. Own skills are edited directly; a generated skill is edited in its plugin source.
- A gotcha that fires while composing a command, not while editing a file → `~/.claude/rules/bash-gotchas.md`. Why: a path-scoped rule loads only once a matching file is read, so path-scoping fits file-editing gotchas only.
- Dated status snapshots → the project note or the plan, with an expiry date if kept.
MEMORY.md is index only, ≤80 lines; clusters go to index-*.md. Why: MEMORY.md is loaded every session and truncates at 200 lines / 25 KB.
Never write to ~/Jadlis/Система/Memory without an explicit request — it is the user's curated layer.

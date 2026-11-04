# Changelog — jadlis-claudecode

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).

## [2.0.0] — 2026-11-04 — Три репо на GitHub / Three repos on GitHub

### Для человека
- Плагин переехал на GitHub: `becyb-org/jadlis-claudecode`. Ставится прямо оттуда, без
  хаба: `claude plugin marketplace add https://github.com/becyb-org/jadlis-claudecode.git`,
  затем `claude plugin install jadlis-claudecode@jadlis-claudecode`.
- `CLAUDE.md`, `rules/` и стили ответа теперь живут в своих репо:
  [jadlis-claude-md](https://github.com/becyb-org/jadlis-claude-md) и
  [jadlis-output-styles](https://github.com/becyb-org/jadlis-output-styles). `/claudecode`
  ставит их новым необязательным шагом 5. Файлы, которые поставила 1.x, остаются на месте.
- `jadlis-notifications` больше не приезжает зависимостью. Поставь его явно:
  `claude plugin install jadlis-notifications@jadlis`, иначе `claude plugin prune` его удалит.
- В сетап вошёл переход в bypass после одобрения плана с телефона. Отдельный плагин
  `jadlis-plan-bypass` рядом не ставь: хук сработает дважды.
- Строка состояния показывает только недельный лимит.
- Лицензия: Apache-2.0.

### For agents
- BREAKING: `assets/CLAUDE.md`, `assets/rules/`, `assets/output-styles/` removed;
  `apply-claude-home.sh` no longer places them. They are exported by
  `tools/export-owner.py --claude-md-repo DIR --styles-repo DIR` into the two new repos.
- BREAKING: `plugin.json` drops `dependencies` (`jadlis-notifications ^1`); `homepage` and
  `repository` → `https://github.com/becyb-org/jadlis-claudecode`; `license: Apache-2.0`.
- Added: `.claude-plugin/marketplace.json` (marketplace `jadlis-claudecode`, source `./`).
- Added: `assets/scripts/plan-bypass-hook.sh` + template hook `PostToolUse` `ExitPlanMode`
  (`KEEP_HOOK_RE`); placed by `apply-claude-home.sh`, checked by `probe.sh` (`claude_scripts`).
- Changed: `probe.sh` — `output_style` and `rules` are `PASS|WARN` (never FAIL), with an
  `.info` hint pointing at the repo to install.
- Changed: `apply-settings.sh` drops the template's `ste-ru-lint` hook unless
  `$CLAUDE_HOME/CLAUDE.md` has a «Writing for people» section; prints `settings.lint_hook=`.
- Changed: `SKILL.md` — 9 steps: new step 5 (clone + `install.sh --plan` of both repos),
  notifications optional (step 8), plan-bypass hook explained in step 6.
- Changed: `export-owner.py` — three targets, scanner skips `.git`/`node_modules`/`img` and
  flags the owner's work project; drops the K02 staff-naming block from the rename hook.
- Changed (owner export): statusline shows the weekly limit only; `Read`/`Edit` allow rules
  without `(*)`.
- CI: `.gitlab-ci.yml` → `.github/workflows/ci.yml` (validate --strict on CLI 2.1.263,
  gitleaks full history, README parity, privacy grep; tools vendored in `tools/ci/`).

## [1.3.0] — 2026-11-02 — Автоподтверждение computer use / Computer-use auto-approve

### Для человека
- Окно «Computer Use wants to control these apps» больше не ждёт клика: в сессии внутри
  tmux (`cld`) скрипт сам нажимает «Allow for this session». Так Claude может работать с
  приложениями Мака, пока ты с телефона или не у экрана.
- Можно запретить отдельные приложения: одна строка в `~/.config/jadlis/cu-deny-apps` —
  им скрипт отвечает отказом, и Claude сообщает об этом, а не ждёт.
- Вне tmux ничего не меняется: окно ждёт тебя, как раньше.

### For agents
- Added: `assets/scripts/cu-autoapprove.sh` (pane watcher: detects the dialog by its title +
  anchored Deny/(esc) line + cursor, sends Down+Enter / Enter, Esc for deny-listed apps; rate
  limit 6 actions/60 s) and `assets/scripts/cu-autoapprove-hook.sh` (PreToolUse
  `mcp__computer-use__.*`: starts or extends the watcher for `$TMUX_PANE`, TTL 90 s).
- Added: template hook `PreToolUse` `mcp__computer-use__.*` → `~/.claude/scripts/cu-autoapprove-hook.sh`.
- Changed: watcher takes the tmux socket from `$TMUX` (was the owner's uid path); optional deny
  list `~/.config/jadlis/cu-deny-apps` (first non-# line, ERE on the dialog's `◉ <app>` lines).
- Changed: `apply-claude-home.sh` and `probe.sh` place/check both scripts; `export-owner.py` keeps
  the hook and exports both scripts.
- Changed (owner export): `syncClaudeAiSkills`/`syncClaudeAiPlugins: false`; Opus 4.8 effort `high`.
- Tested: live run in an isolated tmux server against a rendered dialog — an allowed app got
  Down+Enter, `1Password` with the deny list got Esc.

## [1.2.0] — 2026-10-24 — Новый Jadlis Voice / New Jadlis Voice

### Для человека
- Стиль Jadlis Voice теперь даёт полный ответ на экране, а в конце — блок «🔊 Голосом»:
  тот же ответ, пересказанный для слуха. Блок выделяют и отдают голосовому движку.
  Раньше стиль давал только устный ответ без разметки.
- По умолчанию по-прежнему включён текстовый стиль Jadlis. Jadlis Voice включается
  через `/output-style`.
- Свежая выгрузка правил: для русского поиска Exa теперь `--type auto`, в ловушки Bash
  добавлен встроенный `log` в zsh.

### For agents
- Changed: `assets/output-styles/jadlis-voice.md` — the owner's 2026-10-22 style (screen part +
  trailing `## 🔊 Голосом` block); `tools/export-owner.py` `VOICE_TEXT_FIX` rewrites the two
  lines about the owner's play-button mod (`jadlis-voice-play`, not shipped) for a recipient.
- Changed: `tools/export-owner.py` — `PIN["outputStyle"] = "Jadlis"` (the owner's live default
  is now Jadlis Voice); `ROUTING_DROP_RE` drops the owner's screen-time (`jtt`) line;
  `DENY_DROP_RE` also drops the owner's mail guards (himalaya, smtplib, `send.toml`,
  `k02-mail`, `jm send`) and now filters `permissions.ask` too (empty → removed).
- Changed: `assets/rules/routing.md` (Exa RU `--type auto`), `assets/rules/bash-gotchas.md`
  (zsh `log` builtin), `assets/settings.template.json` (`idleCompaction: false`).
- Changed: `skills/claudecode/SKILL.md` step 6 and `references/settings.md` describe the new
  style; `version` 1.1.0 → 1.2.0.

## [1.1.0] — 2026-10-08 — Свежая выгрузка и переезд на GitLab / Fresh export and move to GitLab

### Для человека
- `CLAUDE.md` теперь полный: как понять задачу, довести её до проверки и отчитаться, плюс
  правила письма для людей (STE-RU — короткие фразы, действующий залог, без канцелярита).
  Личные разделы владельца (Codex, разрешения, диктовка) в выгрузку не попадают.
- Второй стиль ответа — Jadlis Voice: для ответов, которые читает вслух голосовой движок.
  Основной стиль Jadlis обновлён: результат первым, «От тебя:» последней строкой, без
  поддакивания и без спора ради спора.
- Два новых хука: `bash-traps.py` ловит известные ловушки в командах Bash, а проверка
  STE-RU показывает агенту фразы заметки, которые нарушают правила письма.
- `cld` запускает Opus 5.5 вместо старого `fable[1m]`; новая команда `tld` показывает
  tmux-сессии с заголовками Claude Code.
- Плагин и каталог `jadlis` теперь на GitLab: установка через
  `https://gitlab.com/beCyborg/jadlis-hub.git`.

### For agents
- Changed: `tools/export-owner.py` — settings source is the live profile
  (`$CLAUDE_CONFIG_DIR` → `~/.claude-B` → `~/.claude`, `--settings` overrides); hooks are a
  whitelist (`KEEP_HOOK_RE`: session-start-title, rename-topic-from-prompt, bash-traps,
  ste-ru-lint); `deniedMcpServers` dropped; deny rules for owner-only MCP/CLIs dropped;
  `model` pinned to `claude-opus-5-5`; CLAUDE.md filtered by section
  (`CLAUDE_DROP_SECTIONS`) and line; routing lines for owner agents/accounts rewritten to
  plugin commands; bash-gotchas bullets on Keychain/profile B/Shortcuts dropped; zsh block
  rebuilt from the owner's (runner `claude`, no spawner, `+ tld`); iTerm2
  `Semantic History` dropped when it points at an unshipped owner script; scan also flags
  the owner's login name.
- Added: `assets/output-styles/jadlis-voice.md`, `assets/hooks/bash-traps.py`,
  `assets/scripts/ste-ru-lint.py`, `assets/scripts/session-title.sh` (paths → `$HOME`).
- Changed: `scripts/apply-claude-home.sh`, `scripts/probe.sh` — place and check the new files.
- Changed: `assets/settings.template.json` — PreToolUse(Bash) `bash-traps.py`,
  PostToolUse(Write|Edit|MultiEdit) `ste-ru-lint.py --hook`,
  `env.CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS=36`, `subagentPromptCacheTtl: 1h`,
  `modelSettings.claude-opus-4-8.effortLevel: xhigh`, allow for `jadlis-search` plugin MCPs.
- Changed: `.github/workflows/ci.yml` → `.gitlab-ci.yml` (hub `/ci/plugin-ci.yml`); all
  `github.com/beCyborg/*` links → `gitlab.com/beCyborg/*`; `version` 1.0.2 → 1.1.0.
- Migration: re-run `/claudecode`. `apply-settings.sh` deep-merges, so keys the template
  no longer carries (`alwaysThinkingEnabled`, `teammateMode`, …) stay in an existing
  `settings.json`; changed asset files show as `DIFFERS` and need `--force`.

## [1.0.2] — 2026-09-22 — Opus 5.5 на effort high / Opus 5.5 at effort high

### Для человека
- Шаблон настроек ставит Opus 5.5 на effort `high` вместо `xhigh`: по разбору Opus 5.5 от
  22.09.2026 `xhigh` окупается только у одиночных агентов в конце цепочки, а на коде и в
  массовых субагентах лишь быстрее расходует недельную квоту.
- `xhigh` остаётся точечно, в настройках самого агента: анализ и синтез, валидаторы,
  критики, операторы браузера и рабочего стола.

### For agents
- Changed: `assets/settings.template.json` — `modelSettings.claude-opus-5-5.effortLevel`
  `xhigh` → `high` (top-level `effortLevel: high` and the `claude-fable-5-1` /
  `claude-opus-5` entries unchanged).
- Changed: `README.md`, `README.en.md` (token-spend paragraph),
  `skills/claudecode/references/settings.md` (`modelSettings` row) — Opus 5.5 default is
  `high`; `xhigh` only for single end-of-chain agents (analysis/synthesis, validators,
  critics) and the browser/desktop operators, set per agent, not per session; the settings
  row also says how to raise effort for one session (`s` in the `/effort` slider) without
  saving it as the default.
- Changed: `.claude-plugin/plugin.json` — `version` 1.0.1 → 1.0.2.
- Migration: existing installs keep `xhigh` until `/claudecode` is re-run —
  `apply-settings.sh` deep-merges the template over `settings.json`, so the re-run sets
  `modelSettings.claude-opus-5-5.effortLevel` to `high`.

## [1.0.1] — 2026-09-22 — Переход на Opus 5.5 / Switch to Opus 5.5

### Для человека
- Шаблон настроек теперь ставит модель Opus 5.5 (`claude-opus-5-5`) — у неё окно на 1M
  токенов сразу, приписка `[1m]` больше не нужна; effort для неё — `xhigh`.
- Нужен Claude Code ≥ 2.1.280: в более старых версиях этой модели нет.
- Документация, хук имени сессии и шаблонные правила говорят о той же модели.

### For agents
- Changed: `assets/settings.template.json` — `env.ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`
  and `env.CLAUDE_CODE_SUBAGENT_MODEL` `claude-opus-5[1m]` → `claude-opus-5-5`; `model`
  `opus[1m]` → `claude-opus-5-5`; `fallbackModel` → `["claude-opus-5-5"]`; `modelSettings`
  gains `"claude-opus-5-5": {"effortLevel": "xhigh"}` (existing `claude-fable-5-1` and
  `claude-opus-5` entries kept; top-level `effortLevel: high` unchanged).
- Changed: `assets/hooks/rename-topic-from-prompt.sh` — headless default
  `TITLE_MODEL` `claude-opus-5` → `claude-opus-5-5`, header comments updated (wall time
  re-measured: ~3–4 s on `claude-opus-5-5`).
- Changed: `assets/rules/bash-gotchas.md` (tmux example `--model 'claude-opus-5-5'`),
  `assets/CLAUDE.md` ("Opus 5.5 subagents"; delegation note no longer pinned to Opus 5).
- Changed: `README.md`, `README.en.md`, `docs/tier/README.md`, `docs/tier/README.en.md`,
  `skills/claudecode/SKILL.md`, `skills/claudecode/references/settings.md` — `opus[1m]` →
  `claude-opus-5-5`, Claude Code ≥ 2.1.280 stated; `references/settings.md` gains a
  `modelSettings` row.
- Changed: `.claude-plugin/plugin.json` — `version` 1.0.0 → 1.0.1.
- Migration: requires Claude Code ≥ 2.1.280 (the release that added `claude-opus-5-5`);
  older Claude Code versions may reject the unknown model ID in `model`, `fallbackModel`
  and the `env` model overrides after the merge — update Claude Code before re-running
  `/claudecode`. `apply-settings.sh` merges by key, so a re-run replaces the old model
  values; a recipient's own `modelSettings` entries stay.

## [1.0.0] — 2026-09-10 — первый релиз: рабочее место один в один / first release: the workbench one to one

### Для человека
- `/claudecode` собирает Claude Code, терминал и папку `~/Jadlis` один в один с машиной
  владельца: зависимости, `~/.claude`, `~/.tmux.conf`, динамический профиль iTerm2 и
  команда `cld`.
- Восемь шагов, каждый сначала объясняет простым языком, что делает, и спрашивает перед
  установкой и перед любой перезаписью; дифф показывается до записи.
- Настройки не копируются поверх чужих, а сливаются через `jq`: шаблон побеждает по своим
  ключам, чужие ключи и `pluginSecrets` остаются, `env` и `permissions` объединяются.
- Повторный запуск ничего не меняет: блок `.zshrc` живёт между маркерами, все скрипты
  идемпотентны.
- Уведомления приезжают сами — `jadlis-notifications` объявлен зависимостью плагина.

### For agents
- Added: `.claude-plugin/plugin.json` (`jadlis-claudecode` 1.0.0, dependency
  `jadlis-notifications ^1`), `skills/claudecode/SKILL.md` + `references/{install,settings,priyomy}.md`.
- Added: `scripts/probe.sh` (machine-readable `key=PASS|FAIL`), `apply-settings.sh`,
  `apply-shell.sh`, `apply-iterm.sh`, `apply-claude-home.sh` — POSIX sh, `--plan`/`--force`,
  every path derived from `$HOME` so the set runs under a throwaway HOME.
- Added: `assets/` — выгрузка рабочих файлов владельца (`settings.template.json`,
  `CLAUDE.md`, `rules/`, `output-styles/jadlis.md`, `hooks/*.sh`, `statusline-command.sh`,
  `scripts/*.sh`, `tmux.conf`, `zshrc-jadlis.zsh`, `iterm2-profile.json`).
- Added: `tools/export-owner.py` — owner-side dev tool that regenerates `assets/`.
- Added: `docs/tier/README.md` + `README.en.md` (тир 0), `README.md` + `README.en.md`,
  `.github/workflows/ci.yml` (`beCyborg/jadlis-hub/.github/workflows/plugin-ci.yml@main`,
  `mode: plugin`, `forbid-mermaid: true`), `.gitignore`.
- Changed vs. the raw export: `assets/iterm2-profile.json` — `"maxwidth": Infinity` (valid
  in a plist, rejected by `JSON.parse` and by NSJSONSerialization, which iTerm2 uses for
  dynamic profiles) заменено на `1000000`; `tools/export-owner.py` получил `json_safe()`,
  чтобы повторный экспорт больше не выдавал невалидный JSON.
- Decision: `permissions.deny` объединяется так же, как `allow` — замена шаблоном молча
  сняла бы запрет, поставленный получателем.
- Decision: `defaults write com.googlecode.iterm2 "Default Bookmark Guid"` вынесено под
  флаг `--set-default` и отказывается работать, когда `$HOME` не совпадает с домашним
  каталогом логина: `defaults` резолвит дом через cfprefsd, а не через `$HOME`.
- Note: лицензии нет, все права сохранены за автором (README contract 2026-09).

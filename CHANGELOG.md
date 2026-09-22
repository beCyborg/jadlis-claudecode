# Changelog — jadlis-claudecode

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).

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

# Changelog — jadlis-claudecode

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).

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

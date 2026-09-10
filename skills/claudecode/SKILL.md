---
name: claudecode
description: "Первый шаг маршрута Jadlis: ставит Claude Code, терминал и папку ~/Jadlis один в один с рабочим местом владельца — зависимости, ~/.claude (настройки, правила, хуки, строка состояния), tmux, профиль iTerm2 и команда cld.\nTRIGGER when: user says \"/claudecode\", \"настрой claude code\", \"настрой рабочее место\", \"как у тебя\", \"первый шаг маршрута\", \"поставь зависимости\", \"настрой терминал\", \"настрой iterm\", \"настрой tmux\", \"setup claude code\", \"set up my workplace\".\nDO NOT TRIGGER when: нужна только папка-vault и структура заметок — это /jadlis-obsidian; уведомления сами по себе — /jadlis-notifications; ключи API — /jadlis-search:keys."
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
argument-hint: "[статус | поставить | только терминал | только настройки]"
---

# Рабочее место один в один

`$ARGUMENTS`

```
PLUGIN  = ${CLAUDE_PLUGIN_ROOT}
SCRIPTS = ${CLAUDE_PLUGIN_ROOT}/scripts
ASSETS  = ${CLAUDE_PLUGIN_ROOT}/assets
```

Читателю с СДВГ: **первая строка ответа — действие**, один шаг за реплику, без преамбул,
списки не длиннее пяти пунктов. Вывод команд целиком не показывать — только итог.

Порядок шагов ниже фиксирован. Перед каждым шагом одной-двумя фразами скажи простым
языком, что это и зачем. **Ничего не ставится и не перезаписывается без явного «да».**

`статус` в аргументах — сделать только шаг 1 и остановиться.

## Шаг 1 — проба

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/probe.sh"
```

Скрипт ничего не меняет. Он печатает строки `ключ=PASS|FAIL` и `ключ.info=…`.
Разложи их в одну таблицу «Что · Статус · Зачем», пояснения — из
`references/install.md`. Сгруппируй: базовые инструменты → терминал → `~/.claude` → папка.

Всё PASS — скажи одной строкой «рабочее место уже собрано, дальше `/jadlis-hub`» и стой.

## Шаг 2 — базовые зависимости

Ставим только то, что в FAIL. Ничего не переустанавливаем.

Спроси одним `AskUserQuestion` (по вопросу на пакет, максимум четыре за вызов):
«Ставим `<пакет>`?» — варианты «Ставлю» / «Пропустить», в описании одна строка «зачем»
из `references/install.md`.

Порядок установки и точные команды — `references/install.md`, раздел «Установка».
Коротко:

1. Homebrew — первым, от него зависит остальное; спросит пароль от Mac.
2. `claude` нативно: `curl -fsSL https://claude.ai/install.sh | bash`.
3. `brew install git jq node python@3.13 uv poppler tmux`.
4. `brew install --cask iterm2 font-jetbrains-mono-nerd-font`.

После каждой установки — одна строка результата, не простыня вывода.

## Шаг 3 — терминал

Что это: `tmux` держит сессию живой, когда окно закрыто; профиль iTerm2 задаёт шрифт,
цвета и рабочую папку; блок в `.zshrc` даёт команду `cld`.

Сначала покажи, что изменится:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-shell.sh" --plan
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-iterm.sh"  --plan
```

`tmux_conf=DIFFERS` — у человека свой `~/.tmux.conf`: покажи дифф и спроси, перезаписать
(`--force`, старый файл уедет в `.bak-…`) или оставить. Спросил, получил «да» — применяй:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-shell.sh"
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-iterm.sh" --set-default
```

Что делают эти два скрипта:

- Блок `.zshrc` между маркерами `# >>> jadlis-claudecode >>>` / `# <<< … <<<` —
  повторный запуск заменяет блок, а не плодит копии. В блоке: `cld`, `_cld_spawn`,
  `_cld_session_name`, `_tmux_server_alive`.
- `cld` открывает tmux-сессию с именем папки (`repo`, `repo_2`, `repo_3`, …) и запускает
  `claude --dangerously-skip-permissions --model 'fable[1m]'`.
- Профиль iTerm2 ложится в `~/Library/Application Support/iTerm2/DynamicProfiles/jadlis.json`,
  `$HOME/Jadlis` в нём заменяется на реальный путь: динамический профиль — обычный JSON,
  переменные в нём не раскрываются.
- `--set-default` делает профиль профилем по умолчанию
  (`defaults write com.googlecode.iterm2 "Default Bookmark Guid" …`), поэтому новая
  вкладка открывается сразу в `~/Jadlis`.

Скажи одной строкой: блок `.zshrc` заработает в новой вкладке терминала, профиль iTerm2
подхватывает сам, `~/.tmux.conf` — при следующем старте tmux.

## Шаг 4 — папка `~/Jadlis`

Что это: рабочая папка, в которую смотрит терминал и в которой живут заметки.

```bash
mkdir -p "$HOME/Jadlis/Система/Планы" "$HOME/Jadlis/.claude/rules"
```

Затем, если файла ещё нет, создай `~/Jadlis/Система/Приёмы работы — Claude Code.md`
(`Write`, содержимое — из `references/priyomy.md`, скопируй как есть).

Скажи одной строкой: `CLAUDE.md` самой папки и структуру заметок делает `/jadlis-obsidian`,
здесь только каркас.

## Шаг 5 — `~/.claude` один в один

Что это: настройки, правила, стиль ответа, хуки и строка состояния владельца.

Сначала дифф настроек, файл при этом не меняется:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-settings.sh" --plan
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-claude-home.sh" --plan
```

Покажи **только дифф**, потом три вещи по строке (подробности — `references/settings.md`):

1. `model: "opus[1m]"` — Opus с окном на 1M токенов. Нужен план **Max**; на Pro такая
   модель списывает usage-кредиты.
2. `permissions.defaultMode: "bypassPermissions"` — агент выполняет команды и правит
   файлы, не спрашивая разрешения каждый раз.
3. Слияние: шаблон побеждает по своим ключам, чужие ключи остаются, `env`,
   `permissions.allow` и `permissions.deny` объединяются. `pluginSecrets` и ключи не
   трогаются никогда.

Получил «да» — применяй:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-settings.sh"
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-claude-home.sh"
```

`…=DIFFERS` в выводе — такой файл уже есть и отличается. Покажи дифф по одному файлу,
спроси и только тогда перезаписывай (`--force`, старый уедет в `.bak-…`).

Про хуки скажи одной строкой: `rename-topic-from-prompt.sh` даёт сессии осмысленное имя
по-русски, по умолчанию в режиме `native` (без ключей и без сети); имена ритуалов внутри
хука — владельца, у получателя они просто не совпадут ни с чем, и это нормально.

## Шаг 6 — режим для читателя с СДВГ

Отдельного скилла нет и не нужно: стиль ответа задаёт `output-styles/jadlis.md`, он уже
приехал на шаге 5, а `outputStyle: "Jadlis"` в настройках включает его по умолчанию.

Проверь и скажи одной строкой, что режим включён:

```bash
jq -r '.outputStyle' "$HOME/.claude/settings.json"
```

## Шаг 7 — уведомления

`jadlis-notifications` ставится сам как зависимость плагина. Проверь:

```bash
claude plugin list 2>/dev/null | grep -i notifications || echo "не установлен"
```

Не установлен — одна строка: `claude plugin install jadlis-notifications@jadlis`.

Один ручной шаг, чтобы клик по уведомлению переключал на нужную вкладку iTerm2:
**iTerm2 → Settings → General → Magic → Enable Python API**, затем перезапустить iTerm2.
Без него уведомления работают, просто поднимают iTerm2 без выбора вкладки.

## Шаг 8 — итог

Прогони пробу из шага 1 ещё раз и напечатай ту же таблицу. Дальше ровно две вещи:

1. Что изменилось — списком не длиннее пяти пунктов, значениями, а не словами.
2. Дальше: «открой новую вкладку iTerm2 (она откроется в `~/Jadlis`), набери `cld`,
   затем `/jadlis-hub`».

Что-то осталось FAIL — назови пакет, причину одной строкой и один способ починить.

## Чего не делать

- Не ставить и не перезаписывать ничего без явного «да» на конкретный вопрос.
- Не редактировать `settings.json` текстом, `Write` или `sed` — только `apply-settings.sh`.
- Не переписывать `.zshrc` целиком и не трогать чужие строки вне маркеров.
- Не писать в `settings.json` ключи API — они живут в Связке ключей macOS.
- Не создавать `~/Jadlis/CLAUDE.md` и структуру заметок — это работа `/jadlis-obsidian`.

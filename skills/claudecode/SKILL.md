---
name: claudecode
description: "Первый шаг маршрута Jadlis: ставит Claude Code, терминал и папку ~/Jadlis один в один с рабочим местом владельца — зависимости, ~/.claude (настройки, хуки, строка состояния), tmux, профиль iTerm2, команды cld и tld; по желанию — CLAUDE.md и стили ответа из их репо.\nTRIGGER when: user says \"/claudecode\", \"настрой claude code\", \"настрой рабочее место\", \"как у тебя\", \"первый шаг маршрута\", \"поставь зависимости\", \"настрой терминал\", \"настрой iterm\", \"настрой tmux\", \"setup claude code\", \"set up my workplace\".\nDO NOT TRIGGER when: нужна только папка-vault и структура заметок — это /jadlis-obsidian; уведомления сами по себе — /jadlis-notifications; ключи API — /jadlis-search:keys."
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

Скрипт ничего не меняет. Он печатает строки `ключ=PASS|FAIL|WARN` и `ключ.info=…`.
Разложи их в одну таблицу «Что · Статус · Зачем», пояснения — из
`references/install.md`. Сгруппируй: базовые инструменты → терминал → `~/.claude` → папка.

Всё PASS (или PASS и WARN) — скажи одной строкой «рабочее место уже собрано, дальше
`/jadlis-hub`» и стой. `WARN` — необязательная часть из другого репо (стили, `CLAUDE.md`):
назови её одной строкой и предложи шаг 5.

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
  `claude --dangerously-skip-permissions --model claude-opus-5-5`.
- `tld` без аргумента показывает все tmux-сессии с заголовками Claude Code, `tld <имя>` —
  переключает на сессию.
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

## Шаг 5 — инструкции и стили (по желанию)

Что это: глобальный `CLAUDE.md` (как агент понимает задачу, проверяет результат и пишет
для людей), правила `rules/` и два стиля ответа — Jadlis и Jadlis Voice. Они живут в двух
отдельных репо на GitHub: `becyb-org/jadlis-claude-md` и `becyb-org/jadlis-output-styles`.
Плагин их не везёт, но может поставить.

Спроси одним `AskUserQuestion`, два вопроса: «Ставим CLAUDE.md и правила?» и «Ставим стили
ответа?» — варианты «Ставлю» / «Пропустить». В описании одна строка «зачем» из этого шага.
Оба «Пропустить» — переходи к шагу 6.

Склонируй выбранные репо во временную папку и покажи план. Каждый блок самодостаточен:
переменные между вызовами Bash не живут.

```bash
D="${TMPDIR:-/tmp}/jadlis-repos"; rm -rf "$D"; mkdir -p "$D"
git clone -q --depth 1 https://github.com/becyb-org/jadlis-claude-md.git "$D/jadlis-claude-md"
git clone -q --depth 1 https://github.com/becyb-org/jadlis-output-styles.git "$D/jadlis-output-styles"
sh "$D/jadlis-claude-md/install.sh" --plan
sh "$D/jadlis-output-styles/install.sh" --plan
```

Клонируй и планируй только то, что человек выбрал. `CLAUDE.md=DIFFERS` — у человека свой
`CLAUDE.md`: покажи дифф и спроси, заменить (`--force`, старый уедет в `.bak-…`) или оставить.
Стили с тем же именем заменяются после бэкапа без отдельного вопроса — скажи об этом одной
строкой. Получил «да» — применяй и убери временную папку:

```bash
D="${TMPDIR:-/tmp}/jadlis-repos"
sh "$D/jadlis-claude-md/install.sh"          # + --force, если человек согласился заменить свой CLAUDE.md
sh "$D/jadlis-output-styles/install.sh"
rm -rf "$D"
```

Скажи одной строкой: обновить потом — те же команды, свежий клон всегда берёт последнюю версию.

## Шаг 6 — `~/.claude` один в один

Что это: настройки, хуки, строка состояния и служебные скрипты владельца.

Сначала дифф настроек, файл при этом не меняется:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-settings.sh" --plan
sh "${CLAUDE_PLUGIN_ROOT}/scripts/apply-claude-home.sh" --plan
```

Покажи **только дифф**, потом три вещи по строке (подробности — `references/settings.md`):

1. `model: "claude-opus-5-5"` — Opus 5.5, окно на 1M токенов у неё по умолчанию. Нужен
   план **Max** и Claude Code ≥ 2.1.280; на Pro такая модель списывает usage-кредиты.
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

Про хуки скажи по строке (подробности — `references/settings.md`):

- `rename-topic-from-prompt.sh` даёт сессии осмысленное имя по-русски. Для обычного
  промпта имя ставит сам Claude Code. Для промпта с файлом, плана или скилла хук зовёт
  `scripts/session-title.sh` — это короткий `claude -p` на подписке.
- `bash-traps.py` ловит известные ловушки в командах Bash: чинит `find /tmp` и зависший
  `codex exec`, блокирует опасные команды. Обойти — `# traps-ok` в команде.
- `ste-ru-lint.py` после записи заметки в `~/Jadlis` показывает агенту до пяти фраз,
  которые нарушают правила письма из `CLAUDE.md`. Ничего не блокирует. Хук встаёт, только
  если в `~/.claude/CLAUDE.md` есть раздел «Writing for people» (`settings.lint_hook=true`
  в выводе). Человек поставит `CLAUDE.md` позже — пусть снова запустит `apply-settings.sh`.
- `cu-autoapprove-hook.sh` сам отвечает на окно «Computer Use wants to control these apps»:
  разрешает приложение на сессию. Работает, только когда Claude Code запущен в tmux (`cld`).
  Приложения, которые нельзя разрешать, — одна строка-регэксп в `~/.config/jadlis/cu-deny-apps`:
  им скрипт отказывает.
- `plan-bypass-hook.sh` срабатывает после одобрения плана. Если план одобрили с телефона
  (Remote Control) и сессия осталась в auto mode, хук переключает её в bypass, очищает
  контекст и запускает реализацию плана в чистом окне. Работает только в tmux. Стоит
  отдельный плагин `jadlis-plan-bypass` — предложи его удалить
  (`claude plugin uninstall jadlis-plan-bypass@jadlis`), иначе хук сработает дважды.

## Шаг 7 — режим для читателя с СДВГ

Отдельного скилла нет и не нужно: стиль ответа задаёт `output-styles/jadlis.md` из шага 5,
а `outputStyle: "Jadlis"` в настройках включает его по умолчанию. Рядом лежит второй стиль —
`Jadlis Voice`. Он даёт тот же ответ на экране, а в конце добавляет блок `## 🔊 Голосом`:
пересказ ответа для слуха. Этот блок выделяют и отдают голосовому движку (TTS). Включается
через `/output-style`. Сам голосовой движок плагин не ставит.

Проверь и скажи одной строкой, что режим включён:

```bash
jq -r '.outputStyle' "$HOME/.claude/settings.json"; ls "$HOME/.claude/output-styles/" 2>/dev/null
```

Файла `jadlis.md` нет (стили пропустили на шаге 5) — скажи одной строкой: Claude Code молча
работает в стиле Default, стили можно поставить позже тем же шагом 5.

## Шаг 8 — уведомления (по желанию)

`jadlis-notifications` — отдельный плагин из маркетплейса `jadlis`, он присылает уведомление
macOS, когда сессия ждёт ответа. С 2.0.0 он не приезжает зависимостью. Проверь:

```bash
claude plugin list 2>/dev/null | grep -i notifications || echo "не установлен"
```

Не установлен — спроси, ставить ли. «Да» — две команды (первая нужна, только если
маркетплейса `jadlis` ещё нет в `claude plugin marketplace list`):

```bash
claude plugin marketplace add https://gitlab.com/beCyborg/jadlis-hub.git
claude plugin install jadlis-notifications@jadlis
```

Человек обновился с 1.x и уведомления уже стоят — всё равно поставь их явно второй
командой: раньше они приехали зависимостью, и `claude plugin prune` иначе их удалит.

Один ручной шаг, чтобы клик по уведомлению переключал на нужную вкладку iTerm2:
**iTerm2 → Settings → General → Magic → Enable Python API**, затем перезапустить iTerm2.
Без него уведомления работают, просто поднимают iTerm2 без выбора вкладки.

## Шаг 9 — итог

Прогони пробу из шага 1 ещё раз и напечатай ту же таблицу. `WARN` — необязательная часть
не стоит, это не ошибка. Дальше ровно две вещи:

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

# Пакеты и установка

## Что за что отвечает

Ключи слева — те же, что печатает `scripts/probe.sh`.

| Ключ | Что это | Зачем нужно |
|---|---|---|
| `homebrew` | менеджер пакетов macOS | через него ставится всё остальное |
| `claude` | CLI Claude Code | им ставятся плагины (`claude plugin install …`) |
| `claude_native` | нативная установка в `~/.local/bin/claude` | обновляется скриптом `tools-autoupdate.sh`; каст `claude-code` из Homebrew так не умеет |
| `git` | версии и клоны репозиториев | работа с кодом и плагинами |
| `jq` | обработка JSON | без него нельзя слить `settings.json`, ломается строка состояния |
| `node` | Node.js и `npx` | на них живут MCP-серверы плагинов |
| `python313` | Python 3.13 (`brew install python@3.13`) | системный 3.9 роняет длинные скрипты с кириллицей |
| `uv` | запуск Python с изолированными зависимостями | `uv run --with pytest …`; в системный Python ставить пакеты нельзя (PEP 668) |
| `poppler` | даёт `pdftotext` | текст из PDF без платных сервисов |
| `tmux` | терминальные сессии | сессия переживает закрытие окна; на нём стоит `cld` |
| `iterm2` | терминал | динамические профили, статус-бар, нормальная работа с цветом |
| `font_jetbrains` | JetBrains Mono Nerd Font | профиль просит `JetBrainsMonoNFM-Regular`; без шрифта иконки станут квадратами |
| `tmux_conf` | `~/.tmux.conf` | passthrough OSC-последовательностей, bell, заголовки окон |
| `iterm_profile` | `DynamicProfiles/jadlis.json` | профиль «Jadlis» и рабочая папка `~/Jadlis` |
| `zshrc_block` | блок в `~/.zshrc` | команда `cld` и фоновое автообновление CLI |
| `settings_merged` | `~/.claude/settings.json` | настройки владельца слиты в файл получателя |
| `hooks` | три хука в `~/.claude/hooks` | имя сессии и заголовок вкладки |
| `statusline` | `~/.claude/statusline-command.sh` | папка, контекст, модель, лимиты в строке состояния |
| `output_style` | `~/.claude/output-styles/jadlis.md` | стиль ответа для читателя с СДВГ |
| `rules` | `~/.claude/rules/*.md` | маршрутизация инструментов и гоча Bash |
| `claude_scripts` | `~/.claude/scripts/*.sh` | обновление CLI и чтение квоты для строки состояния |
| `jadlis_dir` | `~/Jadlis` | рабочая папка терминала и место для заметок |

## Установка

Ставить строго по порядку и только то, что в FAIL.

### 1. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Три вещи, которые надо сказать заранее, по строке:

1. Установщик спросит пароль от Mac — это `sudo`, так устроен официальный скрипт.
2. На Apple Silicon Homebrew ложится в `/opt/homebrew`, на Intel — в `/usr/local`.
3. После установки её надо прописать в шелл, иначе `brew` не найдётся в новом окне:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Установка долгая и интерактивная. Если Bash в текущем окружении её не тянет — отдай
команду строкой «набери это в Терминале и вернись» и жди.

### 2. CLI `claude` — нативно

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Именно нативная установка: она кладёт лаунчер в `~/.local/bin/claude`, а его обновляет
`~/.claude/scripts/tools-autoupdate.sh`, который вызывает `cld` в фоне. В настройках
стоит `DISABLE_AUTOUPDATER=1` — встроенный автообновлятор выключен, обновление идёт
только через этот скрипт.

После установки нужно новое окно терминала: `claude` появляется в `PATH` только там.

### 3. Пакеты Homebrew

```bash
brew install git jq node python@3.13 uv poppler tmux
```

`git` обычно уже есть из Command Line Tools — если проба дала PASS, ставить не надо.

### 4. Терминал и шрифт

```bash
brew install --cask iterm2 font-jetbrains-mono-nerd-font
```

iTerm2 после установки надо один раз открыть руками из папки «Программы».

Каст с шрифтом даёт семейство `JetBrainsMonoNFM` (Nerd Font Mono) — именно его просит
профиль. Без шрифта профиль применится, но иконки в строке состояния станут квадратами.

## Если что-то пошло не так

- `brew` не находится в новом окне → не выполнен `brew shellenv` (пункт 1.3).
- `claude` не находится → открыть новое окно терминала; если и там нет, проверить, что
  `~/.local/bin` есть в `PATH`.
- Профиль iTerm2 не появился → iTerm2 читает `DynamicProfiles` на лету, но если файл
  писался при закрытом iTerm2, помогает перезапуск приложения.
- Новая вкладка открывается не в `~/Jadlis` → профиль не сделан профилем по умолчанию:
  `apply-iterm.sh --set-default` или iTerm2 → Settings → Profiles → Jadlis → Other
  Actions → Set as Default.

#!/bin/bash
# Принимает $1 = заголовок. Переименовывает ТОЛЬКО tmux-окно (rename-window) —
# это единственное, что работает из фонового хука: tmux общается через сокет,
# а не через /dev/tty (которого у хука нет с v2.1.139).
#
# НЕ-tmux окно/таб (iTerm и пр.) теперь ставит сам rename-topic-from-prompt.sh
# через JSON-поле terminalSequence — прямой printf '\033]…' отсюда был мёртв
# (хук-процесс без controlling terminal, escape уходил в /dev/null).
#
# tmux session НЕ трогаем: session name = контракт с `cld` в ~/.zshrc.

export LC_ALL=en_US.UTF-8   # byte-wise cut рвёт кириллицу при пустом LANG у tmux-сервера

TITLE="${1:-}"
TITLE=$(printf '%s' "$TITLE" | tr -d '\000-\037\177' | cut -c1-120)
[ -z "$TITLE" ] && exit 0
[ -z "$TMUX" ] && exit 0

tmux set-window-option -q automatic-rename off 2>/dev/null
tmux set-window-option -q allow-rename off 2>/dev/null
tmux rename-window "$TITLE" 2>/dev/null
tmux set-option -q set-titles-string "#{window_name}" 2>/dev/null
tmux refresh-client -S 2>/dev/null
exit 0

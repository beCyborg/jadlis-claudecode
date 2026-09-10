#!/bin/bash
# Фоновое автообновление CLI-инструментов: claude / grok / codex.
# Запускается из cld/cld2 (_cld_spawn в ~/.zshrc), работу терминала не блокирует.
# Троттлинг: не чаще раза в THROTTLE_SECS; параллельные запуски отсекает lock.
# Лог: ~/.cache/tools-autoupdate/update.log

set -u
CACHE_DIR="$HOME/.cache/tools-autoupdate"
STAMP="$CACHE_DIR/last-run"
LOCK="$CACHE_DIR/lock"
LOG="$CACHE_DIR/update.log"
THROTTLE_SECS=$((6 * 3600))

mkdir -p "$CACHE_DIR"

# Троттлинг по mtime stamp-файла
if [[ -f "$STAMP" ]]; then
  now=$(date +%s)
  last=$(stat -f %m "$STAMP" 2>/dev/null || echo 0)
  (( now - last < THROTTLE_SECS )) && exit 0
fi

# Лок через atomic mkdir; протухший (>1ч) лок сносим
if ! mkdir "$LOCK" 2>/dev/null; then
  now=$(date +%s)
  lock_ts=$(stat -f %m "$LOCK" 2>/dev/null || echo 0)
  (( now - lock_ts < 3600 )) && exit 0
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
trap 'rm -rf "$LOCK"' EXIT

# Ротация лога на ~200 КБ
if [[ -f "$LOG" ]] && (( $(stat -f %z "$LOG" 2>/dev/null || echo 0) > 200000 )); then
  mv -f "$LOG" "$LOG.1"
fi

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') tools-autoupdate ==="
  echo "--- claude update"
  "$HOME/.local/bin/claude" update </dev/null 2>&1
  echo "--- grok update"
  # Напрямую бинарь из ~/.grok/bin, минуя shim (shim подменяет HOME на iso-home)
  "$HOME/.grok/bin/grok" update </dev/null 2>&1
  echo "--- brew upgrade codex"
  /opt/homebrew/bin/brew upgrade codex </dev/null 2>&1
  echo "=== done $(date '+%H:%M:%S')"
} >> "$LOG"

touch "$STAMP"

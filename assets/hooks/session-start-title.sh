#!/bin/bash
# SessionStart hook (SYNC, matcher: startup): подписывает ТОЛЬКО терминал
# (tmux-окно / таб) стартовым "<папка> · HH:MM" — без LLM и сети (<50 мс).
#
# ВАЖНО: sessionTitle здесь НЕ ставим. Разбор бинаря 2.1.227 (2026-08-11):
# стартовый hook-титул при коннекте Remote Control-моста снимается снапшотом
# и занимает слот custom-title → RC «залипает» на "<папка> · HH:MM", а вся
# нативная генерация имён (по 1-му промпту, рефреш после 3-го, именование по
# плану) глушится проверкой vC(Mt()). Это была первопричина рассинхрона имён.
# Смысловое имя ставит rename-topic-from-prompt.sh (UserPromptSubmit) — его
# sessionTitle идёт путём /rename и патчит RC напрямую; при его провале
# работает нативное именование (language=Russian в settings).
#
# Гейт вложенности: дочерние CC-процессы (мост claude -p из verif/full-research)
# наследуют CLAUDE_CODE_SESSION_ID родителя — если env-id не совпадает с
# .session_id из stdin, мы внутри вложенной сессии → молчим.
# CLAUDE_HOOK_RENAME_NESTED оставлен как ручной override.

[ -n "$CLAUDE_HOOK_RENAME_NESTED" ] && exit 0

INPUT=$(cat)

# Гейт вложенности: headless-CC (`claude -p`) виден по командной строке предка;
# env-переменные CC переопределяет и для хуков вложенной сессии (probe 2026-08-11).
_pp=$PPID
for _i in 1 2 3 4; do
  [ -z "$_pp" ] || [ "$_pp" -le 1 ] 2>/dev/null && break
  _cmd=$(ps -o command= -p "$_pp" 2>/dev/null)
  case "$_cmd" in
    claude\ *|*/claude\ *|node\ *claude*)
      case " $_cmd" in *" -p "*|*" --print"*|*" -p") exit 0 ;; esac
      break ;;
  esac
  _pp=$(ps -o ppid= -p "$_pp" 2>/dev/null | tr -d ' ')
done

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD=$PWD
TITLE="$(basename "$CWD") · $(date +%H:%M)"

if [ -n "$TMUX" ]; then
  ( "$HOME/.claude/hooks/_rename-apply.sh" "$TITLE" ) >/dev/null 2>&1 &
  disown 2>/dev/null
  exit 0
fi

# Вне tmux: окно/таб через terminalSequence (прямой printf в /dev/tty мёртв
# с v2.1.139 — у хука нет controlling terminal).
SEQ=$(printf '\033]2;%s\007\033]1;%s\007' "$TITLE" "$TITLE")
jq -nc --arg s "$SEQ" '{terminalSequence:$s}'
exit 0

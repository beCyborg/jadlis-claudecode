#!/usr/bin/env python3
"""Privacy-греп по markdown/тексту репо: ключи, почты, личные пути, чувствительные темы.

Адаптация гейта privacy-grep пакета «Передача» под md-файлы (без браузера — читает текст).
Скриншоты этим не проверяются: картинки просматриваются глазами, отметка — в docs/img/INDEX.md.

Использование:
  python3 tools/privacy-grep.py                 # все *.md, *.json, *.sh, *.py, *.txt от корня репо
  python3 tools/privacy-grep.py docs plugins/jadlis-hub
  python3 tools/privacy-grep.py --words extra-words.txt   # доп. стоп-слова, по одному на строку

Код выхода 1 при любом HIT. Ложные срабатывания гасятся комментарием
`<!-- privacy-ok: <причина> -->` на той же строке (для md) или `# privacy-ok` (для кода).
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

SKIP_DIRS = {".git", "node_modules", "__pycache__", "img"}
EXTS = {".md", ".json", ".sh", ".py", ".txt", ".yml", ".yaml", ".toml", ".js", ".mjs"}

PATTERNS = {
    "ключи": r"\b(BSA[A-Za-z0-9_-]{20,}|fc-[a-f0-9]{32}|sk-[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|AQVN[A-Za-z0-9_-]{30,})\b",
    "почты": r"\b[A-Za-z0-9._%+-]+@(?!example\.com|example\.org|email\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b",
    "личные пути": r"/Users/(?!<)[A-Za-z0-9_.-]+/",
    "телефоны": r"(?<![\d/.-])\+\d{2}[\s-]?\d{3}[\s-]?\d{3}[\s-]?\d{2,4}(?![\d/.-])",
    "финансы": r"runway|подушк|сбережени|накоплени|зарплат[аы]\b",
    "медицина": r"\bкиста\b|GAD-7|HbA1c|спермограмм|моя медкарт|мой диагноз",
    "миграция": r"карт[аы] побыта|ВНЖ|гражданств|миграционн(ый|ая) статус|релокац|защит[аы] ЕС",
    "адреса": r"\bул\.\s|\bг\.\s?[А-ЯЁ][а-яё]+",
    "приватный бэкап": r"beCyborg/jadlis(?![-_])",
}

OK_MARK = re.compile(r"privacy-ok")


def iter_files(roots: list[Path]):
    for root in roots:
        if root.is_file():
            yield root
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for f in filenames:
                p = Path(dirpath) / f
                if p.suffix.lower() in EXTS:
                    yield p


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", default=["."])
    ap.add_argument("--words", type=Path, help="файл с доп. стоп-словами (regex, по одному на строку)")
    args = ap.parse_args()

    patterns = {k: re.compile(v, re.I) for k, v in PATTERNS.items()}
    if args.words and args.words.exists():
        extra = [w.strip() for w in args.words.read_text(encoding="utf-8").splitlines() if w.strip() and not w.startswith("#")]
        if extra:
            patterns["стоп-слова"] = re.compile("|".join(extra), re.I)

    self_path = Path(__file__).resolve()
    hits = 0
    for path in iter_files([Path(p) for p in args.paths]):
        if path.resolve() == self_path or path.name == "privacy-grep.py":
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for ln, line in enumerate(lines, 1):
            if OK_MARK.search(line):
                continue
            for name, rx in patterns.items():
                m = rx.search(line)
                if m:
                    hits += 1
                    print(f"HIT  {name:<16} {path}:{ln}: …{line.strip()[:110]}…")
    print("RESULT:", "REVIEW" if hits else "PASS", f"({hits} совпадений)")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())

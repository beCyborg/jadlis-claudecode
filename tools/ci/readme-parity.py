#!/usr/bin/env python3
"""Проверка двуязычных README: README.md (RU) ↔ README.en.md (EN).

Проверяет для каждой пары:
  - первая строка — переключатель языка («Русский» и «English»);
  - одинаковое число H2 и порядок (по индексу) — набор секций совпадает;
  - каждый ```mermaid``` блок проходит через mmdc (если mmdc установлен);
  - относительные ссылки и картинки существуют.

Использование:
  python3 tools/readme-parity.py            # весь репо от корня
  python3 tools/readme-parity.py docs/brand plugins/jadlis-hub
  python3 tools/readme-parity.py --no-mermaid

Код выхода 1 при любой ошибке.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".playwright-mcp", "assets"}
H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.M)
FENCE_RE = re.compile(r"^```mermaid\s*\n(.*?)^```", re.M | re.S)
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def find_pairs(roots: list[Path]) -> list[tuple[Path, Path | None]]:
    pairs: list[tuple[Path, Path | None]] = []
    for root in roots:
        if root.is_file():
            root = root.parent
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            if "README.md" in filenames:
                ru = Path(dirpath) / "README.md"
                en = Path(dirpath) / "README.en.md"
                pairs.append((ru, en if en.exists() else None))
    return sorted(set(pairs))


def h2s(text: str) -> list[str]:
    out: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = H2_RE.match(line)
        if m:
            out.append(m.group(1))
    return out


def check_switcher(path: Path, text: str, errors: list[str]) -> None:
    first = text.lstrip().splitlines()[0] if text.strip() else ""
    if "Русский" not in first or "English" not in first:
        errors.append(f"{path}: первая строка не переключатель «Русский · English»")


def check_links(path: Path, text: str, errors: list[str]) -> None:
    for m in LINK_RE.finditer(text):
        target = m.group(1)
        if target.startswith(("http://", "https://", "mailto:", "#", "obsidian://")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        resolved = (path.parent / target).resolve()
        if not resolved.exists():
            errors.append(f"{path}: битая ссылка {target}")


def check_mermaid(path: Path, text: str, errors: list[str], mmdc: str | None) -> int:
    blocks = FENCE_RE.findall(text)
    if not blocks or not mmdc:
        return len(blocks)
    with tempfile.TemporaryDirectory() as td:
        for i, block in enumerate(blocks, 1):
            src = Path(td) / f"b{i}.mmd"
            src.write_text(block, encoding="utf-8")
            out = Path(td) / f"b{i}.svg"
            proc = subprocess.run(
                [mmdc, "-i", str(src), "-o", str(out), "-q"],
                capture_output=True, text=True, timeout=120,
            )
            if proc.returncode != 0 or not out.exists():
                tail = (proc.stderr or proc.stdout).strip().splitlines()[-3:]
                errors.append(f"{path}: mermaid-блок #{i} не рендерится: {' | '.join(tail)}")
    return len(blocks)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", default=["."], help="папки или README.md")
    ap.add_argument("--no-mermaid", action="store_true", help="не гонять mmdc")
    ap.add_argument("--allow-missing-en", action="store_true", help="README без EN-пары — предупреждение, не ошибка")
    args = ap.parse_args()

    mmdc = None if args.no_mermaid else shutil.which("mmdc")
    if not args.no_mermaid and not mmdc:
        print("[warn] mmdc не найден — Mermaid не проверяется (npm i -g @mermaid-js/mermaid-cli)", file=sys.stderr)

    errors: list[str] = []
    checked = 0
    mermaid_blocks = 0
    for ru, en in find_pairs([Path(p) for p in args.paths]):
        ru_text = ru.read_text(encoding="utf-8")
        if en is None:
            msg = f"{ru}: нет README.en.md"
            (print("[warn] " + msg, file=sys.stderr) if args.allow_missing_en else errors.append(msg))
            check_links(ru, ru_text, errors)
            mermaid_blocks += check_mermaid(ru, ru_text, errors, mmdc)
            continue
        en_text = en.read_text(encoding="utf-8")
        checked += 1
        check_switcher(ru, ru_text, errors)
        check_switcher(en, en_text, errors)
        ru_h2, en_h2 = h2s(ru_text), h2s(en_text)
        if len(ru_h2) != len(en_h2):
            errors.append(
                f"{ru.parent}: H2 расходятся — RU {len(ru_h2)} {ru_h2} vs EN {len(en_h2)} {en_h2}"
            )
        for p, t in ((ru, ru_text), (en, en_text)):
            check_links(p, t, errors)
            mermaid_blocks += check_mermaid(p, t, errors, mmdc)

    for e in errors:
        print("[error] " + e)
    print(f"пар README проверено: {checked}; mermaid-блоков: {mermaid_blocks}; ошибок: {len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

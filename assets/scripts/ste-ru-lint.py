#!/usr/bin/env python3
"""STE-RU lint: rough counters for the «Writing for people» rules in ~/.claude/CLAUDE.md.
Usage: uv run -q --with pymorphy3 python ~/.claude/scripts/ste-ru-lint.py <file.md> [...]   (or text on stdin)
Per file: words, sentences, avg_len, pct_gt20 (sentences >20 words), per-100-word rates of деепричастия (grnd),
причастия (prtf), passive-ish forms (3rd-person/past «-ся» verbs + short participles — also catches plain
reflexives like «является», compare files, don't read it absolutely), verbal nouns, genitive chains of 3+ nouns,
канцелярит hits, Flesch–Oborneva readability (higher = easier). Built for the 02.10.2026 blind test.

Hook mode (since 02.10.2026, plan «Хаки Claude Code из ресёрча — внедрение», step 3):
  uv run -q --with pymorphy3 python ~/.claude/scripts/ste-ru-lint.py --hook   (PostToolUse Write|Edit|MultiEdit)
Reads the hook JSON on stdin, lints only the text just written (Write content / Edit new_string /
MultiEdit edits[].new_string) of a .md file in the vault scope below, and returns up to 5 offending
sentences as additionalContext. Silent on clean text, never blocks; any error -> exit 0, no output.
"""
import json, os, re, sys, unicodedata
try:
    import pymorphy3
    M = pymorphy3.MorphAnalyzer()
except Exception:
    M = None
KANC = ['является','являются','являлся','данный','данная','данное','данные','данного','данной','данном','данным',
        'осуществля','осуществи','производит','произведен','в рамках','в целях','на текущий момент','на данный момент',
        'в случае если','в связи с','с целью','посредством','вышеуказ','нижеслед']
def clean(t):
    t = re.sub(r'```.*?```', ' ', t, flags=re.S)
    t = re.sub(r'`[^`]*`', ' X ', t)
    t = re.sub(r'\]\([^)]*\)', ']', t)
    t = re.sub(r'https?://\S+', ' X ', t)
    t = re.sub(r'[*_#>|]', ' ', t)
    return t
def sents(t):
    parts = re.split(r'(?<=[.!?…:])\s+|\n+', t)
    return [p.strip() for p in parts if len(re.findall(r'[А-Яа-яЁёA-Za-z0-9]+', p)) >= 2]
def stats(text):
    t = clean(text); low = t.lower()
    ss = sents(t)
    words_all = re.findall(r'[А-Яа-яЁёA-Za-z0-9-]+', t)
    lens = [len(re.findall(r'[А-Яа-яЁёA-Za-z0-9-]+', s)) for s in ss]
    toks = re.findall(r'[А-Яа-яЁё-]+|[.,;:!?()\n]', t)
    grnd = prtf = vsya = vnoun = 0; chains = 0; run = 0
    for w in toks:
        if not re.match(r'[А-Яа-яЁё]', w):
            if run >= 3: chains += 1
            run = 0; continue
        p = M.parse(w.lower())[0]; tag = p.tag
        if tag.POS == 'GRND': grnd += 1
        if tag.POS == 'PRTF': prtf += 1
        if (tag.POS == 'VERB' and re.search(r'(ся|сь)$', w.lower()) and ('3per' in tag or 'past' in tag)) or tag.POS == 'PRTS': vsya += 1
        if tag.POS == 'NOUN' and re.search(r'(ние|ения|ению|ением|нии|ание|тие|ация|ации|ацию|ацией)$', w.lower()): vnoun += 1
        if tag.POS == 'NOUN':
            if run == 0: run = 1
            elif 'gent' in tag: run += 1
            else:
                if run >= 3: chains += 1
                run = 1
        elif tag.POS in ('ADJF','PRTF') and run:
            pass
        else:
            if run >= 3: chains += 1
            run = 0
    if run >= 3: chains += 1
    kanc = sum(low.count(k) for k in KANC)
    nw = max(len(words_all), 1); nsen = max(len(ss), 1)
    syl = sum(len(re.findall(r'[аеёиоуыэюяaeiouy]', w.lower())) for w in words_all)
    fre = 206.835 - 1.3*(nw/nsen) - 60.1*(syl/nw)
    per100 = lambda x: round(100*x/nw, 2)
    return {'words': nw, 'sent': nsen, 'avg_len': round(nw/nsen, 1),
            'pct_gt20': round(100*sum(l > 20 for l in lens)/nsen, 1),
            'grnd_100w': per100(grnd), 'prtf_100w': per100(prtf), 'passive_100w': per100(vsya),
            'vnoun_100w': per100(vnoun), 'gen_chains3': chains, 'kanc': kanc, 'FRE_oborneva': round(fre, 1)}
def strip_fm(t):
    return re.sub(r'\A---\n.*?\n---\n', '', t, flags=re.S)

# ---------- hook mode ----------
VAULT = os.path.expanduser('~/Jadlis')
SCOPE_DIRS = ['Знания', 'Периоды', 'Проекты', 'Цели', 'Потребности', 'Система/Планы']
LONG = 25          # rule says 20; the hook leaves headroom
MAX_SHOWN = 5
ABBR = {'млн', 'млрд', 'тыс', 'трлн', 'руб', 'коп', 'долл', 'чел', 'шт', 'мес', 'мин', 'сек', 'стр', 'гг', 'вв'}
GRND_OK = {'благодаря', 'включая', 'начиная', 'исходя', 'несмотря', 'судя', 'спустя', 'погодя', 'кончая', 'хотя'}
KANC_RE = [re.compile(r, re.I) for r in [
    r'\bявля(ется|ются|лся|лась|лось|лись|ясь)\b', r'\bданн(ый|ая|ое|ого|ой|ом|ому|ую)\b',
    r'\bосуществ\w*', r'\bпроизв(одит|одится|одят|одятся|одить|одиться|ести|ёл|ела|ели|едён\w*|еден\w*)\b',
    r'\bв рамках\b', r'\bв целях\b', r'\bна (текущий|данный) момент\b', r'\bв случае,? если\b',
    r'\bв связи с\b', r'\bс целью\b', r'\bпосредством\b', r'\bвышеуказ\w*', r'\bнижеслед\w*']]
WORD = re.compile(r'[А-Яа-яЁёA-Za-z0-9-]+')


def nfc(p):
    return unicodedata.normalize('NFC', p)


def in_scope(path):
    if not path or not path.endswith('.md'):
        return False
    full = nfc(os.path.realpath(os.path.expanduser(path)))
    root = nfc(os.path.realpath(VAULT))
    if not full.startswith(root + os.sep):
        return False
    rel = full[len(root) + 1:]
    if re.fullmatch(r'\.full-research/[^/]+/draft\.md', rel):
        return True
    return any(rel.startswith(nfc(d) + '/') for d in SCOPE_DIRS)


def hook_clean(t):
    """Drop what is not prose: frontmatter, code, tables, embeds, links, html, callout markers."""
    t = strip_fm(t)
    t = re.sub(r'```.*?```', ' ', t, flags=re.S)
    t = re.sub(r'^\s*\|.*$', ' ', t, flags=re.M)
    t = re.sub(r'!\[\[[^\]]*\]\]', ' ', t)
    t = re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', r'\1', t)
    t = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', t)
    t = re.sub(r'\[!\w+\][+-]?', ' ', t)
    t = re.sub(r'<[^>]+>', ' ', t)
    t = re.sub(r'`[^`]*`', ' X ', t)
    t = re.sub(r'https?://\S+', ' X ', t)
    t = re.sub(r'[*_#>]', ' ', t)
    return t


def gen_chain(sentence):
    """First run of 3+ nouns where every noun after the first is genitive (adjectives may sit inside)."""
    run = []
    for i, w in enumerate(re.findall(r'[А-Яа-яЁё-]+|[A-Za-z0-9]+|[.,;:!?()«»"—–/]', sentence)):
        if not re.match(r'[А-Яа-яЁё]', w) or (i and w[0].isupper()) or w.lower() in ABBR:
            if len(run) >= 3:
                return run
            run = []
            continue
        tag = M.parse(w.lower())[0].tag
        if tag.POS == 'NOUN':
            if run and 'gent' in tag:
                run.append(w)
            else:
                if len(run) >= 3:
                    return run
                run = [w]
        elif tag.POS in ('ADJF', 'PRTF') and run:
            continue
        else:
            if len(run) >= 3:
                return run
            run = []
    return run if len(run) >= 3 else None


def sentence_issues(s):
    out = []
    n = len(WORD.findall(s))
    if n > LONG:
        out.append(f'long sentence ({n} words)')
    for i, w in enumerate(re.findall(r'[А-Яа-яЁё]+', s)):
        lw = w.lower()
        if (i == 0 or not w[0].isupper()) and lw not in GRND_OK and M.parse(lw)[0].tag.POS == 'GRND':
            out.append(f'деепричастие «{w}»')
            break
    chain = gen_chain(s)
    if chain:
        out.append(f'genitive chain «{" ".join(chain)}»')
    for r in KANC_RE:
        m = r.search(s)
        if m:
            out.append(f'канцелярит «{m.group(0)}»')
            break
    return out


def short(s, limit=160):
    s = re.sub(r'\s+', ' ', s).strip()
    return s if len(s) <= limit else s[:limit - 1] + '…'


def hook_text(data):
    ti = data.get('tool_input') or {}
    name = data.get('tool_name', '')
    if name == 'Write':
        return ti.get('content', '')
    if name == 'Edit':
        return ti.get('new_string', '')
    if name == 'MultiEdit':
        return '\n'.join(e.get('new_string', '') for e in ti.get('edits') or [])
    return ''


def hook_report(data):
    path = (data.get('tool_input') or {}).get('file_path', '')
    if M is None or not in_scope(path):
        return None
    hits = []
    for s in sents(hook_clean(hook_text(data))):
        issues = sentence_issues(s)
        if issues:
            hits.append((issues, s))
    if not hits:
        return None
    lines = [f'STE-RU lint (CLAUDE.md § Writing for people): {len(hits)} sentence(s) in {os.path.basename(path)} '
             f'break the rules. Rewrite them if that keeps every fact; ignore quotes and terms.']
    for issues, s in hits[:MAX_SHOWN]:
        lines.append(f'- {"; ".join(issues)}: «{short(s)}»')
    if len(hits) > MAX_SHOWN:
        lines.append(f'- …and {len(hits) - MAX_SHOWN} more')
    return '\n'.join(lines)


def hook_main():
    try:
        msg = hook_report(json.load(sys.stdin))
        if msg:
            json.dump({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': msg}},
                      sys.stdout, ensure_ascii=False)
    except Exception:
        pass
    sys.exit(0)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--hook']:
        hook_main()
    if len(sys.argv) > 1:
        for f in sys.argv[1:]:
            print(f, json.dumps(stats(strip_fm(open(f, encoding='utf-8').read())), ensure_ascii=False))
    else:
        print(json.dumps(stats(strip_fm(sys.stdin.read())), ensure_ascii=False))

#!/usr/bin/env python3
"""Regenerate bulletin-prereqs.json from the BITS Bulletin PDF.

The bulletin's course-description section (pages 611-784) sets each course as a
heading, a units cell, a description paragraph, and sometimes a closing
"Pre-requisites: ..." sentence. This turns those sentences into the app's
AND-of-ORs group shape; `apply-bulletin-prereqs.js` reconciles them with
Firestore.

Three things about the source drive the parsing:

  * Two columns per page, and the PDF's block order does not follow reading
    order, so words are re-sorted by (column, y). The gutter runs x 287.5-307.2
    and each column's units cell sits at its right edge — split at x=297, not at
    the page centre, or the units land in the wrong column.
  * There is no running head; body text starts at y~59. Only the folio
    ("VI-55") at the foot is furniture.
  * A heading is a course code plus a title AND a units cell on, or just below,
    the same line. Without the units test, prerequisite lines like
    "EEE F214 / INSTR F214 / ECE F214" read as headings and swallow the row.

Usage:
    python3 extract-bulletin-prereqs.py /path/to/bulletin.pdf [--pages 611-784] [--out FILE]

Needs `pdftotext` (poppler) on PATH and a courses_master code list; pass one
with --master, or the catalogue check is skipped.
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

# The 2025-26 Bulletin's course descriptions. Each year's edition moves them:
# find the first and last description page and pass --pages.
FIRST_PAGE, LAST_PAGE = 611, 784
MID = 297.0                      # column split; the gutter is x 287.5 -> 307.2
MAX_GAP = 90                     # chars of title text tolerated between two codes

LINE_RE = re.compile(r'<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</line>', re.S)
WORD_RE = re.compile(r'<word[^>]*>(.*?)</word>')
FOLIO_RE = re.compile(r'[IVX]+-\d+')

HEAD_RE = re.compile(r'^([A-Z]{2,6})\s+([FG]\d{3}[A-Z]?)\s+([A-Za-z0-9(].*)$')
UNITS_RE = re.compile(r'^\d+(\s+\d+){0,2}\s*\*?$|^\*$')
UNITS_TAIL_RE = re.compile(r'\s\d+(\s+\d+){1,2}\s*\*?$')
PREREQ_RE = re.compile(
    r'^\s*((?:pre|co)[\s\-/]*(?:requisites|requisite|reqs|req)|prerequisites?|corequisites?)\s*[:\-–]?\s*(.*)$',
    re.I)
STOP_RE = re.compile(r'^\s*(equivalent|note|text\s*book|reference|tb\s*:|r\d\s*:)', re.I)

CODE_RE = re.compile(r'\b([A-Z]{2,6})\s*((?:/\s*[A-Z]{2,6}\s*)*)([FG]\s?\d{3}[A-Z]?)\b')
BARE_RE = re.compile(r'\b([A-Z]{2,6})\s+(\d{3})\b')          # bulletin typo: "MF 218"
TYPE_PAREN_RE = re.compile(r'\(\s*(pre|co)[\s\-/]*requisites?\s*\)', re.I)
OTHER_PAREN_RE = re.compile(r'\([^)]*\)')


# --------------------------------------------------------------------------
# PDF -> lines in reading order
# --------------------------------------------------------------------------

def unescape(s):
    return (s.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
             .replace('&quot;', '"').replace('&#39;', "'").replace('&apos;', "'"))


def reflow(pdf_path):
    with tempfile.TemporaryDirectory() as tmp:
        xml = Path(tmp) / 'bulletin.xml'
        subprocess.run(['pdftotext', '-f', str(FIRST_PAGE), '-l', str(LAST_PAGE),
                        '-bbox-layout', str(pdf_path), str(xml)], check=True)
        pages = xml.read_text().split('<page ')[1:]

    out = []
    for pi, pg in enumerate(pages):
        lines = []
        for xmin, ymin, _xmax, _ymax, body in LINE_RE.findall(pg):
            text = ' '.join(unescape(w) for w in WORD_RE.findall(body)).strip()
            if not text:
                continue
            x0, y0 = float(xmin), float(ymin)
            if y0 > 780 and FOLIO_RE.fullmatch(text):
                continue
            lines.append((0 if x0 < MID else 1, y0, x0, text))
        lines.sort()
        out.extend((FIRST_PAGE + pi, t) for _, _, _, t in lines)
    return out


# --------------------------------------------------------------------------
# lines -> course blocks -> prerequisite sentences
# --------------------------------------------------------------------------

def dehyphen(lines):
    """Join words split across a line break by a soft wrap hyphen."""
    out = []
    for ln in lines:
        if out and re.search(r'[a-z]-$', out[-1]) and re.match(r'^[a-z]', ln):
            out[-1] = out[-1][:-1] + ln
            continue
        out.append(ln)
    return out


def is_heading(flat, i):
    m = HEAD_RE.match(flat[i][1])
    if not m or len(m.group(3)) < 4:
        return None
    if UNITS_TAIL_RE.search(flat[i][1]):
        return m
    for k in range(i + 1, min(i + 4, len(flat))):
        if UNITS_RE.match(flat[k][1]):
            return m
        if HEAD_RE.match(flat[k][1]) or PREREQ_RE.match(flat[k][1]):
            return None
    return None


def course_blocks(flat):
    cur, out = None, []
    for i, (page, text) in enumerate(flat):
        m = is_heading(flat, i)
        if m:
            cur = {'code': f'{m.group(1)} {m.group(2)}',
                   'title': UNITS_TAIL_RE.sub('', m.group(3)).strip(),
                   'page': page, 'body': []}
            out.append(cur)
        elif cur is not None:
            cur['body'].append(text)
    for b in out:
        b['body'] = dehyphen([x for x in b['body'] if not UNITS_RE.match(x)])
    return out


def prereq_stmts(block):
    stmts, i, body = [], 0, block['body']
    while i < len(body):
        m = PREREQ_RE.match(body[i])
        if not m:
            i += 1
            continue
        parts, j = [m.group(2)], i + 1
        while j < len(body) and not PREREQ_RE.match(body[j]) and not STOP_RE.match(body[j]):
            parts.append(body[j])
            j += 1
        stmts.append({'label': m.group(1).strip(),
                      'text': re.sub(r'\s+', ' ', ' '.join(p for p in parts if p)).strip()})
        i = j
    return stmts


# --------------------------------------------------------------------------
# sentence -> AND-of-ORs groups
# --------------------------------------------------------------------------

def strip_parens(text):
    """`(Pre-requisite)` marks a type; every other parenthetical is an aside."""
    marks = []

    def keep(m):
        marks.append((m.start(), 'co/pre' if m.group(1).lower() == 'co' else 'pre'))
        return ' ' * len(m.group(0))

    text = TYPE_PAREN_RE.sub(keep, text)
    return OTHER_PAREN_RE.sub(lambda m: ' ' * len(m.group(0)), text), marks


def find_slots(text, known_subjects):
    """Locate every course code, collapsing `A/B/C F212` into a single OR slot."""
    text = BARE_RE.sub(
        lambda m: f'{m.group(1)} F{m.group(2)}' if m.group(1) in known_subjects else m.group(0),
        text)

    slots = []
    for m in CODE_RE.finditer(text):
        subs = [m.group(1)] + [s.strip() for s in m.group(2).split('/') if s.strip()]
        cat = m.group(3).replace(' ', '')
        slots.append({'codes': [f'{s} {cat}' for s in subs],
                      'start': m.start(), 'end': m.end()})

    # `EEE F214 / INSTR F214 / ECE F214` — separate matches joined by slashes.
    merged = []
    for s in slots:
        if merged and re.fullmatch(r'\s*/\s*(:\s*)?', text[merged[-1]['end']:s['start']]):
            merged[-1]['codes'].extend(s['codes'])
            merged[-1]['end'] = s['end']
        else:
            merged.append(s)
    return text, merged


def connector(gap):
    """Read the AND/OR connector out of the text between two codes."""
    g = gap.strip()
    if re.fullmatch(r'[\s/,;:&]*', g) and '/' in g:
        return 'OR'
    if re.search(r'\bor\b', g, re.I):
        return 'OR'
    if re.search(r'\band\b|&', g, re.I) or re.search(r'[,;]', g):
        return 'AND'
    return None


def to_groups(text, slots, default_type, marks):
    """Walk the slot chain, stopping as soon as the sentence stops being a code list.

    Bulletin prerequisite sentences frequently run straight into the next
    course's description, so the chain has to end itself rather than trust the
    sentence boundary.
    """
    if not slots:
        return [], []
    used, conns = [slots[0]], []
    for prev, cur in zip(slots, slots[1:]):
        gap = text[prev['end']:cur['start']]
        c = connector(gap)
        if c is None or len(gap) > MAX_GAP:
            break
        used.append(cur)
        conns.append(c)

    groups = [[used[0]]]
    for c, s in zip(conns, used[1:]):
        if c == 'OR':
            groups[-1].append(s)
        else:
            groups.append([s])

    def type_at(slot):
        after = [t for pos, t in marks if slot['end'] <= pos <= slot['end'] + MAX_GAP]
        return after[0] if after else default_type

    out = [[{'course_code': c, 'type': type_at(s)} for s in g for c in s['codes']]
           for g in groups]
    return out, used


# --------------------------------------------------------------------------

def main():
    global FIRST_PAGE, LAST_PAGE
    ap = argparse.ArgumentParser()
    ap.add_argument('pdf', help='path to bulletin.pdf')
    ap.add_argument('--out', default=str(Path(__file__).with_name('bulletin-prereqs.json')))
    ap.add_argument('--master', help='JSON array of courses_master codes, for the catalogue check')
    ap.add_argument('--pages', help=f'course-description page range, default {FIRST_PAGE}-{LAST_PAGE}')
    a = ap.parse_args()
    if a.pages:
        FIRST_PAGE, LAST_PAGE = (int(x) for x in a.pages.split('-'))

    master = set(json.load(open(a.master))) if a.master else None
    known_subjects = {c.split()[0] for c in master} if master else set()

    flat = reflow(a.pdf)
    blocks = course_blocks(flat)
    print(f'{len(flat)} lines, {len(blocks)} course blocks', file=sys.stderr)

    parsed, prose = [], []
    for b in blocks:
        for st in prereq_stmts(b):
            default_type = 'co/pre' if st['label'].lower().startswith('co') else 'pre'
            text, marks = strip_parens(st['text'])
            text, slots = find_slots(text, known_subjects)
            # The first code must sit at the head of the sentence; anything further
            # in means the statement is prose and the match came from a runaway
            # paragraph that ran on from the previous course.
            if slots and slots[0]['start'] > 40:
                slots = []
            groups, used = to_groups(text, slots, default_type, marks)
            rec = {'course_code': b['code'], 'title': b['title'], 'page': b['page'],
                   'label': st['label'], 'statement': st['text'], 'groups': groups,
                   'skipped_codes': [],
                   'dropped_codes': [c for s in slots[len(used):] for c in s['codes']]}
            (parsed if groups else prose).append(rec)

    # A code the catalogue has never heard of cannot be matched against a
    # transcript, so it is recorded but kept out of the groups.
    if master is not None:
        for r in parsed:
            unknown = {o['course_code'] for g in r['groups'] for o in g} - master
            r['skipped_codes'] = sorted(unknown)
            r['groups'] = [[o for o in g if o['course_code'] not in unknown]
                           for g in r['groups']]
            r['groups'] = [g for g in r['groups'] if g]

    payload = {
        'source': {
            'document': 'bulletin.pdf (BITS Pilani Bulletin, course descriptions)',
            'pages': f'{FIRST_PAGE}-{LAST_PAGE}',
            'extracted': date.today().isoformat(),
            'method': 'pdftotext -bbox-layout, two-column reflow, prerequisite '
                      'sentence parsed into the AND-of-ORs group shape',
        },
        'note': 'groups = AND of requirements; each inner list = OR of acceptable '
                'courses. Matches CoursePrerequisites.toMap() in '
                'lib/models/prerequisite.dart. skipped_codes were named by the '
                'bulletin but are absent from courses_master.',
        'courses': sorted(parsed, key=lambda r: r['course_code']),
        'unparsed': [{'course_code': r['course_code'], 'page': r['page'],
                      'label': r['label'], 'statement': r['statement'],
                      'reason': 'prerequisite stated in prose, no course codes'}
                     for r in sorted(prose, key=lambda r: r['course_code'])],
    }
    Path(a.out).write_text(json.dumps(payload, indent=2) + '\n')
    print(f'{len(parsed)} parsed, {len(prose)} prose-only -> {a.out}', file=sys.stderr)


if __name__ == '__main__':
    main()

"""Turns a Timetable Division "Timetable changes-N" PDF (posted on the LMS)
into proposed edits to campuses/hyderabad/timetable, for an admin to approve.

The PDF has four kinds of table, each with its own header row:
- Instructor/Instructor In charge Change: course, section, existing, new.
- Room/ Hour Changes: course, section, existing and new days/hours/room.
- Mid Sem & Compre examination date changes: course, existing, new.
- New courses: course, sections, instructor, hours and room, exam dates.

Every proposal is judged against the live document:
- "apply": live still matches the PDF's "existing", so the change is safe.
- "done": live already matches "new" (applied by hand, or by a later booklet).
- "check": live matches neither; the PDF's change may still be right.
- "manual": the PDF does not say enough to write it (e.g. a new course with
  several sections sharing one hours cell).
- "missing": the course or section is not in the timetable.

Proposals are recomputed from the PDF and the live data on every preview and
apply, so nothing stored can go stale.
"""

import re

DAYS = ["M", "T", "W", "Th", "F", "S"]
_DAY_TOKEN = {"M": "M", "T": "T", "W": "W", "TH": "Th", "Th": "Th", "F": "F", "S": "S"}
_COURSE_RE = re.compile(r"\b([A-Z]{2,6})\s+([A-Z]?\d{3})\b")
_SECTION_RE = re.compile(r"\b([LTP]\d{1,2})\b")
_ROOM_RE = re.compile(r"\b([A-Z])\s*-?\s*(\d{3})\b")
_SLOT_TOKEN_RE = re.compile(r"TH|Th|[MTWFS]|\d{1,2}")
_TBA_RE = re.compile(r"^tba\b", re.I)

SELECTABLE = ("apply", "check")


def _clean(s):
    return re.sub(r"\s+", " ", (s or "").replace("Â", "")).strip()


# ─── Cells ───

def parse_course(cell):
    m = _COURSE_RE.search(_clean(cell))
    return f"{m.group(1)} {m.group(2)}" if m else None


def parse_sections(cell):
    """Section ids in a cell. The title column sometimes spills into it
    ("AL P1", "& P3"), and new courses list several ("L1 T1 & P1")."""
    return _SECTION_RE.findall(cell or "")


def _key(name):
    return re.sub(r"[^a-z]", "", name.casefold())


def parse_names(cell, known=frozenset()):
    """Instructor names, in order, from "A / B, C" with the PDF's line breaks
    and stray separators ("Das,/Mohd Talha"). TBA placeholders and
    parenthetical notes are dropped.

    A line break is usually a name wrapping ("Venkata\nVamsi Krishna
    Venuganti"), but the PDF also stacks names one per line with nothing
    between them ("Abhijeet Rajendra Joshi\nAbhipshit Kalita"). A break ends a
    name when the text before it is already a name the timetable knows
    (`known`: name keys)."""
    parts, current = [], ""
    for token in re.split(r"([/,&\n])", re.sub(r"\([^)]*\)", " ", cell or "")):
        if token == "\n":
            if _key(current) in known:
                parts.append(current)
                current = ""
            else:
                current += " "
        elif token in ("/", ",", "&"):
            parts.append(current)
            current = ""
        else:
            current += token
    parts.append(current)
    names = []
    for part in parts:
        name = _clean(part).rstrip(".").strip()
        if name and not _TBA_RE.match(name) and _key(name) not in {_key(n) for n in names}:
            names.append(name)
    return names


def same_people(a, b):
    """Whether two instructor lists name the same people, allowing for the
    PDF's spelling slips ("Sweta Agarwal" / "Sweta Agarwala")."""
    from difflib import SequenceMatcher
    a, b = [_key(n) for n in a], [_key(n) for n in b]
    if len(a) != len(b):
        return False
    rest = list(b)
    for x in a:
        best = max(rest, key=lambda y: SequenceMatcher(None, x, y).ratio(), default=None)
        if best is None or SequenceMatcher(None, x, best).ratio() < 0.85:
            return False
        rest.remove(best)
    return True


def parse_slots(cell):
    """(slots, rooms) from a days/hours/room cell such as "T TH 4 F 5 I 111",
    "M 10 & M W Th 11 F208" or "TH 11 & 12". Slots are (day, hour) pairs."""
    text = _clean(cell)
    rooms = []
    for letter, digits in _ROOM_RE.findall(text):
        room = f"{letter}{digits}"
        if room not in rooms:
            rooms.append(room)
    text = _ROOM_RE.sub(" ", text)
    if re.search(r"\bCHAMBER\b", text, re.I):
        rooms.append("CHAMBER")
        text = re.sub(r"\bCHAMBER\b", " ", text, flags=re.I)
    # "F5": a day glued to its hour.
    text = re.sub(r"(?<=[A-Za-z])(?=\d)", " ", text)

    slots, days, hours = set(), [], []
    for tok in _SLOT_TOKEN_RE.findall(text):
        if tok.isdigit():
            if 1 <= int(tok) <= 12:
                hours.append(int(tok))
            continue
        if hours:
            slots |= {(d, h) for d in days for h in hours}
            days, hours = [], []
        days.append(_DAY_TOKEN[tok])
    slots |= {(d, h) for d in days for h in hours}
    return slots, rooms


def slots_to_schedule(slots):
    """The stored schedule shape: days sharing the same hours grouped together."""
    by_day = {}
    for d, h in slots:
        by_day.setdefault(d, []).append(h)
    groups = {}
    for d in DAYS:
        if d in by_day:
            groups.setdefault(tuple(sorted(by_day[d])), []).append(d)
    return [{"days": [f"DayOfWeek.{d}" for d in ds], "hours": list(hs)}
            for hs, ds in sorted(groups.items(), key=lambda kv: DAYS.index(kv[1][0]))]


def schedule_to_slots(schedule):
    return {(d.replace("DayOfWeek.", ""), h)
            for e in schedule or [] for d in e.get("days", []) for h in e.get("hours", [])}


def describe_slots(slots):
    return ", ".join(f"{' '.join(e['days']).replace('DayOfWeek.', '')} {' '.join(map(str, e['hours']))}"
                     for e in slots_to_schedule(slots)) or "no hours"


def parse_exams(cell):
    """{"mid_sem_exam": ..., "end_sem_exam": ...} with only the fields the cell
    states. "NO EXAM" clears whichever of the two the cell does not give."""
    import main
    out = {}
    lines = [_clean(l) for l in (cell or "").split("\n") if _clean(l)]
    no_exam = any(re.search(r"\bNO\s+EXAM\b", l, re.I) for l in lines)
    for line in lines:
        if re.match(r"\d{1,2}/\d{1,2}\s*-\s*\S", line):
            out["mid_sem_exam"] = main.parse_midsem_exam(line)
        elif re.match(r"\d{1,2}/\d{1,2}\s+(FN|AN)\b", line):
            out["end_sem_exam"] = main.parse_endsem_exam(line)
    if no_exam:
        for field in ("mid_sem_exam", "end_sem_exam"):
            out.setdefault(field, None)
    return {f: out[f] for f in ("mid_sem_exam", "end_sem_exam") if f in out}


def describe_exam(field, exam):
    label = "Mid-sem" if field == "mid_sem_exam" else "Compre"
    if not exam:
        return f"{label}: none"
    y, m, d = exam["date"][:10].split("-")
    return f"{label}: {d}/{m} {exam['timeSlot'].replace('TimeSlot.', '')}"


def _exam_key(exam):
    return (exam["date"][:10], exam["timeSlot"]) if exam else None


# ─── Tables ───

def _norm(h):
    return re.sub(r"\s+", " ", h or "").strip().lower()


def _table_kind(header):
    h = [_norm(c) for c in header]
    joined = " | ".join(h)
    if "tructor" in joined and ("hour" in joined or "exam" in joined) and not any(c.startswith("existing") for c in h):
        return "new_course"
    if not any(c.startswith("existing") for c in h):
        return None
    if "room/hour" in joined:
        return "schedule"
    if "exam" in joined:
        return "exam"
    return "instructor"


def _columns(header):
    h = [_norm(c) for c in header]

    def find(pred):
        return next((i for i, c in enumerate(h) if pred(c)), None)
    return {
        "course": find(lambda c: c.startswith("course") and "title" not in c),
        "section": find(lambda c: c.replace(" ", "").startswith("sec")),
        "existing": find(lambda c: c.startswith("existing")),
        "new": find(lambda c: c.startswith("new")),
        "instructor": find(lambda c: "tructor" in c),
        "hours": find(lambda c: "hour" in c),
        "exam": find(lambda c: "exam" in c),
    }


def rows_from_tables(tables, where=None):
    """Change rows from pdfplumber tables, in document order. A table with no
    header row is the previous table carried onto the next page, as long as it
    has the same width; anything else headerless is page furniture.

    `where`, parallel to `tables`, gives each table's (page index, row bboxes);
    with it every row records where it, the row naming its course and its
    table's header were printed ("at", "course_at", "header"), for snippets()."""
    rows = []
    kind = cols = width = header = course_at = None
    course = section = None
    run_new = []  # "new" cells of the rows so far under the current section
    for ti, table in enumerate(tables):
        if not table:
            continue
        body = list(enumerate(table))
        page, boxes = where[ti] if where else (None, None)
        k = _table_kind(table[0])
        if k:
            kind, cols, width = k, _columns(table[0]), len(table[0])
            course = section = None
            body = body[1:]
            header = (page, boxes[0]) if boxes else None
        elif not kind or len(table[0]) != width:
            continue

        def cell(r, name):
            i = cols.get(name)
            return (r[i] or "") if i is not None and i < len(r) else ""

        for ri, r in body:
            c = parse_course(cell(r, "course"))
            if c:
                course, section = c, None
                course_at = (page, boxes[ri]) if boxes else None
            loc = {"at": (page, boxes[ri]), "course_at": course_at, "header": header} if boxes else {}
            if not course:
                continue
            secs = parse_sections(cell(r, "section"))
            if kind == "exam":
                rows.append({"kind": kind, "course": course, "section": None,
                             "existing": cell(r, "existing"), "new": cell(r, "new"), **loc})
            elif kind == "new_course":
                if not c:
                    continue
                rows.append({"kind": kind, "course": course, "sections": secs,
                             "instructor": cell(r, "instructor"), "hours": cell(r, "hours"),
                             "exam": cell(r, "exam"), **loc})
            else:
                if not (cell(r, "existing").strip() or cell(r, "new").strip()):
                    continue
                inherited = not secs
                if secs:
                    run_new = []
                for s in secs or [section]:
                    rows.append({"kind": kind, "course": course, "section": s, "inherited": inherited,
                                 "existing": cell(r, "existing"), "new": cell(r, "new"),
                                 "run_section": s, "prior_new": "\n".join(run_new) if inherited else "",
                                 **loc})
                run_new.append(cell(r, "new"))
                if secs:
                    section = secs[-1]
    return rows


def parse_pdf(path):
    import pdfplumber
    tables, where = [], []
    with pdfplumber.open(path) as pdf:
        for i, page in enumerate(pdf.pages):
            for t in page.find_tables():
                tables.append(t.extract())
                # Full table width: a continuation row's own box covers only
                # its non-empty cells.
                where.append((i, [(t.bbox[0], r.bbox[1], t.bbox[2], r.bbox[3]) for r in t.rows]))
    return rows_from_tables(tables, where)


SNIPPET_DPI = 110


def snippets(path, rows):
    """{row key: PNG as base64} showing each row as printed, under its table's
    header row, so an admin can read exactly what the PDF says."""
    import base64
    import io
    import pdfplumber
    from PIL import Image

    scale = SNIPPET_DPI / 72
    out, pages = {}, {}
    with pdfplumber.open(path) as pdf:
        def crop(where):
            page_i, (x0, top, x1, bottom) = where
            if page_i not in pages:
                pages[page_i] = pdf.pages[page_i].to_image(resolution=SNIPPET_DPI).original.convert("L")
            pad = 2
            return pages[page_i].crop((int((x0 - pad) * scale), int((top - pad) * scale),
                                       int((x1 + pad) * scale), int((bottom + pad) * scale)))
        for r in keyed(rows):
            if not r.get("at"):
                continue
            parts = [crop(r["header"])] if r.get("header") else []
            at, first = r["at"], r.get("course_at")
            if first and first != at:
                if first[0] == at[0]:  # same page: everything from the course's row down
                    at = (at[0], (at[1][0], first[1][1], at[1][2], at[1][3]))
                else:
                    parts.append(crop(first))
            parts.append(crop(at))
            img = Image.new("L", (max(p.width for p in parts), sum(p.height for p in parts) + 6 * (len(parts) - 1)), 255)
            y = 0
            for p in parts:
                img.paste(p, (0, y))
                y += p.height + 6
            buf = io.BytesIO()
            img.save(buf, format="PNG", optimize=True)
            out[r["key"]] = base64.b64encode(buf.getvalue()).decode()
    return out


# ─── Judging a row against the live timetable ───

def _section(doc, section_id):
    return next((s for s in (doc or {}).get("sections", []) if s.get("sectionId") == section_id), None)


def evaluate(row, doc, master=None, known=frozenset()):
    """(status, reason, before, after, apply) for one row against the live
    course doc. `apply(doc)` returns the doc with the change made."""
    kind = row["kind"]
    if kind == "new_course":
        return _evaluate_new_course(row, doc, master, known)
    if doc is None:
        return "missing", f"{row['course']} is not in the timetable", "", "", None
    if kind == "exam":
        return _evaluate_exam(row, doc)

    sec = _section(doc, row["section"])
    if kind == "schedule" and row.get("inherited"):
        # A continuation row with a blank section cell: the PDF means the
        # section that holds those hours, which is not always the one above
        # (BIO F312's "W 5" row is its tutorial, printed under L1). Hours the
        # rows above it moved into that section are left out of the search, so
        # the answer is the same before and after those rows are applied;
        # failing a section holding the old hours, the one the change is
        # already in.
        ex_slots, _ = parse_slots(row["existing"])
        new_slots, _ = parse_slots(row["new"])
        prior, _ = parse_slots(row.get("prior_new", ""))
        if ex_slots:
            secs = doc.get("sections", [])

            def own(s):
                slots = schedule_to_slots(s.get("schedule"))
                return slots - prior if s.get("sectionId") == row["run_section"] else slots
            holders = [s for s in secs if ex_slots <= own(s)]
            done = [s for s in secs if new_slots and new_slots <= own(s) and not ((ex_slots - new_slots) & own(s))]
            pick = holders or done
            if len(pick) == 1:
                sec = pick[0]
                row["section"] = sec["sectionId"]  # the keyed copy, so the proposal shows it
            elif len(pick) > 1:
                row["ambiguous"] = True
    if sec is None:
        return "missing", f"{row['course']} has no section {row['section']}", "", "", None
    sid = sec["sectionId"]

    def patch_section(d, fn):
        d = {**d, "sections": [dict(s) for s in d.get("sections", [])]}
        fn(_section(d, sid))
        return d

    if kind == "instructor":
        new = parse_names(row["new"], known)
        live = parse_names(sec.get("instructor", ""))
        before, after = ", ".join(live), ", ".join(new)
        apply = lambda d: patch_section(d, lambda s: s.update(instructor=after))  # noqa: E731
        if not new:
            return "manual", "No instructor names could be read", before, after, None
        if {_key(n) for n in live} == {_key(n) for n in new}:
            return "done", "", before, after, apply
        if same_people(live, parse_names(row["existing"], known)):
            return "apply", "", before, after, apply
        return "check", "The live instructors differ from the PDF's existing list", before, after, apply

    # Room/hour change.
    ex_slots, ex_rooms = parse_slots(row["existing"])
    new_slots, new_rooms = parse_slots(row["new"])
    live_slots = schedule_to_slots(sec.get("schedule"))
    live_room = sec.get("room", "")
    target_slots = (live_slots - ex_slots) | new_slots if new_slots else live_slots
    target_room = ", ".join(new_rooms) if new_rooms else live_room
    statuses, reasons = [], []
    if new_slots:
        if not ex_slots:
            statuses.append("check")
            reasons.append("The PDF gives new hours but not the existing ones")
        elif new_slots <= live_slots and not ((ex_slots - new_slots) & live_slots):
            statuses.append("done")
        elif ex_slots <= live_slots:
            statuses.append("apply")
        else:
            statuses.append("check")
            reasons.append("The live hours differ from the PDF's existing hours")
    if new_rooms:
        def rkey(r):
            return re.sub(r"[^A-Z0-9,]", "", r.upper())
        if rkey(live_room) == rkey(target_room):
            statuses.append("done")
        elif not ex_rooms or rkey(live_room) == rkey(", ".join(ex_rooms)):
            statuses.append("apply")
        else:
            statuses.append("check")
            reasons.append("The live room differs from the PDF's existing room")
    if not statuses:
        return "manual", "No hours or room could be read", "", "", None
    if row.get("ambiguous"):
        statuses.append("check")
        reasons.append(f"The PDF leaves the section blank and several sections meet then; {sid} assumed")
    status = "check" if "check" in statuses else ("apply" if "apply" in statuses else "done")

    def describe(slots, room):
        return f"{describe_slots(slots)} · {room or 'no room'}"

    def apply(d):
        return patch_section(d, lambda s: s.update(schedule=slots_to_schedule(target_slots), room=target_room))
    return status, "; ".join(reasons), describe(live_slots, live_room), describe(target_slots, target_room), apply


def _evaluate_exam(row, doc):
    ex, new = parse_exams(row["existing"]), parse_exams(row["new"])
    if not new:
        return "manual", "No exam dates could be read", "", "", None
    changed = {f: v for f, v in new.items() if _exam_key(doc.get(f)) != _exam_key(v)}
    before = " · ".join(describe_exam(f, doc.get(f)) for f in new)
    after = " · ".join(describe_exam(f, v) for f, v in new.items())

    def apply(d):
        return {**d, **new}
    if not changed:
        return "done", "", before, after, apply
    stale = [f for f in changed if f in ex and _exam_key(doc.get(f)) != _exam_key(ex[f])]
    if stale:
        return "check", "The live exam differs from the PDF's existing date", before, after, apply
    return "apply", "", before, after, apply


def _evaluate_new_course(row, doc, master, known):
    slots, rooms = parse_slots(row["hours"])
    names = parse_names(row["instructor"], known)
    exams = parse_exams(row["exam"])
    after = " · ".join(filter(None, [" ".join(row["sections"]), ", ".join(names),
                                     describe_slots(slots), ", ".join(rooms)]))
    if doc is not None:
        return "done", "Already in the timetable", "", after, None
    if len(row["sections"]) != 1:
        return ("manual", "Several sections share one hours cell; add it in Course Management",
                "", after, None)
    if not master:
        return "manual", "Not in the course catalogue; add it in Course Management", "", after, None
    sid = row["sections"][0]
    credits = master.get("credits", 0)
    new_doc = {
        "sections": [{
            "sectionId": sid,
            "type": f"SectionType.{sid[0]}",
            "instructor": ", ".join(names),
            "room": ", ".join(rooms),
            "schedule": slots_to_schedule(slots),
        }],
        "mid_sem_exam": exams.get("mid_sem_exam"),
        "end_sem_exam": exams.get("end_sem_exam"),
        "lecture_credits": credits,
        "practical_credits": 0,
        "total_credits": credits,
        "total_credit_hours": 0,
        "com_codes": [],
    }
    return "apply", "", "", after, lambda _d: new_doc


def keyed(rows):
    """Each row with a key that is stable across re-parsing the same PDF."""
    seen = {}
    out = []
    for r in rows:
        base = f"{r['kind']}|{r['course']}|{r.get('section') or ''}"
        seen[base] = seen.get(base, 0) + 1
        out.append({**r, "key": f"{base}|{seen[base]}"})
    return out


def doc_id(course):
    return course.replace(" ", "_")


def known_names(docs):
    """Name keys of every instructor in the timetable, for parse_names."""
    return frozenset(_key(n) for d in docs.values() for s in (d or {}).get("sections", [])
                     for n in parse_names(s.get("instructor", "")))


def propose(rows, docs, masters):
    """The admin-facing list: one entry per row, judged against `docs`
    ({doc id: live course doc}) and `masters` ({doc id: catalogue row})."""
    known = known_names(docs)
    out = []
    for r in keyed(rows):
        did = doc_id(r["course"])
        status, reason, before, after, _ = evaluate(r, docs.get(did), masters.get(did), known)
        out.append({
            "key": r["key"], "kind": r["kind"], "course": r["course"],
            "section": r.get("section") or " ".join(r.get("sections", [])),
            "status": status, "reason": reason, "before": before, "after": after,
        })
    return out


def apply_selected(rows, docs, masters, keys):
    """Applies the rows in `keys`, in document order, each judged against the
    doc as the rows before it left it. Returns ({doc id: new doc}, applied)."""
    keys = set(keys)
    known = known_names(docs)
    working = dict(docs)
    touched, applied = {}, []
    for r in keyed(rows):
        if r["key"] not in keys:
            continue
        did = doc_id(r["course"])
        status, _, before, after, fn = evaluate(r, working.get(did), masters.get(did), known)
        if status not in SELECTABLE or fn is None:
            continue
        working[did] = touched[did] = fn(working.get(did))
        applied.append({"key": r["key"], "course": r["course"], "before": before, "after": after})
    return touched, applied


def summary(proposals):
    counts = {}
    for p in proposals:
        counts[p["status"]] = counts.get(p["status"], 0) + 1
    words = {"apply": "to apply", "check": "to check", "done": "already in",
             "manual": "to add by hand", "missing": "not found"}
    parts = [f"{counts[s]} {w}" for s, w in words.items() if counts.get(s)]
    return f"{len(proposals)} changes: " + ", ".join(parts) if proposals else "No changes found in the PDF"

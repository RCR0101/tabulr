"""Golden-file checks for the three campus timetable parsers in main.py.

Run from the repo root with the functions venv (no pytest dependency):

    functions-python/venv/bin/python functions-python/test_timetable_parsers.py

The fixtures are the real timetable booklets in the repo root, matching
test_academic_calendar.py. They are gitignored (see .gitignore: source PDFs are
admin inputs, not shipped assets), so the suite SKIPS when they are absent
rather than failing — it is a local guard, not a CI gate.

Why this exists: parse_timetable_rows_{hyd,pilani,goa} are three hand-written
state machines over pdfplumber table extraction, and a mis-parse is silent.
upload_courses_to_firestore clears the collection and rewrites it, the catalogue
bundle regenerates, clients cache for 72h, and the first signal is a student
sitting in the wrong room. These numbers are a tripwire: if a pdfplumber upgrade
or a registrar layout change moves them, that should be a deliberate update to
this file, not a surprise in production.
"""
import os
import re
import sys

import main

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CAMPUS_CODES = {"hyd": "hyderabad", "pilani": "pilani", "goa": "goa"}

# Parsed booklets, keyed by campus code. Populated once — extraction is the
# slow part (seconds per PDF), and every test below reuses the result.
_parsed = {}


def pdf_path(campus):
    return os.path.join(ROOT, f"timetable-{campus}.pdf")


def have_pdfs():
    return all(os.path.exists(pdf_path(c)) for c in CAMPUS_CODES)


def parse(campus):
    if campus not in _parsed:
        code = CAMPUS_CODES[campus]
        rows = main.extract_pdf_tables(
            pdf_path(campus), main.DEFAULT_TIMETABLE_HEADERS.get(code, []))
        _parsed[campus] = main.parse_timetable_rows(rows, code)
    return _parsed[campus]


def find(courses, code):
    for c in courses:
        if c["courseCode"] == code:
            return c
    return None


# ── Shape of every row that survives parsing ────────────────────────────────


def test_every_parsed_row_is_a_course():
    """No day headers, repeated column headers, or calendar day numbers.

    Before is_course_row existed the full-booklet parse (page_range is optional,
    so this is a real production path) emitted 41 of these for Hyderabad alone —
    "M"/"T" day headers, "COURSE\\nNO", bare day numbers like "12", and the time
    legend "8.00 - 8.50 AM". Each became a Firestore course document, and
    sync_courses_master then inserted the junk code into the curated master
    catalogue, which never deletes a row.
    """
    for campus in CAMPUS_CODES:
        for c in parse(campus):
            code = c["courseCode"]
            assert main.COURSE_CODE_RE.match(code), f"{campus}: {code!r}"


def test_suffixed_codes_are_kept():
    """Hyderabad prints BITS F101-1 / BITS K101-1 as real, distinct rows.

    They carry their own titles, credits and instructors, so a filter anchored
    to the end of the course code would silently delete real courses — the same
    class of failure the filter exists to prevent, in the other direction.
    """
    hyd = parse("hyd")
    social = find(hyd, "BITS F101-1")
    assert social, "BITS F101-1 was dropped"
    assert "SOCIAL" in social["courseTitle"].upper(), social["courseTitle"]
    assert find(hyd, "BITS K101-1"), "BITS K101-1 was dropped"


# ── Per-campus totals (the tripwire) ────────────────────────────────────────


def test_course_counts_are_stable():
    # pilani rose 407 -> 687 with the 2026-27 booklet: a bigger offering, plus
    # the 142 courses now printed a second time for the 2026 batch.
    expected = {"hyd": 855, "pilani": 687, "goa": 377}
    for campus, want in expected.items():
        got = len(parse(campus))
        assert got == want, f"{campus}: parsed {got}, expected {want}"


def test_dedupe_leaves_one_row_per_document_id():
    """What reaches Firestore must be one row per document id.

    The raw parse is NOT duplicate-free: Hyderabad prints every course in both
    the I-SEM and II-SEM tables, so a whole-booklet parse yields two rows per
    course. dedupe_by_doc_id is what makes the write safe.
    """
    for campus in CAMPUS_CODES:
        seen = {}
        for c in main.dedupe_by_doc_id(parse(campus)):
            doc_id = main.course_code_to_doc_id(c["courseCode"])
            assert doc_id not in seen, \
                f"{campus}: {c['courseCode']!r} and {seen[doc_id]!r} -> {doc_id!r}"
            seen[doc_id] = c["courseCode"]


def test_dedupe_keeps_the_populated_row_not_the_blank_one():
    """The failure this prevents: 382 real Hyderabad courses replaced by blanks.

    The empty II-SEM copy is written second, and batch.set() means last-write-
    wins, so without deduping the upload stored zero credits and no sections
    for every course offered in only one semester.
    """
    deduped = main.dedupe_by_doc_id(parse("hyd"))
    c = find(deduped, "BIO F212")
    assert c, "BIO F212 missing after dedupe"
    assert c["totalCredits"] > 0, "kept the blank row"
    assert c["sections"], "kept the row with no sections"

    blanks = [x for x in deduped if not x["sections"] and x["totalCredits"] == 0]
    assert len(blanks) < len(deduped) * 0.15, \
        f"{len(blanks)}/{len(deduped)} courses are blank after dedupe"


def test_dedupe_is_order_independent():
    """Reversing the input must not change which row survives — otherwise the
    result depends on which table the registrar happened to print second."""
    for campus in ("hyd", "pilani"):
        courses = parse(campus)
        forward = {c["courseCode"]: (c["totalCredits"], c["creditHours"])
                   for c in main.dedupe_by_doc_id(courses)}
        backward = {c["courseCode"]: (c["totalCredits"], c["creditHours"])
                    for c in main.dedupe_by_doc_id(list(reversed(courses)))}
        assert forward == backward, f"{campus}: dedupe depends on input order"


# ── Units vs credit hours ───────────────────────────────────────────────────


def test_pilani_high_com_codes_are_hours_not_units():
    """The 2026-batch row's CREDIT column is hours, and reading it as units is
    what stored BIO G514 as 15 credits instead of 5.

    dedupe must merge the pair rather than pick a winner: the units live on one
    row and the hours on the other, and the hours row would win any "more
    credits" contest with a number that is not units at all.
    """
    deduped = main.dedupe_by_doc_id(parse("pilani"))
    c = find(deduped, "BIO G514")
    assert c, "BIO G514 missing from the Pilani booklet"
    assert c["totalCredits"] == 5, c["totalCredits"]
    assert c["creditHours"] == 15, c["creditHours"]
    assert c["comCodes"] == [392, 6046], c["comCodes"]

    # Both numbers survive on every merged pair, not just this one.
    paired = [x for x in deduped if len(x["comCodes"]) > 1]
    assert len(paired) == 142, len(paired)
    assert all(x["totalCredits"] and x["creditHours"] for x in paired), \
        [x["courseCode"] for x in paired
         if not (x["totalCredits"] and x["creditHours"])]


def test_a_two_com_cod_course_offers_both_ways():
    """Both rows are on offer at once, so both survive as a choice.

    The document stays keyed on the bare course code — that is what every saved
    timetable stores — and the twin becomes a variant rather than a second
    document that nothing could tell apart from the first.
    """
    c = find(main.dedupe_by_doc_id(parse("pilani")), "CS G569")
    assert c, "CS G569 missing from the Pilani booklet"
    assert c["variants"] == [
        {"comCode": 2986, "credits": 4, "creditHours": 0},
        {"comCode": 6221, "credits": 0, "creditHours": 12},
    ], c["variants"]


def test_only_a_units_hours_pair_becomes_a_choice():
    """Hyderabad's two-semester duplicates and cross-listed codes are one
    offering printed twice, not two ways to take a course — giving those
    variants would ask students to choose between a row and its own blank
    copy."""
    for campus in CAMPUS_CODES:
        for c in main.dedupe_by_doc_id(parse(campus)):
            for v in c.get("variants", []):
                assert v["credits"] or v["creditHours"], \
                    f"{campus}: {c['courseCode']} has an empty variant {v}"
            if c.get("variants"):
                assert any(v["creditHours"] for v in c["variants"]), \
                    f"{campus}: {c['courseCode']} has variants but no hours row"

    assert not [c for c in main.dedupe_by_doc_id(parse("hyd")) if c.get("variants")]


def test_a_course_printed_only_in_hours_has_no_invented_units():
    """CHEM U101 is 7 credit hours at Pilani and 3 units at Hyderabad, so hours
    are not units x 3 and must not be back-derived into a unit count."""
    c = find(main.dedupe_by_doc_id(parse("pilani")), "CHEM U101")
    assert c, "CHEM U101 missing from the Pilani booklet"
    assert c["creditHours"] == 7, c["creditHours"]
    assert c["totalCredits"] == 0, \
        f"units were invented for an hours-only course: {c['totalCredits']}"


def test_goa_reads_hours_from_its_own_column():
    """Goa states hours in a CREDIT HOUR column, not under a second com cod.

    Its U-series rows print an empty L-P-U cell, so before this the only number
    the booklet gave for those 14 courses was dropped and they stored 0 credits.
    The values match Pilani's for the same courses, which is two booklets
    agreeing rather than one being trusted.
    """
    goa = main.dedupe_by_doc_id(parse("goa"))
    pilani = main.dedupe_by_doc_id(parse("pilani"))

    with_hours = [c for c in goa if c["creditHours"]]
    assert len(with_hours) == 14, len(with_hours)
    assert not [c for c in goa if not c["totalCredits"] and not c["creditHours"]], \
        "a Goa course carries neither units nor hours"

    for c in with_hours:
        twin = find(pilani, c["courseCode"])
        if twin and twin["creditHours"]:
            assert twin["creditHours"] == c["creditHours"], \
                f"{c['courseCode']}: goa {c['creditHours']} vs pilani {twin['creditHours']}"


def test_the_hours_rule_is_pilani_only():
    """48 Hyderabad rows sit above the Pilani threshold carrying ordinary units
    — CS F321 is com cod 12624 and 3 units — so a campus-agnostic rule would
    restate all of them as hours."""
    high = [c for c in parse("hyd")
            if any(n >= main.PILANI_CREDIT_HOUR_COM_CODE for n in c["comCodes"])]
    assert high, "no Hyderabad course above the threshold — fixture changed?"
    assert all(c["creditHours"] == 0 for c in high), \
        [c["courseCode"] for c in high if c["creditHours"]]
    assert any(c["totalCredits"] > 0 for c in high)


# ── Content spot-checks, one per campus ─────────────────────────────────────


def test_hyderabad_parses_a_known_course():
    c = find(parse("hyd"), "CS F213")
    assert c, "CS F213 missing from the Hyderabad booklet"
    assert c["totalCredits"] > 0
    assert c["sections"], "no sections"
    assert any(s["schedule"] for s in c["sections"]), "no section carries a schedule"


def test_pilani_parses_a_known_course():
    c = find(parse("pilani"), "AN F314")
    assert c, "AN F314 missing from the Pilani booklet"
    assert "FLIGHT" in c["courseTitle"].upper(), c["courseTitle"]
    assert c["sections"]


def test_goa_parses_a_known_course():
    c = find(parse("goa"), "BIO F212")
    assert c, "BIO F212 missing from the Goa booklet"
    assert "MICROBIOLOGY" in c["courseTitle"].upper(), c["courseTitle"]
    assert len(c["sections"]) > 1, "expected multiple sections"


def test_goa_finds_the_course_code_column():
    """The 2026-27 booklet dropped COM CODE, sliding the code from column 1 to 0.

    STAT/SEC onwards did not move (a blank CREDIT HOUR column took up the slack),
    so every section, room, schedule and exam still parsed perfectly while the
    code, title and credits were each read one column to the left. Nothing
    downstream could tell: the 2026-07-29 upload wrote 274 documents keyed by
    course TITLE, with the "L P U" string stored as the title, and
    sync_courses_master inserted all of them into the master catalogue.
    """
    old = [["1234", "CS F111", "COMPUTER PROGRAMMING", "3 0 3", "L", "1"]]
    new = [["CS F111", "COMPUTER PROGRAMMING", "3 0 3", "", "L", "1"]]
    assert main.goa_code_col(old) == 1
    assert main.goa_code_col(new) == 0
    for rows in (old, new):
        c = main.parse_timetable_rows(rows, "goa")[0]
        assert c["courseCode"] == "CS F111", c
        assert c["courseTitle"] == "COMPUTER PROGRAMMING", c
        assert c["totalCredits"] == 3, c


def test_goa_credit_cell_variants():
    """Every shape the booklet's "L P U" cell actually takes."""
    assert main.parse_lpu("3 1 4") == {"L": 3, "P": 1, "U": 4}
    assert main.parse_lpu("2 2") == {"L": 0, "P": 2, "U": 2}   # PHY F214, lab
    assert main.parse_lpu("40") == {"L": 0, "P": 0, "U": 40}   # BITS C799T thesis
    assert main.parse_lpu("3*") == {"L": 0, "P": 0, "U": 3}    # footnote marker
    assert main.parse_lpu("") == {"L": 0, "P": 0, "U": 0}      # U-series: absent


def test_goa_instructor_newlines_are_line_wraps():
    """pdfplumber reports a wrapped cell with a newline mid-name."""
    rows = [["CS F111", "COMPUTER PROGRAMMING", "3 0 3", "", "L", "1",
             "RAVIPRASAD ADURI/ Rajesh\nMehrotra", "M W F 4", "C404"]]
    c = main.parse_timetable_rows(rows, "goa")[0]
    assert c["sections"][0]["instructor"] == "RAVIPRASAD ADURI, Rajesh Mehrotra"


# ── Structural invariants across every campus ───────────────────────────────


def test_schedules_are_well_formed():
    """Days and hours must be the enum strings the Dart client parses.

    Course.fromJson maps these by exact string; an unrecognised day silently
    drops the class off the grid instead of raising.
    """
    valid_days = set(main.DAY_MAP.values())
    for campus in CAMPUS_CODES:
        for c in parse(campus):
            for s in c["sections"]:
                for entry in s["schedule"]:
                    for d in entry["days"]:
                        assert d in valid_days, f"{campus}: {c['courseCode']}: {d!r}"
                    for h in entry["hours"]:
                        assert 1 <= h <= 12, f"{campus}: {c['courseCode']}: hour {h}"


def test_section_types_are_recognised():
    valid = {"SectionType.L", "SectionType.P", "SectionType.T"}
    for campus in CAMPUS_CODES:
        for c in parse(campus):
            for s in c["sections"]:
                assert s["type"] in valid, f"{campus}: {c['courseCode']}: {s['type']!r}"


def test_most_courses_carry_a_schedule():
    """A layout change that breaks the days/hours columns leaves the course rows
    intact and empties the schedules, so counts alone would not catch it."""
    for campus in CAMPUS_CODES:
        # Deduped, because the raw Hyderabad parse is half empty II-SEM copies.
        courses = main.dedupe_by_doc_id(parse(campus))
        with_sched = sum(
            1 for c in courses if any(s["schedule"] for s in c["sections"]))
        ratio = with_sched / len(courses)
        assert ratio > 0.5, f"{campus}: only {ratio:.0%} of courses have a schedule"


def test_credits_are_plausible():
    for campus in CAMPUS_CODES:
        for c in parse(campus):
            # 40 is the ceiling because Goa's BITS C799T (PH D THESIS) is 40 units.
            assert 0 <= c["totalCredits"] <= 40, \
                f"{campus}: {c['courseCode']}: {c['totalCredits']} credits"


def test_exam_dates_are_iso_and_in_range():
    for campus in CAMPUS_CODES:
        for c in parse(campus):
            for key in ("midSemExam", "endSemExam"):
                exam = c.get(key)
                if not exam:
                    continue
                assert re.match(r"^\d{4}-\d{2}-\d{2}T", exam["date"]), \
                    f"{campus}: {c['courseCode']}: {exam['date']!r}"
                assert exam["timeSlot"].startswith("TimeSlot."), exam["timeSlot"]


# ── A properly specified page range must be unaffected ──────────────────────


TIMETABLE_MARKER = {
    "hyd": "TIMETABLE I SEM 2026 -27",
    "pilani": "COURSEWISE TIMETABLE",
}


def _timetable_page_range(campus):
    import pdfplumber
    with pdfplumber.open(pdf_path(campus)) as pdf:
        pages = [i for i, p in enumerate(pdf.pages, start=1)
                 if TIMETABLE_MARKER[campus] in (p.extract_text() or "")]
    return [pages[0], pages[-1]] if pages else None


def _clean_range_rows(campus):
    page_range = _timetable_page_range(campus)
    assert page_range, f"{campus}: no timetable pages found"
    return main.extract_pdf_tables(
        pdf_path(campus),
        main.DEFAULT_TIMETABLE_HEADERS[CAMPUS_CODES[campus]],
        page_range=page_range)


def test_a_clean_page_range_is_untouched():
    """The filter and the dedupe must be no-ops on a well-specified upload.

    Both exist for the whole-booklet case: junk rows come from the calendar and
    legend pages, and duplicates from Hyderabad printing both semesters. An
    admin who selects just the timetable pages should get byte-identical output
    to before either existed — otherwise this "safety net" is quietly rewriting
    good uploads.

    Pilani is excluded and has its own check below: its 2026-27 booklet prints
    real duplicate rows INSIDE the timetable pages, so collapsing them there is
    the job, not an accident of the page range.
    """
    import json
    rows = _clean_range_rows("hyd")
    before = main.parse_timetable_rows_hyd(rows)
    after = main.dedupe_by_doc_id(main.parse_timetable_rows(rows, "hyderabad"))

    assert json.dumps(before, sort_keys=True, default=str) == \
           json.dumps(after, sort_keys=True, default=str), \
        f"hyd: a clean range changed ({len(before)} -> {len(after)})"


def test_pilani_dedupe_only_merges_com_code_twins():
    """Dedupe may collapse the 2026-batch twin and nothing else.

    The guarantee that replaces byte-identity for Pilani: every course code
    survives, every surviving row keeps its own sections and exams, and the
    only rows that changed are the ones that gained the twin's number.
    """
    rows = _clean_range_rows("pilani")
    before = main.parse_timetable_rows(rows, "pilani")
    after = main.dedupe_by_doc_id(before)

    assert {c["courseCode"] for c in before} == {c["courseCode"] for c in after}, \
        "dedupe dropped a course code"

    by_code = {}
    for c in before:
        by_code.setdefault(c["courseCode"], []).append(c)

    merged = 0
    for c in after:
        originals = by_code[c["courseCode"]]
        assert c["sections"] in [o["sections"] for o in originals], \
            f"{c['courseCode']}: sections were rewritten, not merged"
        assert c["totalCredits"] in [o["totalCredits"] for o in originals]
        assert c["creditHours"] in [o["creditHours"] for o in originals]
        if len(originals) > 1:
            merged += 1
    assert merged == 142, merged


# ── The upload guard ────────────────────────────────────────────────────────


class _FakeRef:
    def __init__(self, count):
        self._count = count

    def list_documents(self):
        return [object()] * self._count


def test_real_booklets_pass_the_sanity_guard():
    """The guard must be silent on all three real parses, or it is unusable.

    This is the half that thresholds get wrong: a check that fires on good data
    gets force-ticked every upload and then protects nothing.
    """
    for campus in CAMPUS_CODES:
        courses = main.dedupe_by_doc_id(parse(campus))
        assert main.sanity_problems(courses) == [], campus


def test_sanity_guard_catches_the_goa_column_shift():
    """The exact shape of the 2026-07-29 write: title holds the L P U string.

    Every one of those 274 rows had correct sections, rooms, schedules and exam
    dates — only the code, title and credits were a column off. Row counts saw
    nothing wrong, which is why this checks content instead.
    """
    shifted = [
        {"courseCode": "MICROBIOLOGY", "courseTitle": "3 1 4", "totalCredits": 0,
         "sections": [{"sectionId": "L1", "schedule": [{"days": ["DayOfWeek.M"], "hours": [4]}]}]},
        {"courseCode": "CELL BIOLOGY", "courseTitle": "3 0 3", "totalCredits": 0,
         "sections": [{"sectionId": "L1", "schedule": [{"days": ["DayOfWeek.T"], "hours": [5]}]}]},
    ]
    problems = main.sanity_problems(shifted)
    assert problems, "the column shift passed the sanity guard"
    assert any("credit string as their title" in p for p in problems), problems

    try:
        main._guard_course_sanity(shifted)
    except main.CourseSanityError as e:
        assert "refusing" in str(e)
    else:
        raise AssertionError("expected the guard to refuse the shifted parse")

    # Force still has to work, or a genuine oddity becomes unuploadable.
    main._guard_course_sanity(shifted, force=True)


def test_sanity_guard_catches_a_code_title_swap():
    swapped = [{"courseCode": "MATH", "courseTitle": "MATH F211",
                "totalCredits": 3, "sections": []}]
    assert any("swapped" in p for p in main.sanity_problems(swapped))


def test_sanity_guard_catches_a_credits_column_that_moved():
    """Titles fine, credits all zero — the L P U column moved on its own."""
    courses = [{"courseCode": f"CS F{200 + i}", "courseTitle": f"COURSE {i}",
                "totalCredits": 0,
                "sections": [{"sectionId": "L1",
                              "schedule": [{"days": ["DayOfWeek.M"], "hours": [1]}]}]}
               for i in range(10)]
    assert any("zero credits" in p for p in main.sanity_problems(courses))


def test_sanity_guard_is_quiet_on_an_empty_parse():
    """Empty is upload_timetable's own error ("No courses found"), not this
    guard's — and 0/0 must not raise ZeroDivisionError on the way there."""
    assert main.sanity_problems([]) == []


# ── The upload preview ──────────────────────────────────────────────────────


class _FakeDoc:
    def __init__(self, doc_id, data):
        self.id = doc_id
        self._data = data

    def to_dict(self):
        return self._data


class _FakeDb:
    def __init__(self, docs):
        self._docs = docs

    def collection(self, _path):
        return self

    def get(self):
        return self._docs


def _live(doc_id, room, hours, credits=4, instructor="A"):
    return _FakeDoc(doc_id, {
        "sections": [{"sectionId": "L1", "room": room, "instructor": instructor,
                      "schedule": [{"days": ["DayOfWeek.M"], "hours": hours}]}],
        "total_credits": credits, "mid_sem_exam": None, "end_sem_exam": None,
    })


def _incoming(code, room, hours, credits=4, instructor="A"):
    return {"courseCode": code, "courseTitle": f"TITLE {code}",
            "totalCredits": credits,
            "sections": [{"sectionId": "L1", "room": room, "instructor": instructor,
                          "schedule": [{"days": ["DayOfWeek.M"], "hours": hours}]}],
            "midSemExam": None, "endSemExam": None}


def _preview(live_docs, incoming):
    real = main.get_db
    main.get_db = lambda: _FakeDb(live_docs)
    try:
        return main.build_timetable_preview(incoming, "goa")
    finally:
        main.get_db = real


def test_preview_reports_the_actual_diff():
    p = _preview(
        [_live("CS_F213", "D101", [1]), _live("CS_F214", "D102", [2]),
         _live("CS_F215", "D103", [3])],
        [_incoming("CS F213", "D101", [1]),        # untouched
         _incoming("CS F215", "D103", [9]),        # moved to a different hour
         _incoming("CS F301", "D104", [4])],       # new
    )
    assert (p["added"], p["removed"], p["changed"], p["unchanged"]) == (1, 1, 1, 1), p
    assert p["addedSample"] == ["CS_F301"], p
    assert p["removedSample"] == ["CS_F214"], p
    assert p["changedSample"] == ["CS_F215"], p


def test_preview_ignores_instructor_churn():
    """Instructor spelling changes between booklet revisions constantly. If that
    counted as a change the diff would read "417 changed" every upload and stop
    meaning anything."""
    p = _preview([_live("CS_F213", "D101", [1], instructor="R Aduri")],
                 [_incoming("CS F213", "D101", [1], instructor="RAVIPRASAD ADURI")])
    assert p["changed"] == 0, p


def test_preview_flags_a_room_change():
    p = _preview([_live("CS_F213", "D101", [1])],
                 [_incoming("CS F213", "D999", [1])])
    assert p["changed"] == 1, p


def test_preview_carries_the_sanity_problems():
    """The preview must show WHY an upload is about to be refused, not just
    that it will be."""
    p = _preview([_live("CS_F213", "D101", [1])],
                 [{"courseCode": "MICROBIOLOGY", "courseTitle": "3 1 4",
                   "totalCredits": 0, "sections": []}])
    assert p["problems"], p


def test_guard_refuses_an_implausible_drop():
    try:
        main._guard_course_count(_FakeRef(800), [{}] * 100)
    except main.CourseCountDropError as e:
        assert "refusing" in str(e)
        return
    raise AssertionError("expected the guard to refuse a 100-of-800 upload")


def test_guard_allows_a_normal_reupload():
    main._guard_course_count(_FakeRef(800), [{}] * 790)


def test_guard_allows_the_first_upload():
    main._guard_course_count(_FakeRef(0), [{}] * 5)


def test_guard_can_be_forced():
    main._guard_course_count(_FakeRef(800), [{}] * 10, force=True)


# ── Course history ──────────────────────────────────────────────────────────


def test_term_id_maps_exam_year_and_semester_to_a_session():
    # A first semester's exams fall in the session's opening calendar year; a
    # second semester's fall in the NEXT one, so it belongs to the prior session.
    assert main.term_id(2026, 1) == "2026-27-1"
    assert main.term_id(2026, 2) == "2025-26-2"
    assert main.term_id(1999, 1) == "1999-00-1"  # two-digit wrap keeps its zero


def test_term_ids_sort_chronologically_as_strings():
    """The client orders terms by plain string sort rather than parsing them."""
    ids = [main.term_id(2025, 1), main.term_id(2026, 2), main.term_id(2026, 1)]
    assert sorted(ids) == ["2025-26-1", "2025-26-2", "2026-27-1"], sorted(ids)


def test_offerings_exclude_courses_that_did_not_run():
    """A course printed with no sections was not offered that semester, and its
    absence is what "last offered" is computed from."""
    offerings = main.build_term_offerings([
        _incoming("CS F213", "D101", [1], instructor="R ADURI"),
        {"courseCode": "CS F407", "courseTitle": "AI", "totalCredits": 3,
         "sections": []},
    ])
    assert set(offerings) == {"CS_F213"}, offerings


def test_offerings_record_distinct_canonical_instructors():
    """Same person, three spellings across two sections: one canonical name.

    The booklet lists the instructor-in-charge again as an instructor, in a
    different case, and wraps long names across lines.
    """
    offerings = main.build_term_offerings([{
        "courseCode": "BIO F110",
        "courseTitle": "BIOLOGY LABORATORY",
        "totalCredits": 1,
        "sections": [
            {"sectionId": "P1", "instructor": "AMARTYA SANYAL, Amartya Sanyal"},
            {"sectionId": "P2", "instructor": "PARDHA SARADHI\nGURUGUBELLI"},
        ],
    }])
    entry = offerings["BIO_F110"]
    assert entry["instructors"] == ["AMARTYA SANYAL", "PARDHA SARADHI GURUGUBELLI"], entry
    assert entry["sections"] == 2, entry
    # A property of the course, not of the term it ran in: resolved from
    # courses_master by the client, so it is deliberately absent here.
    assert "credits" not in entry and "title" not in entry, entry


def test_capitalised_instructors_are_the_ones_in_charge():
    """The booklet marks the instructor-in-charge by CAPITALISING them.

    Case therefore has to be read before names are upper-cased for identity —
    and the in-charge is normally listed a SECOND time in title case as their own
    section's instructor, so "first name seen" is not the rule.
    """
    offerings = main.build_term_offerings([{
        "courseCode": "BIO F110",
        "sections": [
            {"sectionId": "P1", "instructor": "Kirtimaan Syal, Piyush Khandelia"},
            {"sectionId": "P2", "instructor": "AMARTYA SANYAL, Amartya Sanyal"},
        ],
    }])
    entry = offerings["BIO_F110"]
    assert entry["ic"] == ["AMARTYA SANYAL"], entry
    # Still present in the full list, once.
    assert entry["instructors"] == [
        "KIRTIMAAN SYAL", "PIYUSH KHANDELIA", "AMARTYA SANYAL"], entry


def test_a_course_with_no_capitalised_name_has_no_one_in_charge():
    """10 of 333 courses in the 2026-27 booklet print none. Empty, not guessed."""
    offerings = main.build_term_offerings([{
        "courseCode": "ECE F216",
        "sections": [{"sectionId": "L1", "instructor": "Sanket Goel"}],
    }])
    assert offerings["ECE_F216"]["ic"] == [], offerings
    assert offerings["ECE_F216"]["instructors"] == ["SANKET GOEL"]


def test_non_ascii_debris_is_treated_as_whitespace_not_a_letter():
    """The booklets carry U+00C2 "Â" in five names — an orphaned UTF-8
    non-breaking space, not an accent.

    Unicode folding would decompose it to "A" and silently produce
    "HANS KRUPAKARA" / "VIJAYA ANGADI": plausible names that are wrong. It has to
    collapse to a space instead, mid-name and trailing alike.
    """
    offerings = main.build_term_offerings([{
        "courseCode": "CS G526",
        "sections": [
            {"sectionId": "L1", "instructor": "Hans KrupakarÂ, VijayÂ Angadi"},
            {"sectionId": "L2", "instructor": "Hanamkonda Sai SharanyaÂ"},
        ],
    }])
    assert offerings["CS_G526"]["instructors"] == [
        "HANS KRUPAKAR", "VIJAY ANGADI", "HANAMKONDA SAI SHARANYA"], offerings


def test_cleaning_a_name_merges_it_with_its_clean_spelling():
    """The same person written both ways is one instructor, not two.

    This is the point of cleaning at the source rather than at display: the
    upper-cased name is the identity key, so debris forked one professor into two
    rows in the history and two entries in the professors list.
    """
    offerings = main.build_term_offerings([{
        "courseCode": "CS F342",
        "sections": [
            {"sectionId": "L1", "instructor": "Pranay SharmaÂ"},
            {"sectionId": "L2", "instructor": "Pranay Sharma"},
        ],
    }])
    assert offerings["CS_F342"]["instructors"] == ["PRANAY SHARMA"], offerings


def test_placeholder_and_stray_instructors_are_dropped():
    """"TBA" is not a person, and a single character is a split artefact.

    All eighteen spellings the booklets use are covered; the anchoring matters
    because an unanchored match also hits "Harshal Vasan(t Ba)rkale".
    """
    offerings = main.build_term_offerings([{
        "courseCode": "ME F341",
        "sections": [
            {"sectionId": "L1", "instructor": "TBA, Tba. Mech, TBA-ECON, Tba.mech"},
            {"sectionId": "L2", "instructor": "N, a, -, Harshal Vasant Barkale"},
            # A real name that an unanchored or unbounded rule would eat.
            {"sectionId": "L3", "instructor": "T. B. Anand"},
        ],
    }])
    assert offerings["ME_F341"]["instructors"] == [
        "HARSHAL VASANT BARKALE", "T. B. ANAND"], offerings
    assert offerings["ME_F341"]["ic"] == [], offerings


def test_offerings_keep_the_richer_of_two_duplicate_rows():
    """Two rows collapsing onto one document id — a cross-listed code — must
    resolve to the fuller row, not to whichever the registrar printed last.

    Both rows carry sections, so the section filter above cannot decide this
    one; and the fuller row comes FIRST, so last-write-wins would lose it.
    """
    full = _incoming("EEE F211 / ECE F211", "D101", [1], instructor="R ADURI")
    full["sections"].append({"sectionId": "L2", "room": "D102",
                             "instructor": "A NAIR", "schedule": []})
    offerings = main.build_term_offerings([
        full,
        _incoming("EEE F211", "D999", [5], instructor="SOMEONE ELSE"),
    ])
    assert list(offerings) == ["EEE_F211"], offerings
    assert offerings["EEE_F211"]["sections"] == 2, offerings


if __name__ == "__main__":
    if not have_pdfs():
        missing = [c for c in CAMPUS_CODES if not os.path.exists(pdf_path(c))]
        print(f"SKIP  timetable PDFs not present in repo root: {missing}")
        print("      (they are gitignored admin inputs; place them there to run)")
        sys.exit(0)

    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS  {t.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"  FAIL  {t.__name__}: {e}")
    print(f"\n{len(tests) - failed}/{len(tests)} passed")
    sys.exit(1 if failed else 0)

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
    expected = {"hyd": 855, "pilani": 407, "goa": 377}
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
    courses = parse("hyd")
    forward = {c["courseCode"]: c["totalCredits"]
               for c in main.dedupe_by_doc_id(courses)}
    backward = {c["courseCode"]: c["totalCredits"]
                for c in main.dedupe_by_doc_id(list(reversed(courses)))}
    assert forward == backward, "dedupe result depends on input order"


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


def test_a_clean_page_range_is_untouched():
    """The filter and the dedupe must be no-ops on a well-specified upload.

    Both exist for the whole-booklet case: junk rows come from the calendar and
    legend pages, and duplicates from the booklet printing both semesters. An
    admin who selects just the timetable pages should get byte-identical output
    to before either existed — otherwise this "safety net" is quietly rewriting
    good uploads.
    """
    import json
    raw_parsers = {
        "hyd": main.parse_timetable_rows_hyd,
        "pilani": main.parse_timetable_rows_pilani,
    }
    for campus, raw_parser in raw_parsers.items():
        page_range = _timetable_page_range(campus)
        assert page_range, f"{campus}: no timetable pages found"
        rows = main.extract_pdf_tables(
            pdf_path(campus),
            main.DEFAULT_TIMETABLE_HEADERS[CAMPUS_CODES[campus]],
            page_range=page_range)

        before = raw_parser(rows)
        after = main.dedupe_by_doc_id(
            main.parse_timetable_rows(rows, CAMPUS_CODES[campus]))

        assert json.dumps(before, sort_keys=True, default=str) == \
               json.dumps(after, sort_keys=True, default=str), \
            f"{campus}: a clean range changed ({len(before)} -> {len(after)})"


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

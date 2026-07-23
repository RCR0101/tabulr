"""Parser checks for the academic-calendar extraction in main.py.

Run from the repo root with the functions venv (no pytest dependency):

    functions-python/venv/bin/python functions-python/test_academic_calendar.py

The fixtures are the real timetable booklets in the repo root, so this also
guards against a pdfplumber upgrade changing extraction behaviour.
"""
import os
import sys

import main

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CALENDAR_PAGE = {"hyd": [2, 2], "goa": [1, 1], "pilani": [2, 2]}


def parse(campus):
    return main.parse_academic_calendar(
        os.path.join(ROOT, f"timetable-{campus}.pdf"), CALENDAR_PAGE[campus], 2026)


def find(events, needle):
    matches = [e for e in events if needle in e["label"]]
    return matches[0] if matches else None


def test_hyderabad_extracts_every_row_cleanly():
    events = parse("hyd")
    # The Hyd second-semester list has 37 dated rows.
    assert len(events) == 37, len(events)
    dates = [e["date"] for e in events]
    assert dates == sorted(dates)
    assert all(d.startswith("2026") for d in dates)


def test_key_deadlines_and_categories():
    events = parse("hyd")

    withdrawal = find(events, "withdrawal")
    assert withdrawal and withdrawal["date"] == "2026-03-20"
    assert withdrawal["category"] == "deadline"

    substitution = find(events, "substitution")
    assert substitution and substitution["date"] == "2026-01-21"
    assert substitution["category"] == "deadline"


def test_ranges_carry_an_end_date():
    midsem = find(parse("hyd"), "Mid Semester Exams")
    assert midsem and midsem["date"] == "2026-03-09"
    assert midsem["endDate"] == "2026-03-14"
    assert midsem["category"] == "exam"


def test_holidays_are_categorised():
    holi = find(parse("hyd"), "Holi")
    assert holi and holi["category"] == "holiday"


def test_year_filter_drops_the_other_semester():
    # Goa prints both semesters; only the 2026 (second) semester survives.
    events = parse("goa")
    assert events, "expected some Goa second-semester events"
    assert all(e["date"].startswith("2026") for e in events)
    assert find(events, "Independence Day") is None


def test_date_body_parsing_forms():
    # Ranges/lists become month/day components; years are assigned later.
    r = main._cal_parse_body("March", "09 (M)–March 14 (S)")
    assert r and (r["start_month"], r["start_day"]) == (3, 9)
    assert (r["end_month"], r["end_day"]) == (3, 14)
    r = main._cal_parse_body("April", "3(F) - 5(Su)")
    assert r and (r["start_day"], r["end_day"]) == (3, 5)
    r = main._cal_parse_body("February", "20, 21 & 22")
    assert r and (r["start_day"], r["end_day"]) == (20, 22)
    r = main._cal_parse_body("January", "5 (M)")
    assert r and r["start_day"] == 5 and r["end_day"] is None
    assert r["dayOfWeek"] == "M"


def test_year_assignment_by_semester():
    # Second semester: Jan–Jul are exam_year; a printed Aug–Dec row is dropped.
    e = {"start_month": 3, "start_day": 20, "end_month": None, "end_day": None,
         "dayOfWeek": None, "label": "x", "category": "deadline"}
    assert main._assign_years(e, 2026, 2)["date"] == "2026-03-20"
    aug = {**e, "start_month": 8, "start_day": 1}
    assert main._assign_years(aug, 2026, 2) is None

    # First semester: Jul–Dec are exam_year; a Dec→Jan range wraps its end.
    oct_row = {**e, "start_month": 10, "start_day": 5}
    assert main._assign_years(oct_row, 2026, 1)["date"] == "2026-10-05"
    jan = {**e, "start_month": 1, "start_day": 5}
    assert main._assign_years(jan, 2026, 1) is None  # not sem-1
    recess = {"start_month": 12, "start_day": 20, "end_month": 1, "end_day": 3,
              "dayOfWeek": None, "label": "Recess", "category": "event"}
    got = main._assign_years(recess, 2026, 1)
    assert got["date"] == "2026-12-20" and got["endDate"] == "2027-01-03"


def test_first_semester_pdf_end_to_end():
    path = os.path.join(ROOT, "Academic calendar I sem 2026 -27.pdf")
    if not os.path.exists(path):
        print("  (skip: first-sem PDF not present)")
        return
    # Auto-detects "Semester 1" from the heading; all rows land in H2 2026.
    events = main.parse_academic_calendar(path, [1, 1], 2026)
    assert events, "expected first-semester events"
    assert all(7 <= int(e["date"][5:7]) <= 12 for e in events), \
        "every start date should be Jul–Dec"
    assert all(e["date"].startswith("2026") for e in events)
    classwork = find(events, "Class work begins")
    assert classwork and classwork["date"] == "2026-08-03"
    # The Dec→Jan recess range wraps into 2027.
    recess = find(events, "Recess")
    assert recess and recess.get("endDate", "").startswith("2027")


if __name__ == "__main__":
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

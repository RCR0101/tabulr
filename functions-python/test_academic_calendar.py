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

# The 2026-27 first-semester booklets (the fixtures were refreshed 2026-07).
# When next term's booklets replace them, re-derive these facts from the PDFs.
CALENDAR_PAGE = {"hyd": [2, 2], "goa": [2, 2], "pilani": [2, 2]}


def parse(campus, semester=1, exam_year=2026):
    return main.parse_academic_calendar(
        os.path.join(ROOT, f"timetable-{campus}.pdf"), CALENDAR_PAGE[campus],
        exam_year, semester=semester)


def find(events, needle):
    matches = [e for e in events if needle in e["label"]]
    return matches[0] if matches else None


def test_hyderabad_extracts_every_row_cleanly():
    events = parse("hyd")
    assert len(events) == 34, len(events)
    dates = [e["date"] for e in events]
    assert dates == sorted(dates)
    assert all(d.startswith("2026") for d in dates)


def test_key_deadlines_and_categories():
    events = parse("hyd")
    withdrawal = find(events, "withdrawal")
    assert withdrawal and withdrawal["date"] == "2026-09-21"
    assert withdrawal["category"] == "deadline"
    substitution = find(events, "substitution")
    assert substitution and substitution["date"] == "2026-08-17"
    assert substitution["category"] == "deadline"


def test_ranges_carry_an_end_date():
    events = parse("hyd")
    # "October 5 (M)--10 (S)": a doubled dash is still a range.
    midsem = find(events, "Mid sem Exam")
    assert midsem and (midsem["date"], midsem["endDate"]) == ("2026-10-05", "2026-10-10")
    assert midsem["category"] == "exam"
    assert not midsem["label"].startswith("-")
    # "December 20" / "(Su)—January 3 (Su) Recess": the date runs onto the next line.
    recess = find(events, "Recess")
    assert recess and (recess["date"], recess["endDate"]) == ("2026-12-20", "2027-01-03")


def test_wrapped_labels_stay_with_their_date():
    # The booklet centres a date in a two-line cell, so a label's first line is
    # printed ABOVE its date; it used to be glued onto the previous event.
    events = parse("hyd")
    atmos = find(events, "ATMOS")
    assert atmos["label"] == "ATMOS - 2026 (Class work Suspended)", atmos
    assert atmos["endDate"] == "2026-10-25"
    returning = find(events, "returning evaluated")
    assert returning["date"] == "2026-10-28"
    assert returning["label"] == "Last day for returning evaluated answer scripts of Mid-Semester Test"
    phd = find(events, "Ph.D.")
    assert (phd["date"], phd["endDate"]) == ("2026-11-27", "2026-11-28")
    assert phd["label"] == "Test/Interview for II Semester 2026-27 Ph.D. Admissions"


def test_holidays_are_categorised():
    events = parse("hyd")
    for name in ("Deepavali", "Christmas", "Independence Day"):
        e = find(events, name)
        assert e and e["category"] == "holiday", name


def test_grid_beside_the_list_does_not_eat_rows():
    # Pilani prints the month grid on the same lines as the list; those rows
    # ("12 13 ... 19 August 3(M) Classwork begins") used to be dropped.
    events = parse("pilani")
    assert len(events) == 37, len(events)
    assert find(events, "Classwork begins")["date"] == "2026-08-03"
    assert find(events, "Deepavali")["date"] == "2026-11-08"
    assert find(events, "substitution")["date"] == "2026-08-18"
    assert not any("OCTOBER" in e["label"] or "Note" in e["label"] for e in events)
    # Split over two date lines: "October 5(M)-" ... "October 10(S)".
    midsem = find(events, "Mid-Semester Examinations")
    assert (midsem["date"], midsem["endDate"]) == ("2026-10-05", "2026-10-10")
    # "December25 (F) C h r i s t m a s ( H )": glued date, spaced letters.
    assert find(events, "Christmas")["label"] == "Christmas (H)"
    assert find(events, "Recess")["label"] == "Recess for students"


def test_year_filter_drops_the_other_semester():
    # Goa prints both semesters side by side. For the first semester, the
    # even-semester column's July rows ("Summer term ends") are next July.
    events = parse("goa")
    assert len(events) == 36, len(events)
    assert all(e["date"].startswith("2026") for e in events)
    assert find(events, "Summer term") is None
    assert find(events, "Makar Sankranti") is None
    # "Dec 20 (Su) -- Jan 3": abbreviated months.
    recess = find(events, "Recess")
    assert (recess["date"], recess["endDate"]) == ("2026-12-20", "2027-01-03")
    assert find(events, "Goa Liberation Day")["date"] == "2026-12-19"


def test_goa_second_semester_column():
    events = parse("goa", semester=2, exam_year=2027)
    assert len(events) == 35, len(events)
    assert find(events, "Independence Day") is None
    # "March 08 (M)– Mid-semester ... (classwork" / "March 15 (M) suspended)"
    midsem = find(events, "Mid-semester examinations")
    assert (midsem["date"], midsem["endDate"]) == ("2027-03-08", "2027-03-15")
    assert midsem["label"] == "Mid-semester examinations (classwork suspended)"
    # Letter-spaced "M a y 3 (M)".
    assert find(events, "Comprehensive examinations begin")["date"] == "2027-05-03"
    # "May 18 (T)–May" / "19 (W) admissions".
    phd = find(events, "Ph.D.")
    assert (phd["date"], phd["endDate"]) == ("2027-05-18", "2027-05-19")
    assert phd["label"].startswith("Test/Interview")
    assert find(events, "Buddha Purnima")["label"] == "Buddha Purnima (H)"


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
    # "October 23 (F) -" / "25(Su) ATMOS": a bare end day, not the next date.
    atmos = find(events, "ATMOS")
    assert (atmos["date"], atmos["endDate"]) == ("2026-10-23", "2026-10-25")
    assert find(events, "returning evaluated")["date"] == "2026-10-28"


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

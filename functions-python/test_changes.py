"""Checks for changes.py, the LMS timetable-change PDF parser.

    functions-python/venv/bin/python functions-python/test_changes.py

The cell and judging checks always run. The golden checks read the real
"Timetable changes-4/5/6" PDFs from the repo root (timetable-changes-N.pdf,
gitignored like the other source PDFs) and skip when they are absent.
"""
import os

import changes

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sec(sid, instructor="", room="", schedule=()):
    return {"sectionId": sid, "type": f"SectionType.{sid[0]}", "instructor": instructor,
            "room": room, "schedule": list(schedule)}


def slot(days, hours):
    return {"days": [f"DayOfWeek.{d}" for d in days], "hours": hours}


def test_cells():
    assert changes.parse_slots("T TH 4 F 5 I 111") == ({("T", 4), ("Th", 4), ("F", 5)}, ["I111"])
    assert changes.parse_slots("W 4 F5") == ({("W", 4), ("F", 5)}, [])
    assert changes.parse_slots("T 11\nTH 11 & 12\nJ107") == ({("T", 11), ("Th", 11), ("Th", 12)}, ["J107"])
    assert changes.parse_slots("M 10 &\nT TH 1 F208") == ({("M", 10), ("T", 1), ("Th", 1)}, ["F208"])
    assert changes.parse_slots("F-205") == (set(), ["F205"])
    assert changes.slots_to_schedule({("M", 3), ("W", 3), ("F", 3), ("W", 8), ("W", 9)}) == [
        slot(["M", "F"], [3]), slot(["W"], [3, 8, 9])]
    assert changes.parse_sections("AL P1") == ["P1"]
    assert changes.parse_sections("L1 T1 &\nP1") == ["L1", "T1", "P1"]
    assert changes.parse_names("Akshya Gundala/Muddasani Raj\nKumar/ Sujith R/ Sayan\nDas,/Mohd Talha") == [
        "Akshya Gundala", "Muddasani Raj Kumar", "Sujith R", "Sayan Das", "Mohd Talha"]
    assert changes.parse_names("Sk Aziz Ali / Tba Cs") == ["Sk Aziz Ali"]
    assert changes.parse_names("Wadkar Avinash Rudrappa (sangita)") == ["Wadkar Avinash Rudrappa"]
    # A bare line break splits only after a name the timetable knows.
    known = frozenset({"abhijeetrajendrajoshi"})
    assert changes.parse_names("Abhijeet Rajendra Joshi\nAbhipshit Kalita, Kartik Tyagi", known) == [
        "Abhijeet Rajendra Joshi", "Abhipshit Kalita", "Kartik Tyagi"]
    assert changes.parse_names("Zinataman Sarkar / Venkata\nVamsi Krishna Venuganti", known) == [
        "Zinataman Sarkar", "Venkata Vamsi Krishna Venuganti"]
    assert changes.same_people(["Sweta Agarwala", "Balaji Gopalan"], ["Balaji Gopalan", "Sweta Agarwal"])
    assert not changes.same_people(["Pranay Sharma"], ["Samridhh Singh"])
    ex = changes.parse_exams("16/12 FN\nNO EXAM")
    assert ex["mid_sem_exam"] is None and ex["end_sem_exam"]["timeSlot"] == "TimeSlot.FN", ex
    assert changes.parse_exams("-----------") == {}
    assert changes.parse_exams("10/10 - 11.30 - 1.00PM")["mid_sem_exam"]["timeSlot"] == "TimeSlot.MS2"


TABLES = [
    [["Sl No", "Course No", "Course Title", "Section\nNo", "Existing", "New"],
     ["1)", "CS F214", "Logic", "T3", "Sameera Muhamed Salam / TBA", "Sameera Muhamed Salam /\nArnab Hazra"],
     ["", "", "", "T4", "Sameera Muhamed Salam / TBA", "Sameera Muhamed Salam /\nArnab Hazra"]],
    # Page furniture: a headerless table of a different width is skipped.
    [["Engineering Gra"], ["phics"]],
    # The same table carried onto the next page.
    [["2)", "CS F342", "COMPUTER ARCHITECTURE", "P1", "Aritra Mukherjee / Pranay Sharma", "Aritra Mukherjee / Samridhh\nSingh"]],
    [["S.No", "Course No", "Course Title", "SEC", "Existing\nRoom/Hour", "New Room\nRoom/Hour"],
     ["2)", "BIO F312", "PLANT PHYSIOLOGY", "L1", "T TH 1 F 5", "T 1 W F 5 G101"],
     [None, None, None, "", "W 5", "TH 1 G101"],
     ["4)", "CS F342", "COMPUTER ARCHITECTURE", "P3", "D312", "D313"]],
    [["S.No", "Course No", "Course Title", "Existing\nMid-Sem & Compre Exam", "New\nMid-Sem & Compre Exam"],
     ["1)", "CHEM F211", "PHYSICAL CHEMISTRY I", "03/10 - 4.00 - 5.30PM\n05/12 AN", "10/10 - 11.30 - 1.00PM\n05/12 FN"]],
    [["S.No", "Course No", "Course\nTitle", "SE\nC", "Intructor Name", "Room/Hour", "Mid-Sem & Compre\nExam"],
     ["1", "BITS G524", "HEALTH ECONOMICS", "L1", "RISHI KUMAR.", "M W F 7\nK220", "08/10 - 2.00 - 3.30PM\n09/12 AN"],
     ["2", "ECE F242", "CONTROL\nSYSTEMS", "L1 & T1", "HARISH VIJAY", "M W 9 10\nI 122", "05/10 - 9.30 - 11.00AM\n01/12 FN"]],
]

DOCS = {
    "CS_F214": {"sections": [sec("T3", "Sameera Muhamed Salam"), sec("T4", "Sameera Muhamed Salam, Arnab Hazra")]},
    "CS_F342": {"sections": [sec("P1", "Aritra Mukherjee, Pranay Sharma"),
                             sec("P3", "X", "D312", [slot(["Th"], [2, 3])])]},
    "BIO_F312": {"sections": [sec("L1", "Sridev Mohapatra", "G101", [slot(["T", "Th"], [1]), slot(["F"], [5])]),
                              sec("T1", "Sridev Mohapatra", "G101", [slot(["W"], [5])])]},
    "CHEM_F211": {"sections": [sec("L1")],
                  "mid_sem_exam": {"date": "2026-10-10T00:00:00.000Z", "timeSlot": "TimeSlot.MS2"},
                  "end_sem_exam": {"date": "2026-12-05T00:00:00.000Z", "timeSlot": "TimeSlot.AN"}},
}
MASTERS = {"BITS_G524": {"course_code": "BITS G524", "credits": 5}, "ECE_F242": {"course_code": "ECE F242", "credits": 3}}


def test_tables_and_judging():
    rows = changes.rows_from_tables(TABLES)
    props = {p["key"]: p for p in changes.propose(rows, DOCS, MASTERS)}
    assert [k for k in props] == [
        "instructor|CS F214|T3|1", "instructor|CS F214|T4|1", "instructor|CS F342|P1|1",
        "schedule|BIO F312|L1|1", "schedule|BIO F312|L1|2", "schedule|CS F342|P3|1",
        "exam|CHEM F211||1", "new_course|BITS G524||1", "new_course|ECE F242||1"], list(props)
    status = {k: p["status"] for k, p in props.items()}
    assert status == {
        "instructor|CS F214|T3|1": "apply",   # live still "existing" (TBA dropped)
        "instructor|CS F214|T4|1": "done",    # already edited by hand
        "instructor|CS F342|P1|1": "apply",
        "schedule|BIO F312|L1|1": "apply",
        "schedule|BIO F312|L1|2": "apply",      # the blank-section row is the tutorial's
        "schedule|CS F342|P3|1": "apply",
        "exam|CHEM F211||1": "apply",         # mid already moved, compre not yet
        "new_course|BITS G524||1": "apply",
        "new_course|ECE F242||1": "manual",   # two sections, one hours cell
    }, status
    assert props["schedule|BIO F312|L1|2"]["section"] == "T1"

    touched, applied = changes.apply_selected(rows, DOCS, MASTERS, list(props))
    assert len(applied) == 7, applied
    bio = {s["sectionId"]: s for s in touched["BIO_F312"]["sections"]}
    assert changes.schedule_to_slots(bio["L1"]["schedule"]) == {("T", 1), ("W", 5), ("F", 5)}
    assert changes.schedule_to_slots(bio["T1"]["schedule"]) == {("Th", 1)}
    assert touched["CS_F342"]["sections"][1]["room"] == "D313"
    assert touched["CS_F342"]["sections"][0]["instructor"] == "Aritra Mukherjee, Samridhh Singh"
    assert touched["CHEM_F211"]["end_sem_exam"]["timeSlot"] == "TimeSlot.FN"
    g524 = touched["BITS_G524"]
    assert g524["total_credits"] == 5 and g524["sections"][0]["room"] == "K220", g524
    assert g524["sections"][0]["instructor"] == "RISHI KUMAR"
    assert DOCS["CS_F342"]["sections"][1]["room"] == "D312", "DOCS untouched"

    # Re-judged after applying, nothing is left to apply: the edits are idempotent.
    after = changes.propose(rows, {**DOCS, **touched}, MASTERS)
    assert not [p for p in after if p["status"] in changes.SELECTABLE], after
    # With only the first BIO row applied, the blank-section row still means T1.
    half, _ = changes.apply_selected(rows, DOCS, MASTERS, ["schedule|BIO F312|L1|1"])
    mid = {p["key"]: p for p in changes.propose(rows, {**DOCS, **half}, MASTERS)}
    assert (mid["schedule|BIO F312|L1|2"]["section"], mid["schedule|BIO F312|L1|2"]["status"]) == ("T1", "apply")
    # A row nobody selected is never written.
    touched, _ = changes.apply_selected(rows, DOCS, MASTERS, ["exam|CHEM F211||1"])
    assert list(touched) == ["CHEM_F211"]


# Rows per PDF, by kind, as the Timetable Division printed them.
GOLDEN = {
    4: {"instructor": 2, "schedule": 9, "exam": 2, "new_course": 7},
    5: {"instructor": 19, "exam": 3, "schedule": 3, "new_course": 7},
    6: {"instructor": 18},
}


def test_real_pdfs():
    for n, want in GOLDEN.items():
        path = os.path.join(ROOT, f"timetable-changes-{n}.pdf")
        if not os.path.exists(path):
            print(f"SKIP timetable-changes-{n}.pdf not found")
            continue
        rows = changes.parse_pdf(path)
        got = {}
        for r in rows:
            got[r["kind"]] = got.get(r["kind"], 0) + 1
        assert got == want, (n, got)
        if n == 5:
            p5 = next(r for r in rows if r["course"] == "BITS U104" and r["section"] == "P5")
            assert "Mohd Talha" in changes.parse_names(p5["new"]), p5
        if n == 4:
            e = next(r for r in rows if r["course"] == "EEE F314")
            assert changes.parse_exams(e["new"])["mid_sem_exam"] is None


if __name__ == "__main__":
    test_cells()
    test_tables_and_judging()
    test_real_pdfs()
    print("test_changes.py passed")

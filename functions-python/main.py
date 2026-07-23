import json
import os
import re
import tempfile
from datetime import datetime
from firebase_admin import initialize_app, firestore, storage
from firebase_functions import https_fn, options

initialize_app()

_db = None
_bucket = None

def get_db():
    global _db
    if _db is None:
        _db = firestore.client()
    return _db

def get_bucket():
    global _bucket
    if _bucket is None:
        _bucket = storage.bucket()
    return _bucket

BATCH_SIZE = 450
EXAM_YEAR = 2026

DEFAULT_TIMETABLE_HEADERS_HYD = [
    "COMP\nCODE",
    "COMP CODE",
    "DRAFT TIMETABLE",
    "TIMETABLE I SEM",
    "TIMETABLE II SEM",
    "UPDATED TIMETABLE",
]

DEFAULT_TIMETABLE_HEADERS_PILANI = [
    "COURSEWISE TIMETABLE",
    "FIRST SEMESTER",
    "SECOND SEMESTER",
    "COM\nCOD",
    "COURSE NO.",
    "COURSE TITLE",
    "CREDIT",
    "INSTRUCTOR-IN-CHARGE",
    "DAYS &\nHOURS",
    "MIDSEM\nDATE &\nSESSION",
    "COMPRE\nDATE &\nSESSION",
    "*Sections ending with",
    "*There will be changes",
]

PILANI_EXTRA_HEADERS = {"L", "P", "U"}

DEFAULT_TIMETABLE_HEADERS_GOA = [
    "BIRLA INSTITUTE OF TECHNOLOGY AND SCIENCE",
    "BIRLA INSTITUTE",
    "TIMETABLE FIRST SEMESTER",
    "TIMETABLE SECOND SEMESTER",
    "COMCODE",
    "COURSE NO",
]

DEFAULT_TIMETABLE_HEADERS = {
    "hyderabad": DEFAULT_TIMETABLE_HEADERS_HYD,
    "pilani": DEFAULT_TIMETABLE_HEADERS_PILANI,
    "goa": DEFAULT_TIMETABLE_HEADERS_GOA,
}

DEFAULT_EXAM_HEADERS = [
    "Course Code",
    "Course Title",
    "Date of exam",
    "Room No",
    "ID From - To",
    "No. of stu.",
    "S.No",
    "SEATING ARRANGEMENT",
    "Seating Arrangement",
    "SEATING ARRANGEMENT FOR THE I SEMESTER 2025 -26",
    "COMPREHENSIVE EXAMINATION",
    "MIDSEMESTER EXAMINATION",
    "MID SEMSTER EXAMINATIONS",
    "COMPREHENSIVE EXAMINATION SECOND SEMESTER 2025 -26",
    "COURSE CODE",
]

CAMPUS_IDS = {"pilani": "pilani", "hyderabad": "hyderabad", "hyd": "hyderabad", "goa": "goa"}
CAMPUS_NAMES = {"pilani": "Pilani", "hyderabad": "Hyderabad", "hyd": "Hyderabad", "goa": "Goa"}


def require_admin(req: https_fn.CallableRequest):
    if req.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.UNAUTHENTICATED, "Must be signed in")
    # Email-based admins: source of truth is the `admin_emails` collection
    # (keyed by lowercased email). Matches the Node functions / Firestore rules.
    email = (req.auth.token or {}).get("email")
    if not email:
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.PERMISSION_DENIED, "Not an admin")
    doc = get_db().collection("admin_emails").document(email.lower()).get()
    if not doc.exists:
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.PERMISSION_DENIED, "Not an admin")
    return req.auth.uid


def sanitize(s):
    if not isinstance(s, str):
        return s
    return re.sub(r"\s+", " ", s.replace("\n", " ").replace("\r", " ")).strip()


def course_code_to_doc_id(code):
    s = sanitize(code)
    primary = s.split("/")[0].strip() if "/" in s else s
    return re.sub(r"\s+", "_", primary)


# ─── PDF extraction (ported from converter.py / convert-exam-seating.py) ───


def _row_matches_header(row, exclude_headers, exact_match_headers=None):
    for cell in row:
        if cell is None:
            continue
        cell_str = str(cell).strip()
        if not cell_str:
            continue
        if exact_match_headers and cell_str in exact_match_headers:
            return True
        for header in exclude_headers:
            if header in cell_str:
                return True
    return False


def extract_pdf_tables(pdf_path, exclude_headers, page_range=None, exact_match_headers=None):
    import pdfplumber

    pdf = pdfplumber.open(pdf_path)
    pages = pdf.pages
    if page_range and len(page_range) == 2:
        pages = pages[page_range[0] - 1 : page_range[1]]

    all_rows = []
    max_cols = 0
    for page in pages:
        table = page.extract_table()
        if table is None:
            continue
        for row in table:
            if row is None:
                continue
            if _row_matches_header(row, exclude_headers, exact_match_headers):
                continue
            cleaned = [c if c is not None else "" for c in row]
            if len(cleaned) > max_cols:
                max_cols = len(cleaned)
            all_rows.append(cleaned)

    for i, row in enumerate(all_rows):
        if len(row) < max_cols:
            all_rows[i] = row + [""] * (max_cols - len(row))

    pdf.close()
    return all_rows


# ─── Timetable parser (ported from upload-timetable-fresh-hyd.js) ───


def get_cell(row, idx):
    if idx >= len(row):
        return None
    v = row[idx]
    return v if v is not None else None


def get_cell_str(row, idx):
    v = get_cell(row, idx)
    if v is None:
        return ""
    return str(v).strip()


def get_numeric(row, idx):
    v = get_cell(row, idx)
    if v is None:
        return 0
    if isinstance(v, (int, float)):
        return round(v)
    s = str(v).strip()
    if s in ("", "-"):
        return 0
    try:
        return round(float(s))
    except ValueError:
        return 0


def is_empty_row(row):
    return all(c is None or str(c).strip() == "" for c in row)


def parse_section_type(section_id):
    if section_id.startswith("L"):
        return "SectionType.L"
    if section_id.startswith("P"):
        return "SectionType.P"
    if section_id.startswith("T"):
        return "SectionType.T"
    return "SectionType.L"


DAY_MAP = {"M": "DayOfWeek.M", "T": "DayOfWeek.T", "W": "DayOfWeek.W",
            "Th": "DayOfWeek.Th", "F": "DayOfWeek.F", "S": "DayOfWeek.S"}


def parse_days(days_str):
    if not days_str:
        return []
    return [DAY_MAP[p.strip()] for p in days_str.split(" ") if p.strip() in DAY_MAP]


def parse_hours(hours_str):
    if not hours_str:
        return []
    hours = []
    for p in str(hours_str).strip().split():
        try:
            h = int(p)
            if 1 <= h <= 12:
                hours.append(h)
        except ValueError:
            pass
    return hours


def parse_midsem_exam(exam_str):
    if not exam_str:
        return None
    s = str(exam_str).strip()
    if not s:
        return None
    parts = s.split(" - ")
    if len(parts) < 2:
        return None
    date_part = parts[0].strip()
    time_part = parts[1].strip()
    dc = date_part.split("/")
    if len(dc) != 2:
        return None
    try:
        day, month = int(dc[0]), int(dc[1])
    except ValueError:
        return None
    year = EXAM_YEAR
    clean = time_part.replace(".", ":").replace(" ", "")
    if "9:30" in clean:
        slot = "TimeSlot.MS1"
    elif "11:30" in clean:
        slot = "TimeSlot.MS2"
    elif "2:00" in clean or "200" in clean or clean.startswith("2"):
        slot = "TimeSlot.MS3"
    elif "4:00" in clean or "400" in clean or clean.startswith("4"):
        slot = "TimeSlot.MS4"
    else:
        slot = "TimeSlot.MS1"
    return {"date": f"{year}-{month:02d}-{day:02d}T00:00:00.000Z", "timeSlot": slot}


def parse_endsem_exam(exam_str):
    if not exam_str:
        return None
    s = str(exam_str).strip()
    if not s:
        return None
    parts = s.split()
    if len(parts) < 2:
        return None
    dc = parts[0].split("/")
    if len(dc) != 2:
        return None
    try:
        day, month = int(dc[0]), int(dc[1])
    except ValueError:
        return None
    year = EXAM_YEAR
    slot_str = parts[1].strip()
    if slot_str == "FN":
        slot = "TimeSlot.FN"
    elif slot_str == "AN":
        slot = "TimeSlot.AN"
    else:
        return None
    return {"date": f"{year}-{month:02d}-{day:02d}T00:00:00.000Z", "timeSlot": slot}


def parse_section(data, start_row):
    row = data[start_row]
    section_id = get_cell_str(row, 6)
    if not section_id:
        return None

    section_type = parse_section_type(section_id)
    instructors = []
    rooms = []
    schedule = []
    current_row = start_row

    while current_row < len(data):
        r = data[current_row]
        if current_row > start_row:
            next_sec = get_cell_str(r, 6)
            next_comp = get_cell_str(r, 0)
            if next_sec or next_comp:
                break

        instr = get_cell_str(r, 7)
        if instr and instr not in instructors:
            instructors.append(instr)

        room = get_cell_str(r, 8)
        if room and room not in rooms:
            rooms.append(room)

        days_s = get_cell_str(r, 9)
        hours_s = get_cell_str(r, 10)
        if days_s and hours_s:
            dl = parse_days(days_s)
            hl = parse_hours(hours_s)
            if dl and hl:
                schedule.append({"days": dl, "hours": hl})

        current_row += 1

    return {
        "section": {
            "sectionId": section_id,
            "type": section_type,
            "instructor": ", ".join(instructors),
            "room": ", ".join(rooms),
            "schedule": schedule,
        },
        "nextRow": current_row,
    }


def parse_course_group(data, start_row, inherited_comp=None):
    main_row = data[start_row]
    comp_code = get_cell_str(main_row, 0) or inherited_comp
    course_no = get_cell_str(main_row, 1)
    course_title = get_cell_str(main_row, 2) or "Unknown"
    lec_credits = get_numeric(main_row, 3)
    prac_credits = get_numeric(main_row, 4)
    total_credits = get_numeric(main_row, 5)

    if not comp_code or not course_no or course_no == "TBA":
        return None

    sections = []
    current_row = start_row

    while current_row < len(data):
        if current_row == start_row:
            result = parse_section(data, start_row)
            if result:
                sections.append(result["section"])
                current_row = result["nextRow"]
            else:
                current_row += 1
        else:
            r = data[current_row]
            next_comp = get_cell_str(r, 0)
            next_course = get_cell_str(r, 1)
            if next_comp:
                break
            if next_course and next_course != str(course_no):
                break
            sec_id = get_cell_str(r, 6)
            if sec_id:
                result = parse_section(data, current_row)
                if result:
                    sections.append(result["section"])
                    current_row = result["nextRow"]
                else:
                    current_row += 1
            else:
                current_row += 1

    mid = parse_midsem_exam(get_cell(main_row, 11) if len(main_row) > 11 else None)
    end = parse_endsem_exam(get_cell(main_row, 12) if len(main_row) > 12 else None)

    return {
        "course": {
            "courseCode": str(course_no),
            "courseTitle": str(course_title),
            "lectureCredits": lec_credits,
            "practicalCredits": prac_credits,
            "totalCredits": total_credits,
            "sections": sections,
            "midSemExam": mid,
            "endSemExam": end,
        },
        "nextRow": current_row,
    }


def parse_timetable_rows_hyd(data):
    courses = []
    if not data:
        return courses
    current_row = 0
    last_comp = None

    while current_row < len(data):
        row = data[current_row]
        if is_empty_row(row):
            current_row += 1
            continue
        comp = get_cell_str(row, 0)
        course_no = get_cell_str(row, 1)
        if comp:
            last_comp = comp
        if comp or course_no:
            result = parse_course_group(data, current_row, last_comp)
            if result:
                courses.append(result["course"])
                current_row = result["nextRow"]
            else:
                current_row += 1
        else:
            current_row += 1
    return courses


# ─── Pilani parser (ported from upload-timetable-pilani.js) ───

PILANI_EXAM_SESSIONS = {
    "FN1": "TimeSlot.MS1", "FN2": "TimeSlot.MS2",
    "AN1": "TimeSlot.MS3", "AN2": "TimeSlot.MS4",
}

DAY_MAP_EXTENDED = {
    **DAY_MAP,
    "TH": "DayOfWeek.Th",
}


def is_day_of_week(s):
    return s in DAY_MAP_EXTENDED


def parse_merged_schedule(schedule_str):
    if not schedule_str:
        return []
    parts = schedule_str.strip().split()
    schedule = []
    current_days = []
    i = 0
    while i < len(parts):
        part = parts[i]
        if is_day_of_week(part):
            current_days.append(DAY_MAP_EXTENDED[part])
            i += 1
        elif part.isdigit():
            h = int(part)
            if 1 <= h <= 12 and current_days:
                hours = [h]
                j = i + 1
                while j < len(parts) and parts[j].isdigit():
                    nh = int(parts[j])
                    if 1 <= nh <= 12:
                        hours.append(nh)
                        j += 1
                    else:
                        break
                schedule.append({"days": list(current_days), "hours": hours})
                current_days = []
                i = j
            else:
                i += 1
        else:
            i += 1
    return schedule


def parse_pilani_exam(exam_str, is_midsem):
    if not exam_str:
        return None
    s = str(exam_str).strip()
    if not s:
        return None
    date_pattern = re.compile(r"(\d{1,2})[/\-](\d{1,2})(?:[/\-](\d{4}))?")
    exam_date = None
    session = None
    for part in s.split():
        dm = date_pattern.match(part)
        if dm:
            day, month = int(dm.group(1)), int(dm.group(2))
            year = int(dm.group(3)) if dm.group(3) else EXAM_YEAR
            exam_date = f"{year}-{month:02d}-{day:02d}T00:00:00.000Z"
        elif part in PILANI_EXAM_SESSIONS or part in ("FN", "AN"):
            session = part
    if not exam_date:
        return None
    if is_midsem:
        slot = PILANI_EXAM_SESSIONS.get(session, "TimeSlot.MS1")
    else:
        if session == "AN":
            slot = "TimeSlot.AN"
        else:
            slot = "TimeSlot.FN"
    return {"date": exam_date, "timeSlot": slot}


def parse_pilani_section(data, start_row):
    row = data[start_row]
    section_id = get_cell_str(row, 6)
    if not section_id:
        return None
    section_type = parse_section_type(section_id)
    instructors = []
    rooms = []
    schedule = []
    current_row = start_row

    while current_row < len(data):
        r = data[current_row]
        if current_row > start_row:
            next_sec = get_cell_str(r, 6)
            next_comp = get_cell_str(r, 0)
            if next_sec or next_comp:
                break
        instr = get_cell_str(r, 7)
        if instr and instr not in instructors:
            instructors.append(instr)
        room = get_cell_str(r, 8)
        if room and room not in rooms:
            rooms.append(room)
        merged = get_cell_str(r, 9)
        if merged:
            schedule.extend(parse_merged_schedule(merged))
        current_row += 1

    return {
        "section": {
            "sectionId": section_id,
            "type": section_type,
            "instructor": ", ".join(instructors),
            "room": ", ".join(rooms),
            "schedule": schedule,
        },
        "nextRow": current_row,
    }


def parse_pilani_course_group(data, start_row):
    main_row = data[start_row]
    comp_code = get_cell_str(main_row, 0)
    course_no = get_cell_str(main_row, 1)
    course_title = get_cell_str(main_row, 2)
    lec_credits = get_numeric(main_row, 3)
    prac_credits = get_numeric(main_row, 4)
    total_credits = get_numeric(main_row, 5)

    if not comp_code or not course_no or not course_title:
        return None

    sections = []
    current_row = start_row

    while current_row < len(data):
        if current_row == start_row:
            result = parse_pilani_section(data, start_row)
            if result:
                sections.append(result["section"])
                current_row = result["nextRow"]
            else:
                current_row += 1
        else:
            r = data[current_row]
            next_comp = get_cell_str(r, 0)
            if next_comp:
                break
            sec_id = get_cell_str(r, 6)
            if sec_id:
                result = parse_pilani_section(data, current_row)
                if result:
                    sections.append(result["section"])
                    current_row = result["nextRow"]
                else:
                    current_row += 1
            else:
                current_row += 1

    if not sections:
        return None

    mid = parse_pilani_exam(get_cell(main_row, 10) if len(main_row) > 10 else None, True)
    end = parse_pilani_exam(get_cell(main_row, 11) if len(main_row) > 11 else None, False)

    return {
        "course": {
            "courseCode": str(course_no),
            "courseTitle": str(course_title),
            "lectureCredits": lec_credits,
            "practicalCredits": prac_credits,
            "totalCredits": total_credits,
            "sections": sections,
            "midSemExam": mid,
            "endSemExam": end,
        },
        "nextRow": current_row,
    }


def parse_timetable_rows_pilani(data):
    courses = []
    if not data:
        return courses
    current_row = 0

    while current_row < len(data):
        row = data[current_row]
        if is_empty_row(row):
            current_row += 1
            continue
        comp = get_cell_str(row, 0)
        if not comp:
            current_row += 1
            continue
        result = parse_pilani_course_group(data, current_row)
        if result:
            courses.append(result["course"])
            current_row = result["nextRow"]
        else:
            current_row += 1
    return courses


# ─── Goa parser (ported from upload-timetable-goa.js) ───


def _safe_int(s):
    try:
        return int(float(s))
    except (ValueError, TypeError):
        return 0


def parse_lpu(lpu_str):
    parts = lpu_str.strip().split()
    if len(parts) >= 3:
        return {"L": _safe_int(parts[0]), "P": _safe_int(parts[1]), "U": _safe_int(parts[2])}
    if len(parts) == 1:
        return {"L": 0, "P": 0, "U": _safe_int(parts[0])}
    return {"L": 0, "P": 0, "U": 0}


def parse_goa_section_type(stat):
    s = stat.upper()
    if s == "L": return "SectionType.L"
    if s == "P": return "SectionType.P"
    if s == "T": return "SectionType.T"
    if s == "R": return "SectionType.L"
    if s == "I": return "SectionType.L"
    return "SectionType.L"


def parse_goa_days_hours(days_hr_str):
    if not days_hr_str or not days_hr_str.strip():
        return []
    parts = days_hr_str.strip().split()
    entries = []
    current_days = []
    pending_hour = None

    for part in parts:
        if is_day_of_week(part):
            if pending_hour is not None and current_days:
                entries.append({"days": list(current_days), "hours": [pending_hour]})
                current_days = []
            current_days.append(DAY_MAP_EXTENDED[part])
        elif "-" in part:
            hr = part.split("-")
            if len(hr) == 2:
                try:
                    start_h, end_h = int(hr[0]), int(hr[1])
                    range_hours = [h for h in range(start_h, end_h + 1) if 1 <= h <= 12]
                    if current_days and range_hours:
                        entries.append({"days": list(current_days), "hours": range_hours})
                        current_days = []
                except ValueError:
                    pass
            pending_hour = None
        else:
            try:
                hour = int(part)
                if 1 <= hour <= 12:
                    if current_days:
                        entries.append({"days": list(current_days), "hours": [hour]})
                        current_days = []
                    pending_hour = hour
            except ValueError:
                pass

    if pending_hour is not None and current_days:
        entries.append({"days": list(current_days), "hours": [pending_hour]})
    return entries


def _parse_goa_time_slot(ts):
    try:
        time_num = int(ts)
        slot_map = {1: "TimeSlot.MS1", 2: "TimeSlot.MS2", 3: "TimeSlot.MS3", 4: "TimeSlot.MS4"}
        return slot_map.get(time_num, "TimeSlot.MS1")
    except (ValueError, TypeError):
        pass
    clean = ts.replace(".", ":").replace(" ", "").replace("\n", "")
    if "9:30" in clean:
        return "TimeSlot.MS1"
    if "11:30" in clean:
        return "TimeSlot.MS2"
    if "2:00" in clean or "200" in clean or clean.startswith("2"):
        return "TimeSlot.MS3"
    if "4:00" in clean or "400" in clean or clean.startswith("4"):
        return "TimeSlot.MS4"
    return "TimeSlot.MS1"


def parse_goa_midsem(date_str, time_str):
    if not date_str or not time_str:
        return None
    ds = str(date_str).strip()
    ts = str(time_str).strip()
    if ds.upper() == "TBA" or ts in ("0", ""):
        return None
    try:
        date_part = ds.split(",")[0].strip()
        dp = date_part.split("/")
        if len(dp) != 3:
            return None
        day, month, year = int(dp[0]), int(dp[1]), int(dp[2])
        if year < 100:
            year += 2000
        slot = _parse_goa_time_slot(ts)
        return {"date": f"{year}-{month:02d}-{day:02d}T00:00:00.000Z", "timeSlot": slot}
    except (ValueError, IndexError):
        return None


def parse_goa_compre(compre_str):
    if not compre_str:
        return None
    s = str(compre_str).strip()
    if not s:
        return None
    m = re.match(r"(\d{1,2}/\d{1,2}/\d{1,2})\s*\(([FA]N)\)", s)
    if not m:
        return None
    try:
        dp = m.group(1).split("/")
        day, month, year = int(dp[0]), int(dp[1]), int(dp[2])
        if year < 100:
            year += 2000
        slot = "TimeSlot.FN" if m.group(2) == "FN" else "TimeSlot.AN"
        return {"date": f"{year}-{month:02d}-{day:02d}T00:00:00.000Z", "timeSlot": slot}
    except (ValueError, IndexError):
        return None


def parse_goa_course_group(data, start_row):
    main_row = data[start_row]
    course_no = get_cell_str(main_row, 1)
    course_title = get_cell_str(main_row, 2)
    lpu_str = get_cell_str(main_row, 3)

    if not course_no or not course_title or course_no == "#N/A" or course_title == "#N/A":
        return None

    lpu = parse_lpu(lpu_str)
    mid = parse_goa_midsem(
        get_cell(main_row, 10) if len(main_row) > 10 else None,
        get_cell(main_row, 11) if len(main_row) > 11 else None,
    )
    end = parse_goa_compre(get_cell(main_row, 9) if len(main_row) > 9 else None)

    sections = []
    current_row = start_row

    while current_row < len(data):
        r = data[current_row]
        next_cn = get_cell_str(r, 1)
        if current_row > start_row and next_cn and next_cn != str(course_no):
            break

        stat = get_cell_str(r, 4)
        sec = get_cell_str(r, 5)
        if not stat or not sec:
            current_row += 1
            continue

        section_id = f"{stat.strip()}{sec.strip()}"
        section_type = parse_goa_section_type(stat.strip())
        instructor_str = get_cell_str(r, 6)
        days_hr = get_cell_str(r, 7)
        room = get_cell_str(r, 8)

        instructors = [n.strip() for n in re.split(r"[,/\n\r]+", instructor_str) if n.strip()] if instructor_str else []
        schedule = parse_goa_days_hours(days_hr)

        sections.append({
            "sectionId": section_id,
            "type": section_type,
            "instructor": ", ".join(instructors),
            "room": room,
            "schedule": schedule,
        })
        current_row += 1

    return {
        "course": {
            "courseCode": str(course_no),
            "courseTitle": str(course_title),
            "lectureCredits": lpu["L"],
            "practicalCredits": lpu["P"],
            "totalCredits": lpu["U"],
            "sections": sections,
            "midSemExam": mid,
            "endSemExam": end,
        },
        "nextRow": current_row,
    }


def parse_timetable_rows_goa(data):
    courses = []
    if not data:
        return courses
    current_row = 0

    while current_row < len(data):
        row = data[current_row]
        if is_empty_row(row):
            current_row += 1
            continue
        course_no = get_cell_str(row, 1)
        if course_no:
            result = parse_goa_course_group(data, current_row)
            if result:
                courses.append(result["course"])
                current_row = result["nextRow"]
            else:
                current_row += 1
        else:
            current_row += 1

    return [c for c in courses if c["courseCode"] and c["courseCode"] != "#N/A"]


# ─── Campus dispatch ───


def parse_timetable_rows(data, campus_code):
    if campus_code == "pilani":
        return parse_timetable_rows_pilani(data)
    if campus_code == "goa":
        return parse_timetable_rows_goa(data)
    return parse_timetable_rows_hyd(data)


# ─── Exam seating parser (ported from upload-exam-seating.js) ───


def parse_id_range(id_range):
    normalized = id_range.replace("\n", " ").strip()
    if re.search(r"all\s*(the)?\s*students", normalized, re.IGNORECASE):
        return {"from": None, "to": None, "allStudents": True}
    pattern = r"(\d{4}[A-Z0-9]{4}\d{4}[HGPD])"
    m = re.search(pattern + r"\s*[-–]\s*" + pattern, normalized)
    if m:
        return {"from": m.group(1), "to": m.group(2)}
    m = re.search(pattern + r"\s+to\s+" + pattern, normalized, re.IGNORECASE)
    if m:
        return {"from": m.group(1), "to": m.group(2)}
    return None


def parse_exam_seating_rows(data):
    if not data:
        return []

    exams = []
    current_exam = None

    for row in data:
        if is_empty_row(row):
            continue
        # Columns: course_code, course_title, exam_date, room_no, id_range, student_count
        course_code = get_cell_str(row, 0)
        course_title = get_cell_str(row, 1)
        exam_date = get_cell_str(row, 2)
        room_no = get_cell_str(row, 3)
        id_range = get_cell_str(row, 4)
        student_count_str = get_cell_str(row, 5)

        if not room_no or not id_range:
            continue

        parsed = parse_id_range(id_range)
        if not parsed:
            continue

        try:
            student_count = int(student_count_str) if student_count_str else None
        except ValueError:
            student_count = None

        if course_code:
            if current_exam and current_exam["rooms"]:
                exams.append(current_exam)
            current_exam = {
                "courseCode": course_code,
                "courseTitle": course_title,
                "examDate": exam_date,
                "rooms": [],
            }

        if current_exam:
            current_exam["rooms"].append({
                "roomNo": room_no,
                "idFrom": parsed.get("from"),
                "idTo": parsed.get("to"),
                "studentCount": student_count,
            })

    if current_exam and current_exam["rooms"]:
        exams.append(current_exam)

    return exams


# ─── Academic-calendar parser ───────────────────────────────────────────────
#
# The calendar lives on one page of the timetable booklet as a date→event list
# beside the little month grids. pdfplumber's extract_table() only grabs the
# grids, and reading-order text collides the two print columns and interleaves
# the grid digits, so this walks word coordinates instead: cluster the "Month
# DD" anchors into print columns by x, then read each anchor's row-band. A date
# always sits to the left of its own label, so everything between an anchor's
# date blob and the next anchor is that event. See the scoping notes for the
# per-campus quirks; residual noise is fixed in the admin review screen.

CAL_MONTHS = {m: i + 1 for i, m in enumerate([
    "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December"])}
CAL_MONTH_RE = "|".join(CAL_MONTHS)

# Leading month + day, optionally a (Dow), a comma/ampersand day list, or a
# range to another day (or Month day). Stops before the alphabetic label.
CAL_DATE_RE = re.compile(
    r'(?P<mon>' + CAL_MONTH_RE + r')\s+'
    r'(?P<body>\d{1,2}'
    r'(?:\s*\([^)]*\))?'
    r'(?:\s*[,&]\s*\d{1,2})*'
    r'(?:\s*[-–—]\s*(?:(?:' + CAL_MONTH_RE + r')\s+)?\d{1,2}(?:\s*\([^)]*\))?)?'
    r')'
)

# Month-grid leftovers that leak into a label: the day-name header row and long
# runs of bare 1–2 digit numbers (the calendars themselves).
CAL_GRID_HEADER_RE = re.compile(r'\b(?:Su\s+M\s+T\s+W\s+Th\s+F\s+S\b\s*)+', re.I)
CAL_GRID_NUMS_RE = re.compile(r'(?:\b\d{1,2}\b[ \t]*){4,}')
CAL_DOW_RE = re.compile(r'\((Su|Th|M|T|W|F|S)\)')


def _cal_clean(s):
    return re.sub(r'\s+', ' ', s).strip()


def _cal_strip_label(s):
    s = CAL_GRID_HEADER_RE.sub(' ', s)
    s = CAL_GRID_NUMS_RE.sub(' ', s)
    # Trailing booklet footnotes / section headers that trail the last event.
    s = re.split(r'\*Holiday subject|\bNote:|HOLIDAYS\s+RECESS', s)[0]
    s = _cal_clean(s)
    # An orphan "(Dow)" left when a date range wrapped to the next print line.
    s = re.sub(r'^\([^)]*\)\s*', '', s)
    return _cal_clean(s)


def _cal_category(label):
    low = label.lower()
    if "(h)" in low:
        return "holiday"
    if "exam" in low:
        return "exam"
    if any(k in low for k in (
            "last day", "last date", "registration", "withdrawal",
            "substitution")):
        return "deadline"
    if any(k in low for k in (
            "classwork", "class work", "semester ends", "semester begins",
            "grading", "vacation", "summer term")):
        return "milestone"
    return "event"


def _cal_parse_body(mon, body):
    """Turns a date blob ('09 (M)-March 14 (S)') into its month/day components.

    Years are assigned later (see [_assign_years]) because that depends on which
    semester the page belongs to, not on the blob alone.
    """
    start_month = CAL_MONTHS[mon]
    end_month = start_month
    m2 = re.search(r'(' + CAL_MONTH_RE + r')', body)
    if m2:
        end_month = CAL_MONTHS[m2.group(1)]
    days = [int(x) for x in re.findall(r'\d{1,2}', body)]
    if not days:
        return None
    dow_m = CAL_DOW_RE.search(body)
    return {
        "start_month": start_month,
        "start_day": days[0],
        "end_month": end_month if len(days) > 1 else None,
        "end_day": days[-1] if len(days) > 1 else None,
        "dayOfWeek": dow_m.group(1) if dow_m else None,
    }


def _cal_parse_page(page):
    words = page.extract_words(use_text_flow=False, keep_blank_chars=False)
    anchors = []
    for i, w in enumerate(words):
        if w["text"] in CAL_MONTHS:
            nxt = words[i + 1]["text"] if i + 1 < len(words) else ""
            if re.match(r'^\d', nxt):
                anchors.append(w)
    if not anchors:
        return []
    # Column starts from clustered anchor x-positions; a word belongs to the
    # nearest start at or to its left.
    xs = sorted(a["x0"] for a in anchors)
    starts = [xs[0]]
    for a, b in zip(xs, xs[1:]):
        if b - a > 60:
            starts.append(b)

    def col(x):
        c = 0
        for i, st in enumerate(starts):
            if x >= st - 2:
                c = i
        return c

    from collections import defaultdict
    per_col = defaultdict(list)
    for a in anchors:
        per_col[col(a["x0"])].append(a)

    events = []
    for c, alist in per_col.items():
        alist.sort(key=lambda w: w["top"])
        cwords = [w for w in words if col(w["x0"]) == c]
        for j, a in enumerate(alist):
            top0 = a["top"] - 3
            top1 = alist[j + 1]["top"] - 3 if j + 1 < len(alist) else 1e9
            seg = [w for w in cwords if top0 <= w["top"] < top1]
            seg.sort(key=lambda w: (round(w["top"] / 6), w["x0"]))
            text = _cal_clean(" ".join(w["text"] for w in seg))
            m = CAL_DATE_RE.match(text)
            if not m:
                continue
            parsed = _cal_parse_body(m.group("mon"), _cal_clean(m.group("body")))
            if not parsed:
                continue
            label = _cal_strip_label(text[m.end():])
            if not label:
                continue
            events.append({
                "_col": c, "_top": a["top"],
                **parsed,
                "label": label,
                "category": _cal_category(label),
            })
    events.sort(key=lambda e: (e["_col"], e["_top"]))
    return events


def _detect_semester(text):
    """Which semester the calendar page describes, from its heading.

    Booklets label the list "Second Semester …" / "Semester II" or "First
    Semester …" / "Semester 1". Checked second-first so "Semester II" can't be
    mistaken for "Semester I". Defaults to 2 when unlabelled.
    """
    low = text.lower()
    if re.search(r'second semester|semester\s*ii\b|semester\s*2\b', low):
        return 2
    if re.search(r'first semester|semester\s*i\b|semester\s*1\b', low):
        return 1
    return 2


def _iso(year, month, day):
    return "{:04d}-{:02d}-{:02d}".format(year, month, day)


def _assign_years(e, exam_year, semester):
    """Attach a calendar year to a parsed row and decide if it belongs to this
    semester. Inclusion + year both key off the *start* month:

    - Semester 2 runs Jan–Jul of exam_year. A page that also prints the prior
      first semester puts those in Aug–Dec — dropped here.
    - Semester 1 runs Jul/Aug–Dec of exam_year; a Dec→Jan range (the recess)
      wraps its end into exam_year + 1.

    Returns the finished event dict, or None if the row is the other semester.
    """
    sm, sd = e["start_month"], e["start_day"]
    em, ed = e["end_month"], e["end_day"]

    if semester == 2:
        if not (1 <= sm <= 7):
            return None
        start_year = exam_year
    else:
        if not (7 <= sm <= 12):
            return None
        start_year = exam_year

    date = _iso(start_year, sm, sd)
    end = None
    if em is not None and ed is not None:
        # A range whose end month is earlier than its start wrapped into the
        # next calendar year (a December→January recess).
        end_year = start_year + 1 if em < sm else start_year
        end = _iso(end_year, em, ed)
        if end == date:
            end = None
    return {
        "date": date,
        "endDate": end,
        "dayOfWeek": e["dayOfWeek"],
        "label": e["label"],
        "category": e["category"],
    }


def parse_academic_calendar(pdf_path, page_range, exam_year, semester=None):
    import pdfplumber

    pdf = pdfplumber.open(pdf_path)
    pages = pdf.pages
    if page_range and len(page_range) == 2:
        pages = pages[page_range[0] - 1 : page_range[1]]

    raw = []
    page_text = []
    for page in pages:
        raw.extend(_cal_parse_page(page))
        page_text.append(page.extract_text() or "")
    pdf.close()

    if semester is None:
        semester = _detect_semester("\n".join(page_text))

    events = []
    seen = set()
    for e in raw:
        finished = _assign_years(e, exam_year, semester)
        if finished is None:
            continue
        key = (finished["date"], finished["label"])
        if key in seen:
            continue
        seen.add(key)
        events.append(finished)
    events.sort(key=lambda e: e["date"])
    return events


def upload_calendar_to_firestore(events, campus_code, exam_year):
    campus_id = CAMPUS_IDS.get(campus_code.lower(), "hyderabad")
    db = get_db()
    from datetime import datetime
    db.collection("campuses").document(campus_id).collection(
        "academicCalendar").document("current").set({
            "events": events,
            "examYear": exam_year,
            "updatedAt": datetime.utcnow().isoformat() + "Z",
        })


# ─── Firestore batch upload (ported from base-parser.js) ───


def upload_courses_to_firestore(courses, campus_code, clear_first=True):
    campus_id = CAMPUS_IDS.get(campus_code.lower(), "hyderabad")
    db = get_db()
    timetable_ref = db.collection(f"campuses/{campus_id}/timetable")

    if clear_first:
        docs = timetable_ref.get()
        batch = db.batch()
        count = 0
        for doc in docs:
            batch.delete(doc.reference)
            count += 1
            if count >= BATCH_SIZE:
                batch.commit()
                batch = db.batch()
                count = 0
        if count > 0:
            batch.commit()

    for i in range(0, len(courses), BATCH_SIZE):
        batch = db.batch()
        sl = courses[i : i + BATCH_SIZE]
        for course in sl:
            doc_id = course_code_to_doc_id(course["courseCode"])

            sections = []
            for s in course.get("sections", []):
                sections.append({
                    **s,
                    "instructor": sanitize(s.get("instructor", "")),
                    "room": sanitize(s.get("room", "")),
                })

            lec = course.get("lectureCredits", 0)
            prac = course.get("practicalCredits", 0)
            batch.set(timetable_ref.document(doc_id), {
                "sections": sections,
                "mid_sem_exam": course.get("midSemExam"),
                "end_sem_exam": course.get("endSemExam"),
                "lecture_credits": lec,
                "practical_credits": prac,
                # The unit count (U column). Persisted because it is NOT always
                # L + P — projects/theses/labs are e.g. "- - 3" — and the client
                # would otherwise recompute it as L + P and report 0.
                "total_credits": course.get("totalCredits", lec + prac),
            })
        batch.commit()

    sync_courses_master(courses, campus_id)


# courses_master is the only source of course titles in the app: timetable
# documents store no title, and the client resolves every one of them through
# CoursesMasterService. It holds far more courses than any single semester
# offers (~2,800 vs ~420), and its entries are curated — so this only ever
# INSERTS codes that are absent, and never edits or deletes an existing row.
MASTER_BUNDLE_MAX_BYTES = 900 * 1024  # Firestore caps a document at 1 MiB.


def sync_courses_master(courses, campus_id):
    """Adds any newly-offered course to courses_master and refreshes the bundle.

    Without this a course that appears in the timetable PDF but not in
    courses_master renders as its bare code (e.g. "MATH U101") everywhere in the
    app, because the title parsed here would otherwise be discarded.
    """
    db = get_db()
    master_ref = db.collection(f"campuses/{campus_id}/courses_master")

    existing = {}
    for doc in master_ref.get():
        data = doc.to_dict() or {}
        existing[doc.id] = {
            "course_code": data.get("course_code") or doc.id.replace("_", " "),
            "title": data.get("title", ""),
            "credits": data.get("credits", 0),
            "type": data.get("type", "Normal"),
        }

    now_iso = datetime.utcnow().isoformat() + "Z"
    added = []
    for course in courses:
        code = course.get("courseCode", "")
        doc_id = course_code_to_doc_id(code)
        if not doc_id or doc_id in existing:
            continue

        title = sanitize(str(course.get("courseTitle", "")).strip())
        # A code with no usable title is worse than no row at all: it would
        # mask the gap while still displaying the bare code.
        if not title or title.upper() in ("UNKNOWN", "#N/A", code.upper()):
            print(f"[courses_master] skipping {code}: no usable title")
            continue

        entry = {
            # Derived from the doc id, not the raw code: the client looks titles
            # up by the timetable doc id with underscores turned back into
            # spaces, and course_code_to_doc_id drops any "/ALIAS" suffix. Using
            # the raw code here would store a key nothing ever queries.
            "course_code": doc_id.replace("_", " "),
            "title": title,
            # The unit count (U), not L + P — see upload_courses_to_firestore.
            "credits": course.get(
                "totalCredits",
                course.get("lectureCredits", 0) + course.get("practicalCredits", 0)),
            # The PDF carries no course type; curated rows (e.g. ATC) keep
            # theirs because existing documents are never touched.
            "type": "Normal",
        }
        existing[doc_id] = entry
        added.append((doc_id, entry))

    if added:
        for i in range(0, len(added), BATCH_SIZE):
            batch = db.batch()
            for doc_id, entry in added[i : i + BATCH_SIZE]:
                batch.set(master_ref.document(doc_id), {**entry, "updated_at": now_iso})
            batch.commit()
        print(f"[courses_master] added {len(added)}: {', '.join(c for c, _ in added)}")
    else:
        print("[courses_master] no new courses")

    _write_catalog_bundle(db, campus_id, existing, force=bool(added))


def _write_catalog_bundle(db, campus_id, entries_by_id, force):
    """Rewrites the single-document catalogue bundle clients read on cold load.

    The client reads this bundle first and only falls back to scanning the
    collection when it is missing or unparseable, so a collection write that
    skips this step stays invisible.
    """
    entries = sorted(
        (
            {
                "course_code": e["course_code"],
                "title": e.get("title", ""),
                "credits": e.get("credits", 0) or 0,
                "type": e.get("type") or "Normal",
            }
            for e in entries_by_id.values()
        ),
        key=lambda e: e["course_code"],
    )
    if not entries:
        print("[courses_master] refusing to write an empty bundle")
        return

    entries_json = json.dumps(entries, separators=(",", ":"))
    size = len(entries_json.encode("utf-8"))
    if size > MASTER_BUNDLE_MAX_BYTES:
        print(f"[courses_master] bundle too large ({size} bytes) — leaving previous bundle in place")
        return

    bundle_ref = db.document(f"campuses/{campus_id}/catalog/courses_master")
    if not force:
        snap = bundle_ref.get()
        # Rewriting an identical bundle would bump metadata and force every
        # client to refetch the catalogue for no reason.
        if snap.exists and (snap.to_dict() or {}).get("entriesJson") == entries_json:
            print("[courses_master] bundle unchanged")
            return

    stamp = datetime.utcnow()
    bundle_ref.set({
        "version": stamp.isoformat() + "Z",
        "count": len(entries),
        "entriesJson": entries_json,
    })
    # Clients only re-read the bundle when campus metadata says it is newer.
    db.document(f"campuses/{campus_id}/metadata/current").set(
        {"lastUpdated": stamp.isoformat() + "Z", "version": str(int(stamp.timestamp() * 1000))},
        merge=True,
    )
    print(f"[courses_master] bundle written: {len(entries)} entries, {size / 1024:.1f} KB")


# ─── Cloud Functions ───


@https_fn.on_call(region="asia-south1", enforce_app_check=False, timeout_sec=540, memory=options.MemoryOption.GB_1)
def upload_timetable(req: https_fn.CallableRequest):
    require_admin(req)
    db = get_db()
    bucket = get_bucket()

    global EXAM_YEAR
    campus_code = req.data.get("campusCode")
    storage_path = req.data.get("storagePath")
    extra_headers = req.data.get("excludeHeaders", [])
    exclude_headers = DEFAULT_TIMETABLE_HEADERS.get(campus_code, []) + extra_headers
    page_range_raw = req.data.get("pageRange")
    calendar_range_raw = req.data.get("calendarPageRange")
    EXAM_YEAR = req.data.get("examYear", 2026)

    if not campus_code or not storage_path:
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.INVALID_ARGUMENT, "Missing fields")
    if campus_code not in ("hyderabad", "pilani", "goa"):
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.INVALID_ARGUMENT, "Invalid campus")

    def _as_range(raw):
        if raw and isinstance(raw, list) and len(raw) == 2:
            return [int(raw[0]), int(raw[1])]
        return None

    page_range = _as_range(page_range_raw)
    calendar_range = _as_range(calendar_range_raw)
    # Optional explicit semester (1 or 2); otherwise the parser reads it off the
    # page heading.
    calendar_semester = req.data.get("calendarSemester")
    if calendar_semester not in (1, 2):
        calendar_semester = None

    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp_path = tmp.name
        blob = bucket.blob(storage_path)
        blob.download_to_filename(tmp_path)

    try:
        exact_headers = PILANI_EXTRA_HEADERS if campus_code == "pilani" else None
        rows = extract_pdf_tables(tmp_path, exclude_headers, page_range, exact_headers)
        courses = parse_timetable_rows(rows, campus_code)
        # The academic calendar rides along on the same PDF: only parse it when
        # the admin supplies its page range, otherwise leave the stored one be.
        calendar_events = None
        if calendar_range:
            calendar_events = parse_academic_calendar(
                tmp_path, calendar_range, EXAM_YEAR, semester=calendar_semester)
    finally:
        os.unlink(tmp_path)

    if not courses:
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.INVALID_ARGUMENT, "No courses found in PDF")

    upload_courses_to_firestore(courses, campus_code, clear_first=True)

    calendar_uploaded = 0
    if calendar_events:
        upload_calendar_to_firestore(calendar_events, campus_code, EXAM_YEAR)
        calendar_uploaded = len(calendar_events)

    campus_id = CAMPUS_IDS.get(campus_code.lower(), "hyderabad")

    # upload_courses_to_firestore(clear_first=True) replaced the collection with
    # exactly `courses`, so that's the total. Re-reading the whole collection
    # just to count it doubled the read cost of every upload.
    from datetime import datetime
    db.collection("campuses").document(campus_id).collection("metadata").document("current").set({
        "lastUpdated": datetime.utcnow().isoformat() + "Z",
        "totalCourses": len(courses),
        "uploadedAt": datetime.utcnow().isoformat() + "Z",
        "version": str(int(datetime.utcnow().timestamp() * 1000)),
        "campus": CAMPUS_NAMES.get(campus_code.lower(), "Hyderabad"),
        "campusCode": campus_code,
    }, merge=True)

    return {
        "success": True,
        "coursesUploaded": len(courses),
        "calendarEventsUploaded": calendar_uploaded,
    }


@https_fn.on_call(region="asia-south1", enforce_app_check=False, timeout_sec=300, memory=options.MemoryOption.MB_512)
def upload_exam_seating(req: https_fn.CallableRequest):
    require_admin(req)
    db = get_db()
    bucket = get_bucket()

    campus_code = req.data.get("campusCode")
    storage_path = req.data.get("storagePath")
    extra_headers = req.data.get("excludeHeaders", [])
    exclude_headers = DEFAULT_EXAM_HEADERS + extra_headers

    if not campus_code or not storage_path:
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.INVALID_ARGUMENT, "Missing fields")
    if campus_code not in ("hyderabad", "pilani", "goa"):
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.INVALID_ARGUMENT, "Invalid campus")

    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp_path = tmp.name
        blob = bucket.blob(storage_path)
        blob.download_to_filename(tmp_path)

    try:
        rows = extract_pdf_tables(tmp_path, exclude_headers)
        exams = parse_exam_seating_rows(rows)
    finally:
        os.unlink(tmp_path)

    if not exams:
        raise https_fn.HttpsError(https_fn.FunctionalErrorCode.INVALID_ARGUMENT, "No exam data found in PDF")

    campus_id = CAMPUS_IDS.get(campus_code.lower(), "hyderabad")
    collection_path = f"campuses/{campus_id}/exam_seating"

    # Clear existing
    existing = db.collection(collection_path).get()
    batch = db.batch()
    count = 0
    for doc in existing:
        batch.delete(doc.reference)
        count += 1
        if count >= BATCH_SIZE:
            batch.commit()
            batch = db.batch()
            count = 0
    if count > 0:
        batch.commit()

    # Upload
    batch = db.batch()
    op_count = 0
    for exam in exams:
        doc_id = re.sub(r"\s+", "_", exam["courseCode"]).replace("/", "-")
        doc_ref = db.collection(collection_path).document(doc_id)

        exam_date_val = sanitize(exam.get("examDate", ""))

        batch.set(doc_ref, {
            "exam_date": exam_date_val,
            "rooms": exam["rooms"],
            "updated_at": firestore.SERVER_TIMESTAMP,
        })
        op_count += 1
        if op_count >= BATCH_SIZE:
            batch.commit()
            batch = db.batch()
            op_count = 0
    if op_count > 0:
        batch.commit()

    from datetime import datetime
    db.document("admin_metadata/exam_seating").set({
        "lastUpdated": datetime.utcnow().isoformat() + "Z",
        "totalCourses": len(exams),
        "campus": CAMPUS_NAMES.get(campus_code.lower(), "Hyderabad"),
    }, merge=True)

    return {"success": True, "examsUploaded": len(exams)}

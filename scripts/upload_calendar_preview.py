"""One-off: writes the parsed academic-calendar preview to Firestore.

Reads .cal_preview.json (produced from the Sem-1 2026-27 PDF) and PATCHes it to
campuses/hyderabad/academicCalendar/current using the caller's gcloud identity.
Run from the repo root:

    functions-python/venv/bin/python scripts/upload_calendar_preview.py
"""
import datetime
import json
import subprocess

import requests

PROJECT = "timetable-maker-3c8e0"
CAMPUS = "hyderabad"


def val(v):
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    raise TypeError(v)


def ev_map(e):
    # Drop null-valued optional fields (endDate/dayOfWeek) — the client model
    # reads their absence the same as null.
    return {"mapValue": {"fields": {k: val(v) for k, v in e.items() if v is not None}}}


def main():
    events = json.load(open(".cal_preview.json"))["events"]
    body = {"fields": {
        "events": {"arrayValue": {"values": [ev_map(e) for e in events]}},
        "examYear": {"integerValue": "2026"},
        "updatedAt": {"stringValue": datetime.datetime.utcnow().isoformat() + "Z"},
    }}
    token = subprocess.check_output(
        ["gcloud", "auth", "print-access-token"]).decode().strip()
    url = (f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/"
           f"(default)/documents/campuses/{CAMPUS}/academicCalendar/current")
    r = requests.patch(url, headers={"Authorization": f"Bearer {token}"}, json=body)
    print("HTTP", r.status_code)
    if r.status_code == 200:
        print(f"Wrote {len(events)} events to "
              f"campuses/{CAMPUS}/academicCalendar/current")
    else:
        print(r.text[:600])


if __name__ == "__main__":
    main()

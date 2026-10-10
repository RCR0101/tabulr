#!/usr/bin/env python3
"""Build profs.json from the public BITS faculty directory.

    python3 functions-python/faculty.py hyderabad > profs.json

Upload the result in Admin → Professor Schedules → profs.json → Rebuild. The
directory gives name, department, designation, email and phone, but **not
chambers**. The rebuild keeps every chamber already on file, so this only
refreshes who teaches here and how to reach them. Chambers are still edited
in Admin → Professor Chambers.

The listing is filled by `admin-ajax.php?action=fetch_faculties`, keyed by
numeric campus ids (the `<option value>` on /faculty/), not slugs: a slug
returns "No data". Stdlib only. Read-only: it writes nothing anywhere.
"""

import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request

AJAX = "https://www.bits-pilani.ac.in/wp-admin/admin-ajax.php"
CAMPUS_IDS = {"pilani": 96, "goa": 97, "hyderabad": 98, "dubai": 100}
UA = {"User-Agent": "Mozilla/5.0 (Tabulr faculty roster; +https://tabulr.net)"}

CARD_RE = re.compile(
    r'<span class="yellow-tag"><a[^>]*>(?P<dept>[^<]*)</a>.*?'
    r'<p class="facul-title"><a href="(?P<url>[^"]+)">(?P<name>[^<]+)</a></p>\s*'
    r'<p class="facul-desp">(?P<desig>[^<]*)</p>', re.S)
EMAIL_RE = re.compile(r"[\w.+-]+@(?:hyderabad|pilani|goa|dubai)\.bits-pilani\.ac\.in")
PHONE_RE = re.compile(r">\s*(\+?\d[\d\s-]{7,}\d)\s*<")


def _fetch(url, data=None):
    body = urllib.parse.urlencode(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def _clean(s):
    return re.sub(r"\s+", " ", html.unescape(s)).strip()


def _clean_name(raw):
    # Some profiles append the name in Devanagari ("Parikshit Sahatiya डॉ. …").
    name = re.sub(r"[^\x00-\x7F].*$", "", _clean(raw)).strip()
    return re.sub(r"^(?:(?:dr|prof|mr|mrs|ms)\.?\s+)+", "", name, flags=re.I)


def parse_cards(page):
    return [{
        # Honorifics would stop the rebuild matching the timetable's names.
        "name": _clean_name(m["name"]),
        "department": _clean(m["dept"]),
        # "Professor\nDept. of …": the second line repeats the department.
        "designation": _clean(m["desig"].strip().split("\n")[0]).rstrip(","),
        "profileUrl": m["url"],
    } for m in CARD_RE.finditer(page)]


def parse_profile(page):
    email = EMAIL_RE.search(page)
    phone = PHONE_RE.search(page)
    return {
        **({"email": email.group(0).lower()} if email else {}),
        **({"phone": phone.group(1).strip()} if phone else {}),
    }


def scrape(campus):
    profs, seen, page_no = [], set(), 1
    while True:
        page = _fetch(AJAX, {"action": "fetch_faculties", "campus": CAMPUS_IDS[campus],
                             "department": "", "paged": page_no, "page_name": "faculty"})
        cards = [c for c in parse_cards(page) if c["profileUrl"] not in seen]
        if not cards:
            break
        for card in cards:
            seen.add(card["profileUrl"])
            try:
                card.update(parse_profile(_fetch(card["profileUrl"])))
            except Exception as e:  # noqa: BLE001 — keep the card, report the gap
                print(f"  profile failed: {card['profileUrl']}: {e}", file=sys.stderr)
            profs.append(card)
            time.sleep(0.3)  # be polite to the institute's server
        print(f"page {page_no}: {len(profs)} so far", file=sys.stderr)
        page_no += 1
    return profs


def new_faculty(roster, existing):
    """Roster entries Tabulr has no professor for, by email or exact name.
    Respelled names are left to the rebuild's matching, which reports them."""
    emails = {str(e.get("email") or "").lower() for e in existing} - {""}
    names = {str(e.get("name") or "").strip().upper() for e in existing}
    return [p for p in roster
            if str(p.get("email") or "").lower() not in emails
            and p["name"].strip().upper() not in names]


def _self_check():
    card = '''<div class="faculty-tags"><div><span class="blue-tag"><a href="#">Hyderabad</a></span>
      <span class="yellow-tag"><a href="#">Computer Science &amp; Information Systems</a></span> </div></div>
      <p class="facul-title"><a href="https://www.bits-pilani.ac.in/hyderabad/arun-rai">Arun Rai</a></p>
      <p class="facul-desp">Distinguished Adjunct Professors
Dept. of Computer Science and Information Systems</p>'''
    assert parse_cards(card) == [{
        "name": "Arun Rai",
        "department": "Computer Science & Information Systems",
        "designation": "Distinguished Adjunct Professors",
        "profileUrl": "https://www.bits-pilani.ac.in/hyderabad/arun-rai",
    }], parse_cards(card)
    profile = '<p>Telangana, India</p><p>Kavi.Devraj@hyderabad.bits-pilani.ac.in</p><p>040-66303727</p>'
    named = card.replace(">Arun Rai<", ">Dr. Prof. Mr. Arun Rai<").replace("Professors\n", "Professor,\n")
    assert parse_cards(named)[0]["name"] == "Arun Rai", parse_cards(named)
    assert parse_cards(named)[0]["designation"] == "Distinguished Adjunct Professor", parse_cards(named)
    assert _clean_name("Parikshit Sahatiya डॉ. परीक्षित सहतिया") == "Parikshit Sahatiya"
    assert _clean_name("Ms. Aleena Khan") == "Aleena Khan"
    assert parse_profile(profile) == {"email": "kavi.devraj@hyderabad.bits-pilani.ac.in",
                                      "phone": "040-66303727"}, parse_profile(profile)
    existing = [{"name": "Kavi Devraj", "email": "kavi.devraj@hyderabad.bits-pilani.ac.in"},
                {"name": "Vuppuluri Amol"}]
    roster = [{"name": "Kavi Devraj", "email": "KAVI.DEVRAJ@hyderabad.bits-pilani.ac.in"},
              {"name": "vuppuluri amol"}, {"name": "Manas Pradhan", "email": "m@x"}]
    assert [p["name"] for p in new_faculty(roster, existing)] == ["Manas Pradhan"]
    print("faculty.py self-check passed", file=sys.stderr)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]:
        _self_check()
        sys.exit(0)
    if len(sys.argv) != 2 or sys.argv[1] not in CAMPUS_IDS:
        sys.exit(f"usage: {sys.argv[0]} <{'|'.join(CAMPUS_IDS)}> > profs.json   (or --self-check)")
    profs = scrape(sys.argv[1])
    missing = [p["name"] for p in profs if "email" not in p]
    print(f"{len(profs)} faculty, {len(missing)} without an email: {missing}", file=sys.stderr)
    json.dump({"profs": profs}, sys.stdout, indent=2, ensure_ascii=False)
    print()

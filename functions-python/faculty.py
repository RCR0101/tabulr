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


# Profile pages fetched at once. One at a time, a few hundred of them ran
# close to the scheduled check's 540 s limit; a handful in parallel, each
# still pausing between requests, stays polite and well inside it.
PROFILE_WORKERS = 4
MAX_PAGES = 100  # a listing that never ends is a changed site, not 2000 faculty


def _with_profile(card):
    try:
        card.update(parse_profile(_fetch(card["profileUrl"])))
    except Exception as e:  # noqa: BLE001 — keep the card, report the gap
        print(f"  profile failed: {card['profileUrl']}: {e}", file=sys.stderr)
    time.sleep(0.3)  # be polite to the institute's server
    return card


def scrape(campus):
    from concurrent.futures import ThreadPoolExecutor
    cards, seen = [], set()
    for page_no in range(1, MAX_PAGES + 1):
        page = _fetch(AJAX, {"action": "fetch_faculties", "campus": CAMPUS_IDS[campus],
                             "department": "", "paged": page_no, "page_name": "faculty"})
        new = [c for c in parse_cards(page) if c["profileUrl"] not in seen]
        if not new:
            break
        seen.update(c["profileUrl"] for c in new)
        cards += new
        print(f"page {page_no}: {len(cards)} so far", file=sys.stderr)
    with ThreadPoolExecutor(max_workers=PROFILE_WORKERS) as pool:
        return list(pool.map(_with_profile, cards))


def _name_tokens(name):
    return sorted(t for t in re.split(r"[^a-z]+", str(name or "").casefold()) if t)


def same_person_name(a, b):
    """Whether two spellings of a name are the same person, as the faculty
    site and the timetable write them: word order ("Vuppuluri Amol" / "Amol
    Vuppuluri"), initials' dots ("A. K. Jayesh" / "A K Jayesh") and a letter
    or two of spelling. Strict on purpose: a miss here only means one extra
    row in the notice, but a false match hides a new faculty member."""
    from difflib import SequenceMatcher
    ta, tb = _name_tokens(a), _name_tokens(b)
    if not ta or not tb:
        return False
    if ta == tb:
        return True
    full_a, full_b = [t for t in ta if len(t) > 1], [t for t in tb if len(t) > 1]
    if len(full_a) != len(full_b) or not full_a:
        return False
    return SequenceMatcher(None, " ".join(full_a), " ".join(full_b)).ratio() >= 0.9


def new_faculty(roster, existing):
    """Roster entries Tabulr has no professor for: no doc with their email,
    and none whose name is theirs however spelled (same_person_name). Two
    different emails are two different people, however close the names."""
    emails = {str(e.get("email") or "").lower() for e in existing} - {""}
    out = []
    for p in roster:
        email = str(p.get("email") or "").lower()
        if email and email in emails:
            continue
        if any(same_person_name(p["name"], e.get("name"))
               and not (email and e.get("email") and str(e["email"]).lower() != email)
               for e in existing):
            continue
        out.append(p)
    return out


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
    # Respellings the timetable uses are the same person, not new faculty.
    assert same_person_name("Vuppuluri Amol", "Amol Vuppuluri")
    assert same_person_name("A. K. Jayesh", "A K Jayesh")
    assert same_person_name("Sweta Agarwala", "Sweta Agarwal")
    assert not same_person_name("Pranay Sharma", "Pranav Sharma Rao")
    assert not same_person_name("Ravi Kumar", "Ravi Shankar")
    assert not same_person_name("", "Ravi Kumar")
    existing = [{"name": "Amol Vuppuluri"}, {"name": "A K Jayesh"}, {"name": "Ravi Kumar", "email": "rk@x"}]
    roster = [{"name": "Vuppuluri Amol", "email": "va@x"}, {"name": "A. K. Jayesh"},
              {"name": "Ravi Kumar", "email": "ravi.kumar2@x"}, {"name": "Ravi Shankar"}]
    # A different email under the same name is a second Ravi Kumar.
    assert [p["name"] for p in new_faculty(roster, existing)] == ["Ravi Kumar", "Ravi Shankar"], new_faculty(roster, existing)
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

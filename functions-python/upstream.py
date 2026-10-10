"""Watches the upstream sources Tabulr's data comes from and queues anything
new for an admin, so keeping the app current does not depend on one person
remembering to check.

- LMS site news (lms.bits-hyderabad.ac.in, public): "Timetable changes-N"
  posts with a PDF each.
- The Bulletin: a new year's PDF appearing at the predictable URL.

Each find becomes `upstream_notices/{id}` with status "new". The admin screen
lists them: seating and timetable-change posts arrive parsed, and an admin
applies them from there (changes.py proposes the section edits). Nothing here
writes to course data.
"""

import html
import os
import re
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone

LMS_HOME = "https://lms.bits-hyderabad.ac.in/"
BULLETIN_URLS = [
    # The site has used both spellings; try each for the coming session.
    "https://www.bits-goa.ac.in/files/Bulletin/Bulletin-{y}-{y1}.pdf",
    "https://www.bits-goa.ac.in/files/Bulletin/Bulletin-{y}-{yy1}.pdf",
]
_UA = {"User-Agent": "Mozilla/5.0 (Tabulr upstream watcher; +https://tabulr.net)"}

_ARTICLE_RE = re.compile(r'<article\b[^>]*\bdata-post-id="(\d+)"(.*?)</article>', re.S)
_SUBJECT_RE = re.compile(r'data-region-content="forum-post-core-subject"[^>]*>(.*?)</h3>', re.S)
_TIME_RE = re.compile(r'<time datetime="([^"]+)"')
_ATTACH_RE = re.compile(r'href="(https://[^"]*/mod_forum/attachment/[^"]+)"[^>]*>(?:.*?/>)?\s*([^<]+?)\s*</a>', re.S)
_DISCUSS_RE = re.compile(r'href="(https://[^"]*/mod/forum/discuss\.php\?[^"]+)"')


def parse_lms_posts(page):
    """Site-news posts on the LMS front page, newest first as the page lists them."""
    posts = []
    for post_id, body in _ARTICLE_RE.findall(page):
        subject = _SUBJECT_RE.search(body)
        when = _TIME_RE.search(body)
        discuss = _DISCUSS_RE.search(body)
        posts.append({
            "postId": post_id,
            "title": html.unescape(re.sub(r"\s+", " ", subject.group(1)).strip()) if subject else "",
            "postedAt": when.group(1) if when else None,
            "url": html.unescape(discuss.group(1)) if discuss else LMS_HOME,
            "attachments": [
                {"name": html.unescape(name.strip()), "url": html.unescape(url)}
                for url, name in _ATTACH_RE.findall(body)
            ],
        })
    return posts


_SEATING_RE = re.compile(r"seat", re.I)
_CHANGES_RE = re.compile(r"time\s*-?\s*table\s+changes?", re.I)


def post_kind(post):
    """What an LMS post is, from its title and attachment names."""
    text = " ".join([post.get("title", "")] + [a["name"] for a in post.get("attachments", [])])
    if _SEATING_RE.search(text):
        return "seating"
    if _CHANGES_RE.search(text):
        return "timetable_changes"
    return "notice"


def seating_preview(exams):
    """One line an admin can sanity-check before applying."""
    def when(label):
        try:
            return datetime.strptime(label, "%d %B %y")
        except ValueError:
            return datetime.max
    dates = sorted({re.sub(r"\s+", " ", e.get("examDate", "")).split(" - ")[0].strip()
                    for e in exams if e.get("examDate")}, key=lambda d: (when(d), d))
    span = f"{dates[0]} to {dates[-1]}" if len(dates) > 1 else (dates[0] if dates else "no dates")
    rooms = sum(len(e.get("rooms", [])) for e in exams)
    return f"{len(exams)} courses, {rooms} room allocations, {span}"


def download(url, suffix=".pdf"):
    req = urllib.request.Request(url, headers=_UA)
    with urllib.request.urlopen(req, timeout=60) as r, \
            tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
        f.write(r.read())
        return f.name


def bulletin_candidates(now):
    """URLs the next session's Bulletin would be published at. The Bulletin for
    session Y-(Y+1) normally appears around July of year Y."""
    y = now.year if now.month >= 6 else now.year - 1
    return [u.format(y=y, y1=y + 1, yy1=f"{(y + 1) % 100:02d}") for u in BULLETIN_URLS]


def _get(url, method="GET", timeout=20):
    req = urllib.request.Request(url, method=method, headers=_UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, (r.read().decode("utf-8", "replace") if method == "GET" else "")


def _exists(url):
    try:
        return _get(url, method="HEAD")[0] == 200
    except urllib.error.URLError:
        return False


def _record(db, doc_id, notice):
    """Creates the notice once; a notice already seen (in any status) is left alone."""
    from google.api_core.exceptions import AlreadyExists
    try:
        db.collection("upstream_notices").document(doc_id).create({
            **notice,
            "status": "new",
            "foundAt": datetime.now(timezone.utc),
        })
        return True
    except AlreadyExists:
        return False


def poll(db, now=None, parse_seating=None, summarize_changes=None):
    """[parse_seating] turns a seating PDF path into exam rows; when given, a
    new seating post arrives already parsed, ready to apply.
    [summarize_changes] turns a timetable-changes PDF path into a one-line
    preview of the edits it proposes."""
    now = now or datetime.now(timezone.utc)
    added = []
    try:
        _, page = _get(LMS_HOME)
        for post in parse_lms_posts(page):
            doc_id = f"lms_hyd_{post['postId']}"
            if db.collection("upstream_notices").document(doc_id).get().exists:
                continue
            notice = {"source": "lms_hyd", "kind": post_kind(post), **post}
            pdf = next((a for a in post["attachments"] if a["name"].lower().endswith(".pdf")), None)
            reader = {"seating": parse_seating, "timetable_changes": summarize_changes}.get(notice["kind"])
            if pdf and reader:
                path = None
                try:
                    path = download(pdf["url"])
                    if notice["kind"] == "seating":
                        exams = reader(path)
                        notice["preview"] = seating_preview(exams) if exams else "No seating rows found in the PDF"
                        notice["applicable"] = bool(exams)
                    else:
                        notice["preview"] = reader(path)
                        notice["applicable"] = True
                except Exception as e:  # noqa: BLE001 — the notice still goes up
                    notice["preview"] = f"Could not read the PDF: {e}"
                finally:
                    if path:
                        os.unlink(path)
            if _record(db, doc_id, notice):
                added.append(post["title"])
    except Exception as e:  # noqa: BLE001 — one dead source must not stop the others
        print(f"[upstream] LMS poll failed: {e}")

    for url in bulletin_candidates(now):
        if _exists(url):
            name = url.rsplit("/", 1)[-1]
            if _record(db, f"bulletin_{name}", {
                "source": "bulletin",
                "title": f"New Bulletin published: {name}",
                "url": url,
                "attachments": [{"name": name, "url": url}],
            }):
                added.append(name)
            break
    print(f"[upstream] {len(added)} new: {added}")
    return added


if __name__ == "__main__":
    sample = """
    <article id="p707" class="forum-post-container mb-2" data-post-id="707" data-region="post">
      <h3 class="h6 font-weight-bold mb-0" data-region-content="forum-post-core-subject"
          data-reply-subject="Re: Timetable changes - 6 " >Timetable changes - 6 </h3>
      by <a href="x">Time Table</a> - <time datetime="2026-09-08T17:05:57+05:30">Tuesday</time>
      <a
          href="https://lms.bits-hyderabad.ac.in/pluginfile.php/39/mod_forum/attachment/707/Timetable%20changes-6.pdf?forcedownload=1"
          aria-label="Attachment Timetable changes-6.pdf"
      >
          <img class="icon " alt="" aria-hidden="true" src="https://lms/f/pdf" /> Timetable changes-6.pdf
      </a>
      <a data-region="post-action" href="https://lms.bits-hyderabad.ac.in/mod/forum/discuss.php?d=702#p707">Permalink</a>
    </article>
    <article id="p1" data-post-id="1" data-region="post">
      <h3 data-region-content="forum-post-core-subject">Fees &amp; dues</h3>
    </article>
    """
    posts = parse_lms_posts(sample)
    assert len(posts) == 2, posts
    p = posts[0]
    assert p["postId"] == "707" and p["title"] == "Timetable changes - 6", p
    assert p["postedAt"] == "2026-09-08T17:05:57+05:30", p
    assert p["url"].endswith("discuss.php?d=702#p707"), p
    assert p["attachments"] == [{
        "name": "Timetable changes-6.pdf",
        "url": "https://lms.bits-hyderabad.ac.in/pluginfile.php/39/mod_forum/attachment/707/Timetable%20changes-6.pdf?forcedownload=1",
    }], p["attachments"]
    assert posts[1]["title"] == "Fees & dues" and posts[1]["attachments"] == [], posts[1]
    assert post_kind(p) == "timetable_changes"
    assert post_kind({"title": "MID SEMESTER EXAMINATION", "attachments": [{"name": "Seating Arrangement.pdf", "url": ""}]}) == "seating"
    assert post_kind(posts[1]) == "notice"
    assert seating_preview([
        {"examDate": "09 October 26 - 09:30\nAM to 11:00 AM", "rooms": [{}, {}]},
        {"examDate": "12 October 26 - 02:00 PM", "rooms": [{}]},
        {"examDate": "01 November 26 - 02:00 PM", "rooms": []},
    ]) == "3 courses, 3 room allocations, 09 October 26 to 01 November 26"
    # A July check looks for the session starting that year; February for the one already running.
    assert bulletin_candidates(datetime(2026, 7, 1))[0].endswith("Bulletin-2026-2027.pdf")
    assert bulletin_candidates(datetime(2026, 7, 1))[1].endswith("Bulletin-2026-27.pdf")
    assert bulletin_candidates(datetime(2027, 2, 1))[0].endswith("Bulletin-2026-2027.pdf")
    print("upstream.py self-check passed")

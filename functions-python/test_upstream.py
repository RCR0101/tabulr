"""Checks for the upstream watcher and the admin actions on its notices, with
the network and Firestore replaced by in-memory fakes:

    functions-python/venv/bin/python functions-python/test_upstream.py
    (or: pytest functions-python/test_upstream.py)

Covers: poll() (every PDF on a seating post, nothing twice, a dead Bulletin
host), Retry on a notice whose PDF could not be read, the weekly roster
check retiring an older notice, and Apply / Undo of timetable changes.
"""
import copy
import itertools
import os
import sys
import tempfile
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("GCLOUD_PROJECT", "tabulr-test")

from google.api_core.exceptions import AlreadyExists  # noqa: E402
from google.cloud.firestore_v1.transforms import ArrayUnion, Sentinel  # noqa: E402

import upstream  # noqa: E402
import main  # noqa: E402
import changes  # noqa: E402


# ─── Patching that is undone after each test (pytest's teardown_function,
# and the loop at the bottom), so other test files see the real modules ───

_saved = []


def patch(obj, name, value):
    _saved.append((obj, name, getattr(obj, name)))
    setattr(obj, name, value)


def teardown_function(_fn=None):
    while _saved:
        obj, name, value = _saved.pop()
        setattr(obj, name, value)


# ─── An in-memory Firestore: documents keyed by full path ───

_ids = itertools.count(1)


class Snap:
    def __init__(self, ref, data):
        self.reference, self.id, self._data = ref, ref.id, data

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        # Firestore hands back a copy, never the stored object.
        return copy.deepcopy(self._data)


class Doc:
    def __init__(self, db, path):
        self.db, self.path, self.id = db, path, path.rsplit("/", 1)[-1]

    def get(self):
        return Snap(self, self.db.docs.get(self.path))

    def create(self, data):
        if self.path in self.db.docs:
            raise AlreadyExists("exists")
        self.set(data)

    def set(self, data, merge=False):
        clean = copy.deepcopy({k: v for k, v in data.items() if not isinstance(v, Sentinel)})
        self.db.docs[self.path] = {**self.db.docs.get(self.path, {}), **clean} if merge else clean

    def update(self, data):
        doc = self.db.docs[self.path]
        for k, v in data.items():
            if isinstance(v, ArrayUnion):
                doc[k] = doc.get(k, []) + list(v.values)
            elif not isinstance(v, Sentinel):
                doc[k] = copy.deepcopy(v)

    def delete(self):
        self.db.docs.pop(self.path, None)

    def collection(self, name):
        return Coll(self.db, f"{self.path}/{name}")


class Coll:
    def __init__(self, db, path, filters=()):
        self.db, self.path, self.filters = db, path, filters

    def document(self, doc_id=None):
        return Doc(self.db, f"{self.path}/{doc_id or f'auto{next(_ids)}'}")

    def where(self, field, op, value):
        return Coll(self.db, self.path, self.filters + ((field, value),))

    def stream(self):
        depth = self.path.count("/") + 1
        for path, data in list(self.db.docs.items()):
            if path.startswith(self.path + "/") and path.count("/") == depth \
                    and all(data.get(k) == v for k, v in self.filters):
                yield Snap(Doc(self.db, path), data)

    get = stream


class Batch:
    def __init__(self):
        self.ops = []

    def set(self, ref, data, merge=False):
        self.ops.append(lambda: ref.set(data, merge=merge))

    def update(self, ref, data):
        self.ops.append(lambda: ref.update(data))

    def delete(self, ref):
        self.ops.append(ref.delete)

    def commit(self):
        for op in self.ops:
            op()


class FakeDB:
    def __init__(self):
        self.docs = {}

    def collection(self, path):
        return Coll(self, path)

    def document(self, path):
        return Doc(self, path)

    def batch(self):
        return Batch()

    def get_all(self, refs):
        return [r.get() for r in refs]


def use(db):
    patch(main, "get_db", lambda: db)
    patch(main, "require_admin", lambda req: "uid")


def request(**data):
    return types.SimpleNamespace(data=data, auth=types.SimpleNamespace(uid="u", token={"email": "admin@x"}))


def fake_download(url, suffix=".pdf"):
    fd, path = tempfile.mkstemp(suffix="-" + url.rsplit("/", 1)[-1])
    os.write(fd, url.encode())
    os.close(fd)
    return path


def call(fn, req):
    """The plain function under the firebase_functions decorators."""
    import inspect
    return inspect.unwrap(fn)(req)


# ─── poll ───

LMS_PAGE = """
<article data-post-id="9"><h3 data-region-content="forum-post-core-subject">Midsem Seating Arrangement</h3>
<time datetime="2026-10-01T10:00:00+05:30">x</time>
<a href="https://lms.bits-hyderabad.ac.in/pluginfile.php/1/mod_forum/attachment/9/Day1.pdf">Day1.pdf</a>
<a href="https://lms.bits-hyderabad.ac.in/pluginfile.php/1/mod_forum/attachment/9/Day2.pdf">Day2.pdf</a>
</article>
<article data-post-id="10"><h3 data-region-content="forum-post-core-subject">Timetable changes - 7</h3>
<a href="https://lms.bits-hyderabad.ac.in/pluginfile.php/1/mod_forum/attachment/10/c.pdf">c.pdf</a>
</article>"""


def seating_by_file(path):
    if path.endswith("Day1.pdf"):
        return [{"courseCode": "CS F211", "examDate": "09 October 26 - 9 AM", "rooms": [{"r": 1}]}]
    return [{"courseCode": "ME F212", "examDate": "10 October 26 - 9 AM", "rooms": [{"r": 2}]}]


def test_poll_reads_every_seating_pdf_and_survives_a_dead_bulletin_host():
    def fake_get(url, method="GET", timeout=20):
        if url == upstream.LMS_HOME:
            return 200, LMS_PAGE
        raise TimeoutError("slow host")  # not a URLError: used to abort the run
    patch(upstream, "_get", fake_get)
    patch(upstream.urllib.request, "urlopen", lambda *a, **k: (_ for _ in ()).throw(TimeoutError()))
    patch(upstream, "download", fake_download)
    db = FakeDB()
    added = upstream.poll(db, parse_seating=seating_by_file, summarize_changes=lambda p: "3 changes: 3 to apply")
    assert added == ["Midsem Seating Arrangement", "Timetable changes - 7"], added
    seat = db.docs["upstream_notices/lms_hyd_9"]
    assert seat["applicable"] is True and seat["readFailed"] is False
    assert seat["preview"].startswith("2 courses, 2 room allocations"), seat["preview"]
    assert upstream.poll(db, parse_seating=seating_by_file, summarize_changes=lambda p: "") == []


def test_retry_reads_a_failed_notice_again():
    db = FakeDB()
    use(db)
    patch(upstream, "download", fake_download)
    db.docs["upstream_notices/lms_hyd_9"] = {
        "kind": "seating", "status": "new", "readFailed": True, "applicable": False,
        "preview": "Could not read the PDF: timed out",
        "attachments": [{"name": "Day1.pdf", "url": "https://lms/x/Day1.pdf"}],
    }
    patch(main, "parse_seating_pdf", seating_by_file)
    out = call(main.retry_notice, request(noticeId="lms_hyd_9"))
    notice = db.docs["upstream_notices/lms_hyd_9"]
    assert out["readFailed"] is False and notice["readFailed"] is False
    assert notice["applicable"] is True and notice["preview"].startswith("1 courses"), notice

    def broken(url, suffix=".pdf"):
        raise TimeoutError("still down")
    patch(upstream, "download", broken)
    call(main.retry_notice, request(noticeId="lms_hyd_9"))
    assert db.docs["upstream_notices/lms_hyd_9"]["readFailed"] is True


# ─── faculty roster ───

def test_a_newer_roster_check_retires_the_older_notice():
    db = FakeDB()
    use(db)
    db.docs["upstream_notices/roster_hyderabad_old"] = {"kind": "roster", "status": "new"}
    db.docs["upstream_notices/roster_hyderabad_done"] = {"kind": "roster", "status": "done"}
    for i in range(118):
        db.docs[f"reference/professors/hyderabad-entries/e{i}"] = {"name": f"Prof Number{i}", "email": f"p{i}@x"}
    patch(main.faculty, "scrape", lambda c: [{"name": f"Prof Number{i}", "email": f"p{i}@x", "profileUrl": f"u{i}"}
                                     for i in range(120)])
    call(main.check_faculty_roster, None)
    notices = {k.rsplit("/", 1)[-1]: v for k, v in db.docs.items() if k.startswith("upstream_notices/")}
    assert notices["roster_hyderabad_old"]["status"] == "dismissed"
    assert notices["roster_hyderabad_done"]["status"] == "done"
    fresh = [k for k, v in notices.items() if v.get("status") == "new"]
    assert len(fresh) == 1 and notices[fresh[0]]["title"] == "2 new faculty on the BITS website", notices
    call(main.check_faculty_roster, None)  # same finding next week: nothing new
    assert [k for k, v in db.docs.items() if k.startswith("upstream_notices/") and v.get("status") == "new"] \
        == [f"upstream_notices/{fresh[0]}"]


# ─── apply and undo ───

TT = "campuses/hyderabad/timetable"


def changes_setup():
    db = FakeDB()
    use(db)
    patch(upstream, "download", fake_download)
    db.docs["upstream_notices/lms_hyd_10"] = {
        "kind": "timetable_changes", "status": "new",
        "attachments": [{"name": "c.pdf", "url": "https://lms/x/c.pdf"}],
    }
    db.docs[f"{TT}/CS_F211"] = {"sections": [
        {"sectionId": "L1", "type": "SectionType.L", "instructor": "Old Prof", "room": "F101", "schedule": []}]}
    patch(changes, "parse_pdf", lambda path: [{
        "kind": "instructor", "course": "CS F211", "section": "L1", "inherited": False,
        "existing": "Old Prof", "new": "New Prof", "run_section": "L1", "prior_new": "",
    }])
    key = changes.propose(changes.parse_pdf(""), {"CS_F211": db.docs[f"{TT}/CS_F211"]}, {})[0]["key"]
    return db, key


def test_apply_then_undo_restores_the_course():
    db, key = changes_setup()
    out = call(main.apply_changes_notice, request(noticeId="lms_hyd_10", keys=[key]))
    assert out["applied"] == 1
    assert db.docs[f"{TT}/CS_F211"]["sections"][0]["instructor"] == "New Prof"
    [applied] = out["applies"]
    assert applied["undoable"] and applied["courses"] == ["CS F211"], applied

    restored = main.undo_apply(db, db.collection("upstream_notices").document("lms_hyd_10"), applied["id"], "admin@x")
    assert restored == ["CS F211"]
    assert db.docs[f"{TT}/CS_F211"]["sections"][0]["instructor"] == "Old Prof"
    assert db.docs["upstream_notices/lms_hyd_10"]["status"] == "new"
    record = db.docs[f"upstream_notices/lms_hyd_10/applies/{applied['id']}"]
    assert record["undone"] is True and record["undoneBy"] == "admin@x"
    try:
        main.undo_apply(db, db.collection("upstream_notices").document("lms_hyd_10"), applied["id"])
        raise AssertionError("undid twice")
    except ValueError as e:
        assert "Already undone" in str(e)


def test_undo_refuses_when_the_course_was_edited_since():
    db, key = changes_setup()
    out = call(main.apply_changes_notice, request(noticeId="lms_hyd_10", keys=[key]))
    db.docs[f"{TT}/CS_F211"]["sections"][0]["room"] = "F999"  # an edit in Course Management
    try:
        main.undo_apply(db, db.collection("upstream_notices").document("lms_hyd_10"), out["applies"][0]["id"])
        raise AssertionError("undo overwrote a later edit")
    except ValueError as e:
        assert "CS F211" in str(e), e
    assert db.docs[f"{TT}/CS_F211"]["sections"][0]["room"] == "F999"


def test_undo_of_a_new_course_deletes_it():
    db, _ = changes_setup()
    patch(changes, "parse_pdf", lambda path: [{
        "kind": "new_course", "course": "CS F999", "sections": ["L1"], "instructor": "A Prof",
        "hours": "M W 2 F101", "exam": "",
    }])
    db.docs["campuses/hyderabad/courses_master/CS_F999"] = {"credits": 3}
    key = changes.propose(changes.parse_pdf(""), {}, {"CS_F999": {"credits": 3}})[0]["key"]
    out = call(main.apply_changes_notice, request(noticeId="lms_hyd_10", keys=[key]))
    assert f"{TT}/CS_F999" in db.docs
    main.undo_apply(db, db.collection("upstream_notices").document("lms_hyd_10"), out["applies"][0]["id"])
    assert f"{TT}/CS_F999" not in db.docs


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        try:
            t()
        finally:
            teardown_function()
        print(f"ok  {t.__name__}")
    print("test_upstream.py passed")

# Data scripts

Admin-side scripts that write Tabulr's reference data to Firestore. Day-to-day
uploads don't need them: the timetable, academic calendar, exam seating and
professor schedules are all uploaded from **Admin** in the app, through the
`functions-python` and `functions` callables. See `docs/RUNBOOK.md` for the
per-semester order.

## Credentials

Scripts read a Firebase service account from `.env` (`FIREBASE_PROJECT_ID`,
`FIREBASE_PRIVATE_KEY`, `FIREBASE_CLIENT_EMAIL`, …) or `serviceAccountKey.json`
in this folder. Both are gitignored. Get the key from Firebase Console →
Project Settings → Service Accounts.

```bash
cd scripts && npm ci
```

## What each script is for

| Script | When |
|---|---|
| `upload-courses-master.js` | A new course list. Writes `courses_master` and its catalogue bundle on all three campuses. |
| `upload-branch-structure.js` | CDC structure changes (new batch or curriculum). |
| `upload-duplicate-courses.js` | Cross-listed course groups change. |
| `upload-prerequisites.js` | AUGSD publishes a new requisite CSV. Details below. |
| `extract-bulletin-prereqs.py` → `apply-bulletin-prereqs.mjs` | A new Bulletin. Fills prerequisite gaps from its course descriptions. Details below. |
| `fetch-prerequisites.mjs` | Read-only dump of the live prerequisite collection. |
| `generate-static-pages.js` | Runs in CI. Builds the crawlable course pages. |
| `predeploy-python.sh` | Runs before every `functions-python` deploy. Stamps the parser version. |
| `upload_calendar_preview.py` | Local preview of the academic-calendar parse. |
| `acad-drives/` | The Acad Drives sync crawler. It has its own README and `package.json`. |


## Prerequisites (`upload-prerequisites.js`)

Loads the official BITS requisite export (`BITS_PREREQ_LIST.csv`) into
`reference/prerequisites/courses`. Upserts only the courses the CSV covers and
leaves the rest of the collection alone.

```bash
node upload-prerequisites.js ~/Downloads/BITS_PREREQ_LIST.csv            # dry run + diff against live
node upload-prerequisites.js ~/Downloads/BITS_PREREQ_LIST.csv --commit
node upload-prerequisites.js --self-check                                # parser asserts, no network
```

Read the dry run before committing: it lists the live options the CSV drops
outright, which are the ones a human has to sign off on.

## Static SEO pages (`generate-static-pages.js`)

Writes crawlable HTML for the course catalogue into the built web app. The
Flutter UI renders to a `<canvas>`, so these pages are the only thing a search
engine can read.

**This runs automatically** in the `build-web` CI job, between
`flutter build web` and the preview deployment. Production promotes that exact
artifact instead of regenerating it. You only need to run it by hand to preview
the output:

```bash
node generate-static-pages.js --sample /tmp/preview   # renders the templates, no Firestore
open /tmp/preview/courses/cs-f211/index.html
```

No setup, no dependencies and no credentials. It reads the public Firestore
REST API with the web API key from `lib/firebase_options.dart` — everything it
touches is `allow read: if true` in `firestore.rules`, which is how the app
itself reads it before anyone signs in.

Each page carries what stays true — the course, its units, its prerequisites —
plus one line per campus for this semester's section count and exam dates.
Instructors, rooms and section timings are deliberately not published: they
change every semester, and an indexed page would keep answering with stale data.

The step is allowed to fail the whole job on purpose. A Hosting deploy replaces
the entire site, so deploying without these pages would 404 every course URL
Google has indexed — better to block and re-run.

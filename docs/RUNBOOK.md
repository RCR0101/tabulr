# Running Tabulr

For whoever keeps Tabulr current after its original maintainer graduates.
Code setup is in `ENVIRONMENT_SETUP.md`. This file covers **keeping the data
right** and **what you need access to**.

For day-to-day admin work, the in-app **Admin handbook** explains every card and section; open it from the Handbook button on the admin dashboard (`lib/utils/admin_guide_content.dart`). This runbook covers what happens outside the app.

Start each visit at **Admin → Data freshness**:

- **Green:** refreshed this term.
- **Amber:** left over from last term.
- **Red:** never uploaded.

**Admin → Upstream changes** lists what the watcher found upstream that nobody has handled yet.

## Every semester

The booklets come out in July (odd semester) and December (even semester).
In this order:

1. **Timetable.** Get the booklet PDF from the Timetable Division. Upload it in
   Admin → Timetable Upload, once per campus.
   - Set **page ranges**. The whole-booklet path imports page furniture.
   - Set the **exam year**: the calendar year the exams fall in. It defaults correctly.
   - Set the **semester**.
   - Fill the calendar page range too, and the academic calendar comes along.
   - The preview shows the diff before anything is written.
   - An upload that keeps less than 80% of the live courses is refused. Only tick
     "force" if the new booklet really is smaller.
2. **Professor schedules** (Hyderabad) **rebuild themselves** whenever the timetable
   changes: an upload, or an admin editing a section (`onTimetableChanged`).
   The rebuild keeps the chambers and emails already on file, and reports
   any name it matched only by spelling. New faculty only appear after a fresh roster:
   a weekly check (`check_faculty_roster`) compares the BITS faculty
   directory with Tabulr and posts new faculty under Upstream changes; Apply adds
   them. By hand: `python3 functions-python/faculty.py hyderabad > profs.json`,
   then upload it with the rebuild. The faculty site publishes **no chambers**: edit those in
   Admin → Professor Chambers.
3. **Archive** last term's timetables (Admin → Archive Timetables).
4. **Acad Drives.** Approve new links in Admin → Drive Submissions. The
   `Acad Drives sync` GitHub Action runs every Monday (03:00 IST) and can be run
   by hand from the Actions tab. It needs three repo secrets:
   `ACAD_DRIVES_ENV` (the crawler's `.env`), `ACAD_DRIVES_SERVICE_ACCOUNT` and
   `ACAD_DRIVES_GDRIVE_TOKEN`. The Google OAuth app must be **in production,
   not testing**, or its refresh token expires after 7 days. To run it locally:
   ```bash
   cd scripts/acad-drives && node acad-drive-master.js upload          # read the dry run
   node acad-drive-master.js upload --apply
   ```
   See `scripts/acad-drives/README.md`.

## During the semester

- **Timetable changes.** The Timetable Division posts "Timetable changes-N" PDFs
  on the LMS front page. `poll_upstream` checks every Monday (or now, via **Check now** on Data freshness) and queues them
  under Upstream changes.
  - Press **Review**: `functions-python/changes.py` reads the PDF and judges each row against the
    live timetable (Ready / Check / Already in / Add by hand / Not found). Tick and **Apply**.
    Applying re-reads the PDF and the timetable first, and records each edit on the notice
    (`appliedChanges`). New courses with several sections on one hours line go in by hand in
    Course Management.
  - If the PDF layout changes, `functions-python/test_changes.py` is the check: put the PDFs in
    the repo root as `timetable-changes-N.pdf` and run it with the functions venv.
  - Students' saved timetables pick the change up on next open, with a "What changed" notice.
  - Mark the notice **Done**.
- **Exam seating** (Hyderabad): seating posted on the LMS front page is read by
  `poll_upstream` and appears under Upstream changes with a summary; **Apply**
  writes it (`apply_seating_notice`). Otherwise upload in Admin → Exam Seating.

## Every year

**A new Bulletin.** Upstream changes flags it when it appears at
`bits-goa.ac.in/files/Bulletin/`. Then:

- **Prerequisites:**
  ```bash
  python3 scripts/extract-bulletin-prereqs.py Bulletin.pdf --pages <first>-<last>
  node scripts/apply-bulletin-prereqs.mjs        # dry run, then --apply
  ```
  The page range is the course-description section, which moves every edition.
  AUGSD's requisite CSV goes through `scripts/upload-prerequisites.js`.
- **Minors.** Admin → Minor Programmes. Check the "Needs review" filter.
- **New batch CDCs.** `scripts/upload-branch-structure.js`, and Admin → Course Guide.

## Ground rules

- **Every script dry-runs unless given `--apply` or `--commit`.** Read the whole dry run before applying.
- **Fix data at the source**, not in the display.
- **Re-uploading course data never deletes a student's timetable.** Selections
  carry their own section copy. Keep it that way.
- **Maintenance mode** is `maintenance: true` on `reference/app_config`.
  Admins can still write while it is on.

## Access to hand over

Without these, the app keeps running but cannot be updated.

| What | Where | Notes |
|---|---|---|
| Admin role | Firestore `admin_emails/<email>` | Create the doc for each new admin. Lower-case the email. |
| Firebase project `timetable-maker-3c8e0` | Firebase console → Users and permissions | Add the successor as **Owner**. |
| GitHub repo + Actions secrets | `RCR0101/tabulr` | `FIREBASE_OPTIONS_DART`, `FIREBASE_SERVICE_ACCOUNT`, `LOGGER_API_KEY`. See `ENVIRONMENT_SETUP.md`. |
| Domain `tabulr.net` | Registrar + Firebase Hosting | Note the renewal date. |
| Cloudflare: R2 buckets + Workers | Account behind `*.dalmia-aryan.workers.dev` | Source in `workers/`. Move the Workers to a shared account, or add the successor. |
| **`ENCRYPTION_SECRET`** | `cgpa-encryption` Worker secret | **If lost, every student's encrypted CGPA data is unreadable.** Keep a copy somewhere the successor can reach. |
| Google Drive OAuth client | `.env` in `scripts/acad-drives/` | Read-only Drive scope, for the crawler. |
| Service account key | Firebase console → Service accounts | Generate a new one rather than passing a file around. |

Deploys:

- **Web:** push to `main` deploys to preview; run "Deploy Production" to promote it.
- **Functions:** `firebase deploy --only functions:python` or `--only functions:node`.
  The scheduled `poll_upstream` needs the Cloud Scheduler API enabled once.
- **Workers:** `cd workers/<name> && npx wrangler deploy`.
- **Rules:** `firebase deploy --only firestore:rules`, after `npm --prefix test/rules test`.

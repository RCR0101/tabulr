# Acad Drives sync

Copies students' Google Drive folders into R2 and records every file in Firestore
(`acad_drives_files`). It then builds the per-course index the app lists
(`acad_drives_index` + `tabulr_meta/acad-drives-index.json` on R2).

```bash
cd scripts/acad-drives && npm ci
node classify.js                         # resource-type self-check, no network
node acad-drive-master.js upload         # dry run: lists what would sync
node acad-drive-master.js upload --apply # sync new files, then rebuild the index
```

**Every command is a dry run unless you pass `--apply`.** That includes `purge-*` and `full-sync`.
Read the dry run first: it is the approval step.

## Where drives come from

The registry is the `acad_drives_sources` collection. It is admin-only, so contributors'
links stay out of this public repo. Each doc has `{name, driveLink, contributor, courseCode?, disabled?}`.

- **New drives:** students submit a link in the app. An admin approves it in
  Admin → Drive submissions, which writes the source doc. The next `upload --apply` syncs it.
- **`courseCode`** pins every file in that drive to one course, which overrides the name matching.
- **`disabled: true`** skips a drive without deleting what it already synced.
- **Sources with `driveLink: "NA"`** are local folders under `downloads/<name>/`
  (or `$DOWNLOADS_DIR/<name>/`).

## Resource types

`classify.js` gives every file a `resource_type`:

```
pyq · solutions · lectures · notes · books · assignments · handout · other
```

It adds `exam` (midsem / compre / quiz) and `year` where the path says so. It reads the file
name first, then its folders, nearest first.

After changing it:

```bash
node acad-drive-master.js reclassify > /tmp/reclassify.txt   # every change, uncapped
node acad-drive-master.js reclassify --apply
node acad-drive-master.js build-index --apply
```

## Credentials (all gitignored)

| What | Where |
|---|---|
| Firebase Admin | `serviceAccountKey.json` here, or `SERVICE_ACCOUNT_PATH` |
| R2 | `.env`: `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_R2_ACCESS_KEY_ID`, `CLOUDFLARE_R2_SECRET_ACCESS_KEY`, `CLOUDFLARE_R2_BUCKET_NAME`, `CLOUDFLARE_R2_ENDPOINT`, `CLOUDFLARE_R2_PUBLIC_URL`, `CLOUDFLARE_R2_CUSTOM_DOMAIN` |
| Google Drive | `.env`: `GOOGLE_DRIVE_CLIENT_ID`, `GOOGLE_DRIVE_CLIENT_SECRET`. The first run asks you to authorise and writes `gdrive-token.json`. |

## Other commands

| Command | What it does |
|---|---|
| `purge-junk` | Deletes code-environment folders (`.venv`, `.git`, `node_modules`, …) and build artefacts. |
| `rescore [--codes "CS F111,…"]` | Re-runs course matching and moves files in R2. |
| `reallocate <path-or-code> <code>` | Moves files to a course by hand. |
| `dedup` | Removes R2 duplicates by content hash. |
| `build-index` / `copy-index-r2` | Rebuilds the index. |

Course matching uses the Hyderabad `courses_master`, `reference/course_aliases`,
`reference/duplicate_courses` and `nicknames.json`.

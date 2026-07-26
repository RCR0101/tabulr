# Timetable Data Uploader

This script parses XLSX timetable files and uploads the data to Firestore, making the app much faster by eliminating client-side parsing.

## Setup

1. **Install dependencies:**
   ```bash
   cd scripts
   npm install
   ```

2. **Create Firebase Service Account:**
   - Go to Firebase Console → Project Settings → Service Accounts
   - Click "Generate New Private Key"
   - Download the JSON file

3. **Configure environment variables:**
   ```bash
   cp .env.example .env
   ```
   
   Fill in the values from your service account JSON file:
   - `FIREBASE_PROJECT_ID`: Your Firebase project ID
   - `FIREBASE_PRIVATE_KEY`: The private key (with \n escaped)
   - `FIREBASE_CLIENT_EMAIL`: The service account email
   - Other fields from the service account JSON

## Usage

```bash
# Upload a timetable XLSX file
npm run upload path/to/your/timetable.xlsx

# Test the parser without uploading
npm run test path/to/your/timetable.xlsx
```

### Prerequisites (`upload-prerequisites.js`)

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

### Static SEO pages (`generate-static-pages.js`)

Writes crawlable HTML for the course catalogue into the built web app. The
Flutter UI renders to a `<canvas>`, so these pages are the only thing a search
engine can read.

**This runs automatically** in `deploy-preview.yml` and `deploy-production.yml`,
between `flutter build web` and the Firebase deploy. You only need to run it by
hand to preview the output:

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

/**
 * apply-bulletin-prereqs.js — Fills gaps in the prerequisite collection from the
 * BITS Bulletin's course descriptions.
 *
 * The collection was originally built from the AUGSD table
 * `Pre-requisite_Website_18-01-2023.pdf`. The Bulletin (pages 611-784) is a
 * second, newer statement of the same facts: each course description may end
 * with a "Pre-requisites: ..." sentence. `bulletin-prereqs.json` holds
 * those sentences already parsed into the app's AND-of-ORs group shape — that
 * file is the data, this file is only the reconciler.
 *
 * Each bulletin course is compared with what is live and sorted into:
 *
 *   ADD       no document, or a document carrying no groups at all.
 *   WIDEN     every live requirement survives, but the bulletin accepts more
 *             alternatives for it (e.g. the cross-listed twins of a course).
 *             Strictly loosens — no student who qualifies today stops.
 *   EXTEND    every live requirement survives and the bulletin names additional
 *             ANDed requirements the collection is missing. This tightens the
 *             check, so it is reported separately even though it is applied.
 *   CONFLICT  the two sources disagree about structure or type — e.g. the AUGSD
 *             table joins two courses with OR where the bulletin uses "&".
 *             Held back unless --include-conflicts is passed, because resolving
 *             one means deciding which source wins.
 *   SAME      already correct.
 *
 * Usage:
 *   node apply-bulletin-prereqs.js                     # dry run — prints the diff
 *   node apply-bulletin-prereqs.js --apply             # write ADD/WIDEN/EXTEND
 *   node apply-bulletin-prereqs.js --apply --add-only  # write ADD only
 *   node apply-bulletin-prereqs.js --include-conflicts # also take the bulletin's
 *                                                      # side on CONFLICT rows
 */

import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function loadServiceAccount() {
  const keyPath = path.join(__dirname, 'serviceAccountKey.json');
  if (fs.existsSync(keyPath)) {
    return JSON.parse(fs.readFileSync(keyPath, 'utf8'));
  }

  dotenv.config({ path: path.join(__dirname, '.env') });
  if (!process.env.FIREBASE_PROJECT_ID || !process.env.FIREBASE_PRIVATE_KEY) {
    console.error(
      'No credentials found. Add serviceAccountKey.json in this folder or set the ' +
      'FIREBASE_* variables in scripts/.env.'
    );
    process.exit(1);
  }

  return {
    type: 'service_account',
    project_id: process.env.FIREBASE_PROJECT_ID,
    private_key_id: process.env.FIREBASE_PRIVATE_KEY_ID,
    private_key: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    client_email: process.env.FIREBASE_CLIENT_EMAIL,
    client_id: process.env.FIREBASE_CLIENT_ID,
    auth_uri: process.env.FIREBASE_AUTH_URI,
    token_uri: process.env.FIREBASE_TOKEN_URI,
    auth_provider_x509_cert_url: process.env.FIREBASE_AUTH_PROVIDER_X509_CERT_URL,
    client_x509_cert_url: process.env.FIREBASE_CLIENT_X509_CERT_URL,
  };
}

admin.initializeApp({ credential: admin.credential.cert(loadServiceAccount()) });
const db = admin.firestore();

const prereqsRef = db.collection('reference').doc('prerequisites').collection('courses');
// Freshness marker for the app's local cache. Must be the parent document of
// the courses subcollection: firestore.rules covers `reference/prerequisites`
// (world-readable, admin-writable) but has no rule for a top-level `metadata`
// collection, so a marker there is unreadable by clients — which silently
// disabled the cache and made every prereq load a full collection scan.
const metadataRef = db.collection('reference').doc('prerequisites');

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const ADD_ONLY = args.includes('--add-only');
const INCLUDE_CONFLICTS = args.includes('--include-conflicts');

const DATA = path.join(__dirname, 'bulletin-prereqs.json');
const BATCH_LIMIT = 500;

// ---------------------------------------------------------------------------

const docId = (courseCode) => courseCode.replace(/ /g, '_');

const options = (group) => group.options || group;

const fmt = (groups) =>
  (groups || []).map((g) => '(' + options(g)
    .map((o) => `${o.course_code}:${o.type}`).join(' OR ') + ')').join(' AND ') || '<none>';

const codesOf = (group) => new Set(options(group).map((o) => o.course_code));

const typesOf = (groups) => {
  const m = new Map();
  for (const g of groups || []) for (const o of options(g)) m.set(o.course_code, o.type);
  return m;
};

/**
 * Pair every live group with a bulletin group that contains it. Returns null the
 * moment a live requirement has no home — that is what makes a row a CONFLICT
 * rather than an enrichment.
 */
function coverLiveGroups(liveGroups, bulletinGroups) {
  const taken = new Set();
  const pairs = [];
  for (const live of liveGroups) {
    const lc = codesOf(live);
    const idx = bulletinGroups.findIndex((b, i) => {
      if (taken.has(i)) return false;
      const bc = codesOf(b);
      return [...lc].every((c) => bc.has(c));
    });
    if (idx === -1) return null;
    taken.add(idx);
    pairs.push([live, bulletinGroups[idx]]);
  }
  return pairs;
}

function classify(bulletinGroups, liveGroups) {
  if (!liveGroups || liveGroups.length === 0) return 'ADD';

  const pairs = coverLiveGroups(liveGroups, bulletinGroups);
  if (!pairs) return 'CONFLICT';

  // A course the live data types as `pre` must not silently become `co/pre`.
  const liveTypes = typesOf(liveGroups);
  const bulletinTypes = typesOf(bulletinGroups);
  for (const [code, t] of liveTypes) {
    if (bulletinTypes.has(code) && bulletinTypes.get(code) !== t) return 'CONFLICT';
  }

  if (bulletinGroups.length > liveGroups.length) return 'EXTEND';
  const widened = pairs.some(([live, b]) => options(b).length > options(live).length);
  return widened ? 'WIDEN' : 'SAME';
}

async function main() {
  console.log(APPLY ? '=== APPLYING CHANGES ===\n' : '=== DRY RUN (pass --apply to write) ===\n');

  const data = JSON.parse(fs.readFileSync(DATA, 'utf8'));
  console.log(`source: ${data.source.document}, pages ${data.source.pages}`);
  console.log(`bulletin courses with parseable prerequisites: ${data.courses.length}\n`);

  // listDocuments() rather than get(): phantom ids exist in this project, and a
  // phantom must be treated as absent-but-present so it is written, not skipped.
  const existing = new Set((await prereqsRef.listDocuments()).map((r) => r.id));

  const buckets = { ADD: [], WIDEN: [], EXTEND: [], CONFLICT: [], SAME: [] };

  for (const course of data.courses) {
    const id = docId(course.course_code);
    let live = null;
    if (existing.has(id)) {
      const snap = await prereqsRef.doc(id).get();
      live = snap.exists ? (snap.data().groups || []) : null;
    }
    buckets[classify(course.groups, live)].push({ course, live, id });
  }

  const explain = {
    ADD: 'no document, or a document with no groups',
    WIDEN: 'same requirements, more accepted alternatives',
    EXTEND: 'additional ANDed requirements the collection is missing',
    CONFLICT: 'the bulletin and the live data disagree — needs a call',
    SAME: 'already matches the bulletin',
  };

  for (const kind of ['ADD', 'WIDEN', 'EXTEND', 'CONFLICT', 'SAME']) {
    const rows = buckets[kind];
    console.log(`--- ${kind} (${rows.length}) — ${explain[kind]} ---`);
    for (const { course, live } of rows) {
      if (kind === 'SAME') {
        console.log(`  ${course.course_code}`);
        continue;
      }
      console.log(`  ${course.course_code} [bulletin p${course.page}] ${course.title}`);
      console.log(`      live    : ${fmt(live)}`);
      console.log(`      bulletin: ${fmt(course.groups)}`);
      if (course.skipped_codes.length) {
        console.log(`      not in courses_master, left out: ${course.skipped_codes.join(', ')}`);
      }
    }
    console.log('');
  }

  if (data.unparsed.length) {
    console.log(`--- NOT PARSEABLE (${data.unparsed.length}) — stated in prose, no write attempted ---`);
    for (const u of data.unparsed) {
      console.log(`  ${u.course_code} [p${u.page}] ${u.statement.slice(0, 90)}`);
    }
    console.log('');
  }

  let selected = ADD_ONLY
    ? buckets.ADD
    : [...buckets.ADD, ...buckets.WIDEN, ...buckets.EXTEND];
  if (INCLUDE_CONFLICTS) {
    selected = [...selected, ...buckets.CONFLICT];
  } else if (buckets.CONFLICT.length) {
    console.log(`${buckets.CONFLICT.length} CONFLICT row(s) held back; pass --include-conflicts ` +
                'to take the bulletin\'s side on them.\n');
  }

  const writes = selected.map(({ course, id }) => [id, {
    course_code: course.course_code,
    groups: course.groups.map((opts) => ({ options: opts })),
    has_prerequisites: course.groups.length > 0,
  }]);

  if (!APPLY) {
    console.log(`Dry run — ${writes.length} document(s) would be written. Re-run with --apply.`);
    process.exit(0);
  }

  for (let i = 0; i < writes.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const [id, payload] of writes.slice(i, i + BATCH_LIMIT)) {
      batch.set(prereqsRef.doc(id), payload);
    }
    await batch.commit();
  }
  console.log(`Wrote ${writes.length} document(s).`);

  // Freshness marker — clients cache the whole collection for 72h and only
  // refetch when this timestamp moves.
  await metadataRef.set({ lastUpdated: new Date().toISOString() }, { merge: true });
  console.log('Bumped reference/prerequisites.lastUpdated.');

  process.exit(0);
}

main().catch((err) => { console.error(err); process.exit(1); });

/**
 * Uploads the official BITS prerequisite export to `reference/prerequisites/courses`.
 *
 *   node upload-prerequisites.js ~/Downloads/BITS_PREREQ_LIST.csv            # dry run
 *   node upload-prerequisites.js ~/Downloads/BITS_PREREQ_LIST.csv --commit   # writes
 *   node upload-prerequisites.js --self-check                                # parser asserts
 *
 * The CSV is a PeopleSoft "course requisite" dump, one row per requirement
 * line. Its shape is not obvious:
 *
 *   - Columns repeat. Cols 0-3 are the course that HAS the requirement; cols
 *     16-19 are the course that SATISFIES it. Anything keyed by header name
 *     silently reads only the second block, so this parses positionally.
 *   - "Rq Group" is shared: one group is attached to many courses, so the same
 *     four lines repeat once per course that uses them. Group by target course,
 *     not by group id.
 *   - "Conn" is the connector FROM THE PREVIOUS line, not to the next. Group
 *     009923 reads `AND ( ECON C481 OR MGTS C382 OR FIN C342 OR MBA C416 )` —
 *     one requirement with four equivalents. Read the other way round it would
 *     demand two courses that are both titled "FINANCIAL MANAGEMENT".
 *
 * Which lands exactly on the app's AND-of-ORs model (see models/prerequisite.dart):
 * an OR connector extends the current group, anything else starts a new one.
 *
 * ponytail: the parenthesis columns are ignored. They are unbalanced in this
 * export (137 "(" against 47 ")") because non-CRSE lines were filtered out
 * before it was generated, so a real expression parser would be parsing
 * garbage. The connector rule reproduces the intended structure on every
 * balanced group in the file. If a future export is complete and contains
 * genuine nesting — `(A AND B) OR (C AND D)` — this flattens it, and the app's
 * model cannot represent it either; that is the point to revisit both.
 */
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { parse } from 'csv-parse/sync';
import fs from 'fs';
import path from 'path';
import assert from 'assert';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Column indices, by position. See the header comment on why not by name.
const COL = {
  targetSubject: 1,
  targetCatalog: 2,
  key: 6,
  reqType: 10,
  prereqSubject: 17,
  prereqCatalog: 18,
  connector: 25,
};

const code = (subject, catalog) => `${subject.trim()} ${catalog.trim()}`;

/** `PRE` / `CO` -> the app's canonical types (models/prerequisite.dart). */
const canonicalType = (raw) => (raw.trim().toUpperCase() === 'CO' ? 'co/pre' : 'pre');

/**
 * Rows for ONE target course -> the app's AND-of-ORs groups.
 *
 * Self-references are dropped: a shared Rq Group lists every course it is
 * attached to, so `ECON C481` ends up among its own prerequisites. Left in, the
 * app would tell a student they need a course to take that same course.
 */
export function rowsToGroups(rows, targetCode) {
  const groups = [];
  for (const row of [...rows].sort((a, b) => Number(a[COL.key]) - Number(b[COL.key]))) {
    const option = {
      course_code: code(row[COL.prereqSubject], row[COL.prereqCatalog]),
      type: canonicalType(row[COL.reqType]),
    };
    const isOr = row[COL.connector].trim().toUpperCase() === 'OR';
    if (!isOr || groups.length === 0) groups.push([]);
    const group = groups[groups.length - 1];
    if (option.course_code === targetCode) continue;
    if (group.some((o) => o.course_code === option.course_code)) continue;
    group.push(option);
  }
  return groups.filter((g) => g.length > 0).map((options) => ({ options }));
}

function parseCsv(csvPath) {
  const rows = parse(fs.readFileSync(csvPath, 'utf8'), { from_line: 2 });
  const byTarget = new Map();
  for (const row of rows) {
    const target = code(row[COL.targetSubject], row[COL.targetCatalog]);
    if (!byTarget.has(target)) byTarget.set(target, []);
    byTarget.get(target).push(row);
  }
  return [...byTarget].map(([courseCode, rs]) => {
    const groups = rowsToGroups(rs, courseCode);
    return { course_code: courseCode, groups, has_prerequisites: groups.length > 0 };
  });
}

/**
 * Folds cross-listed equivalents from the live document back into [course],
 * mutating it. Returns the live options that were NOT restored.
 *
 * The CSV names one department's copy of a cross-listed course and sets
 * `Incl Equiv = Y` to mean "the equivalents count too" — without ever saying
 * what they are. Taken literally, this upload would drop `ECE F211` from
 * `EEE F345`, `ECE F243` from five ECE courses, and so on, and the app would
 * tell those students they are blocked by a course they have already cleared.
 * The curated live data does name them, so keep any live option that shares a
 * catalog number with an option the CSV lists for the same course — the only
 * shape a cross-listing takes here (EEE/INSTR/ECE F211).
 *
 * Live options that match nothing are real removals by the official source and
 * are reported instead of kept.
 */
export function restoreCrossListings(course, live) {
  const number = (c) => c.split(' ')[1] ?? '';
  const present = new Set(course.groups.flatMap((g) => g.options.map((o) => o.course_code)));
  const dropped = [];
  for (const option of (live?.groups ?? []).flatMap((g) => g.options)) {
    if (present.has(option.course_code)) continue;
    const group = course.groups.find((g) =>
      g.options.some((o) => number(o.course_code) === number(option.course_code)),
    );
    if (!group) {
      dropped.push(option.course_code);
      continue;
    }
    // The CSV's type wins: the live catalogue is full of `nan`, which is
    // exactly the vagueness this upload exists to replace.
    group.options.push({ course_code: option.course_code, type: group.options[0].type });
    present.add(option.course_code);
  }
  return dropped;
}

function selfCheck() {
  // The real ECON C411 case: a leading AND, then three ORs inside parens.
  const row = (key, subj, cat, conn, typ = 'PRE') => {
    const r = new Array(27).fill('');
    r[COL.targetSubject] = 'ECON';
    r[COL.targetCatalog] = '    C411';
    r[COL.key] = key;
    r[COL.reqType] = typ;
    r[COL.prereqSubject] = subj;
    r[COL.prereqCatalog] = `    ${cat}`;
    r[COL.connector] = conn;
    return r;
  };

  // Four alternatives for one requirement, fed out of order to prove the sort.
  assert.deepStrictEqual(
    rowsToGroups(
      [
        row('0006', 'MBA', 'C416', 'OR'),
        row('0003', 'ECON', 'C481', 'AND'),
        row('0005', 'FIN', 'C342', 'OR'),
        row('0004', 'MGTS', 'C382', 'OR'),
      ],
      'ECON C411',
    ),
    [
      {
        options: [
          { course_code: 'ECON C481', type: 'pre' },
          { course_code: 'MGTS C382', type: 'pre' },
          { course_code: 'FIN C342', type: 'pre' },
          { course_code: 'MBA C416', type: 'pre' },
        ],
      },
    ],
  );

  // AND starts a new group; a co-requisite keeps its own type.
  assert.deepStrictEqual(
    rowsToGroups([row('0001', 'MATH', 'F111', ''), row('0002', 'PHY', 'F110', 'AND', 'CO')], 'ECON C411'),
    [
      { options: [{ course_code: 'MATH F111', type: 'pre' }] },
      { options: [{ course_code: 'PHY F110', type: 'co/pre' }] },
    ],
  );

  // A course is never its own prerequisite, and an emptied group disappears.
  assert.deepStrictEqual(
    rowsToGroups([row('0001', 'ECON', 'C411', ''), row('0002', 'CS', 'F111', 'AND')], 'ECON C411'),
    [{ options: [{ course_code: 'CS F111', type: 'pre' }] }],
  );

  // Duplicates within one group collapse.
  assert.deepStrictEqual(
    rowsToGroups([row('0001', 'CS', 'F111', ''), row('0002', 'CS', 'F111', 'OR')], 'ECON C411'),
    [{ options: [{ course_code: 'CS F111', type: 'pre' }] }],
  );

  // Cross-listings come back; an unrelated live option does not.
  const course = { groups: [{ options: [{ course_code: 'EEE F211', type: 'pre' }] }] };
  const dropped = restoreCrossListings(course, {
    groups: [
      { options: [{ course_code: 'ECE F211', type: 'nan' }, { course_code: 'MATH F112', type: 'nan' }] },
    ],
  });
  assert.deepStrictEqual(course.groups, [
    {
      options: [
        { course_code: 'EEE F211', type: 'pre' },
        { course_code: 'ECE F211', type: 'pre' },
      ],
    },
  ]);
  assert.deepStrictEqual(dropped, ['MATH F112']);

  console.log('self-check passed');
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--self-check')) return selfCheck();

  const commit = args.includes('--commit');
  const csvPath = args.find((a) => !a.startsWith('--'));
  if (!csvPath) throw new Error('usage: node upload-prerequisites.js <csv> [--commit]');

  const courses = parseCsv(csvPath);
  console.log(
    `Parsed ${courses.length} courses, ${courses.filter((c) => c.has_prerequisites).length} with prerequisites`,
  );

  dotenv.config({ path: path.join(__dirname, '..', '.env') });
  initializeApp({
    credential: cert({
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
    }),
  });
  const db = getFirestore();
  const prereqsRef = db.collection('reference').doc('prerequisites').collection('courses');

  // Diff against live before touching anything. This overwrites only the
  // courses the CSV covers; the rest of the collection is left alone, so the
  // report has to say what is about to change and what is being left behind.
  const existing = new Map(
    (await prereqsRef.get()).docs.map((d) => [d.id, d.data()]),
  );
  const summary = (c) =>
    JSON.stringify((c.groups ?? []).map((g) => g.options.map((o) => `${o.course_code}:${o.type}`)));

  const added = [];
  const changed = [];
  const removals = [];
  let unchanged = 0;
  for (const course of courses) {
    const live = existing.get(course.course_code.replace(/ /g, '_'));
    const dropped = restoreCrossListings(course, live);
    if (dropped.length) removals.push([course.course_code, dropped]);
    if (!live) added.push(course);
    else if (summary(live) !== summary(course)) changed.push([course, live]);
    else unchanged++;
  }

  console.log(`Requirement groups after cross-listing restore: ${courses.reduce((n, c) => n + c.groups.length, 0)}`);
  console.log(`\nNew documents: ${added.length}`);
  for (const c of added) console.log(`  + ${c.course_code}  ${summary(c)}`);
  console.log(`\nChanged: ${changed.length}`);
  for (const [c, live] of changed) console.log(`  ~ ${c.course_code}\n      live: ${summary(live)}\n      csv:  ${summary(c)}`);
  console.log(`\nIdentical: ${unchanged}`);

  // Not cross-listings — the official export genuinely does not list these.
  // Worth an eyeball before committing, since each one is a requirement a
  // student currently sees and will stop seeing.
  console.log(`\nLive options the CSV drops outright: ${removals.length} course(s)`);
  for (const [c, dropped] of removals) console.log(`  - ${c} loses ${dropped.join(', ')}`);

  const csvCodes = new Set(courses.map((c) => c.course_code.replace(/ /g, '_')));
  const orphans = [...existing].filter(([id, d]) => !csvCodes.has(id) && (d.groups?.length ?? 0) > 0);
  console.log(
    `\nLive courses with prerequisites the CSV does not cover: ${orphans.length} (left untouched)`,
  );
  for (const [id] of orphans.slice(0, 20)) console.log(`  · ${id.replace(/_/g, ' ')}`);
  if (orphans.length > 20) console.log(`  … and ${orphans.length - 20} more`);

  if (!commit) {
    console.log('\nDry run. Re-run with --commit to write.');
    return;
  }

  const BATCH = 450;
  for (let i = 0; i < courses.length; i += BATCH) {
    const batch = db.batch();
    for (const course of courses.slice(i, i + BATCH)) {
      batch.set(prereqsRef.doc(course.course_code.replace(/ /g, '_')), course);
    }
    await batch.commit();
    console.log(`Wrote ${Math.min(i + BATCH, courses.length)}/${courses.length}`);
  }

  // Freshness marker read by LocalCacheService — without this, every client
  // keeps serving its stale on-disk copy of the catalogue.
  await db
    .collection('reference')
    .doc('prerequisites')
    .set({ lastUpdated: new Date().toISOString() }, { merge: true });
  console.log('Done. Freshness marker bumped.');
}

// Only when run directly — this module is imported for its parser.
if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

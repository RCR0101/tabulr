 /**
 * Reconciles the official BITS ERP export against live Firestore, in one pass.
 *
 *   node audit-erp-export.js "~/Downloads/erp scraped"           # dry run (default)
 *   node audit-erp-export.js "~/Downloads/erp scraped" --apply   # writes the safe subset
 *   node audit-erp-export.js --self-check                        # asserts, no network
 *
 * Three sections, three source files:
 *
 *   credits   BITS_CRSE_CATALOG.csv  -> campuses/{id}/courses_master.credits
 *   titles    BITS_COURSE.csv        -> campuses/{id}/courses_master.title
 *   prereqs   BITS_PREREQ_LIST.csv   -> reference/prerequisites/courses
 *
 * `--apply` only ever writes changes this script can justify mechanically.
 * Everything judgement-dependent goes to `erp-review.csv` beside the inputs, to
 * be worked through in the courses-master admin screen. The two rules that
 * decide which is which are `creditVerdict` and `expandsAbbreviation`, and both
 * exist because the export disagrees with us far more often than it is right:
 *
 *   - 580 of 2,619 overlapping credit values are EXACTLY 3x ours. That is the
 *     ERP's higher-degree unit scale (career 0002, G-coded), not a disagreement,
 *     and it is not convertible either — 130 G-codes are already 1x. Taking the
 *     export at face value would triple the credits on every postgrad course.
 *   - The long-title column carries its own damage: `ENGGINEERING DESIGN`,
 *     `SSENTIALS OF STRATEGIC MANAGEMENT`, and `BITS F241` whose "long title" is
 *     a different course entirely (`PRACTICE SCHOOL I` vs `SYSTEMS ENGINEERING
 *     PRINCIPLES`). Longer is not better, so only provable expansions apply.
 *
 * Prerequisites are parsed by `upload-prerequisites.js` and committed through
 * its `writePrereqs`, so there is exactly one prerequisite writer.
 */
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { parse } from 'csv-parse/sync';
import fs from 'fs';
import os from 'os';
import path from 'path';
import assert from 'assert';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';
import { rowsToGroups, restoreCrossListings, writePrereqs } from './upload-prerequisites.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CAMPUSES = ['hyderabad', 'pilani', 'goa'];

// Firestore's hard document limit is 1MiB; same headroom as the uploader.
const MAX_BUNDLE_BYTES = 900 * 1024;

// `HSS F398` is exported as 300.00 units. Nothing at BITS is worth 300 units, so
// anything this far out is a broken row rather than a course we should believe.
const MAX_PLAUSIBLE_UNITS = 30;

const code = (subject, catalog) => `${subject.trim()} ${catalog.trim()}`;

/**
 * Drops non-ASCII bytes, replacing each with a space.
 *
 * Deliberately not NFKD folding: the mojibake in this export is orphaned UTF-8
 * (a bare U+00C2 where a non-breaking space was re-encoded), not an accent, so
 * folding would invent letters rather than recover them.
 */
const ascii = (s) =>
  (s || '')
    .split('')
    .map((ch) => (ch.charCodeAt(0) < 128 ? ch : ' '))
    .join('')
    .replace(/\s+/g, ' ')
    .trim();

/** Comparison form: case, `&`/`AND`, and punctuation carry no meaning here. */
const words = (title) =>
  ascii(title)
    .toUpperCase()
    .replace(/&/g, ' AND ')
    .replace(/[^A-Z0-9]+/g, ' ')
    .trim()
    .split(' ')
    .filter(Boolean);

const isSubsequence = (needle, haystack) => {
  let i = 0;
  for (const ch of haystack) if (ch === needle[i]) i++;
  return i === needle.length;
};

/**
 * Whether [long] is [short] with digits stuck on the end — `CONCEPTS` against the
 * export's `CONCEPTS2` (SCM G511), which is a data-entry slip and not a word
 * getting longer. A trailing numeral as its own word (`MATHEMATICS` ->
 * `MATHEMATICS I`) is a real title and is unaffected.
 */
const digitSuffixed = (short, long) => long.startsWith(short) && /^\d+$/.test(long.slice(short.length));

/**
 * Whether [long] is provably the same title as [short] with the truncations
 * undone — the only case where overwriting a live title is safe.
 *
 * Word by word, in order, each of ours must be either a prefix of theirs
 * (`SANITA` -> `SANITATION`) or a heavy contraction of it (`MGM` ->
 * `MANAGEMENT`). Contractions are only believed when ours is at most 60% of
 * their length, which is what keeps `ENGINEERING` from silently accepting
 * `ENGGINEERING` — a subsequence, but nobody's abbreviation.
 *
 * Their extra words are free — that is the point, dropped words come back — but
 * every word of ours has to find a home, and at least one has to actually grow
 * or there is no reason to write.
 *
 * ponytail: a misspelling inside a word we only hold contracted still passes,
 * because the contraction cannot see it — `MGMT` is a subsequence of the
 * export's `MANGEMENT` (BITS C419) as readily as of `MANAGEMENT` (BITS F419).
 * Catching that needs a spell check or a comparison against the same title on
 * another code, which is more machinery than one bad row a run deserves; the
 * expansions are printed so they can be skimmed.
 */
export function expandsAbbreviation(short, long) {
  const a = words(short);
  const b = words(long);
  // An empty live title is the admin screen's job: there is no abbreviation
  // here to expand, so there is nothing this rule can prove.
  if (a.length === 0) return false;
  let grew = false;
  let j = 0;
  for (const m of a) {
    while (j < b.length && !(b[j].startsWith(m) || (m.length <= b[j].length * 0.6 && m[0] === b[j][0] && isSubsequence(m, b[j])))) {
      // Their extra words are free; ours going unmatched is not.
      j++;
    }
    if (j === b.length) return false;
    if (digitSuffixed(m, b[j])) return false;
    if (b[j].length > m.length) grew = true;
    j++;
  }
  return grew || b.length > a.length;
}

/**
 * What to do about one credit disagreement.
 *
 * `fill`   - we hold 0/absent and the export has a trustworthy number: take it.
 * `scale`  - a multiple of a value we hold: an inflated unit scale, leave alone.
 * `review` - a genuine conflict for a human. ~12 of these are F-coded.
 * `ok`     - agreed, or the export has nothing usable.
 *
 * [peers] is what the *other* campuses hold for this code, and it is most of what
 * keeps the 0-credit case honest. Two real shapes it catches:
 *
 *   - `BIO U101` is 3 units on Hyderabad and 0 on Pilani and Goa while the export
 *     says 9. Judging each campus alone there is no 3x to notice and both zeroes
 *     get filled with the inflated figure.
 *   - `CHEM U101` is 2 on Hyderabad, 0 elsewhere, export 7 — not a clean multiple,
 *     but a sibling holding 2 still says plainly that 7 is wrong. All 16 U-coded
 *     rows are 0 on Pilani and Goa because that series is Hyderabad's first-year
 *     stream; those zeroes mean "not offered here", not "credit missing".
 *
 * [seriesTrusted] gates the last resort — filling a 0 no campus can corroborate —
 * on whether this export inflates the code's series at all, measured rather than
 * assumed. See `inflatedSeries`.
 */
export function creditVerdict(mine, theirs, peers = [], seriesTrusted = false) {
  if (!(theirs > 0) || theirs > MAX_PLAUSIBLE_UNITS) return 'ok';
  if (Math.abs(theirs - mine) < 0.001) return 'ok';
  if ([mine, ...peers].some((v) => v > 0 && Math.abs(theirs - v * 3) < 0.001)) return 'scale';
  if (mine > 0) return 'review';
  if (peers.some((v) => Math.abs(theirs - v) < 0.001)) return 'fill';
  // A sibling that holds a real value and disagrees outranks the export.
  if (peers.some((v) => v > 0)) return 'review';
  return seriesTrusted ? 'fill' : 'review';
}

/**
 * Code series (the letter in `CS F211`) whose units this export inflates, worked
 * out from every code where we and the export both hold a value.
 *
 * Measured instead of hardcoded because the inflation is not uniform and not
 * documented anywhere: `F` is clean across all 1,140 overlaps, `G` is inflated on
 * about four fifths of them, and `U` is inflated on its own irregular scale
 * (2->7, 3->10, 1->3). Hardcoding today's answer would quietly rot the first time
 * a re-scraped export changes which series it inflates.
 */
export function inflatedSeries(pairs) {
  const tally = new Map();
  for (const { code: c, mine, theirs } of pairs) {
    const letter = (c.split(' ')[1] ?? '')[0];
    if (!letter || !(mine > 0) || !(theirs > 0)) continue;
    if (!tally.has(letter)) tally.set(letter, { n: 0, inflated: 0 });
    const t = tally.get(letter);
    t.n++;
    if (theirs >= mine * 1.5) t.inflated++;
  }
  // 5% tolerates the odd genuine disagreement (`C` has 2 in 710) without
  // tolerating a series that is systematically on another scale.
  return { tally, inflated: new Set([...tally].filter(([, t]) => t.inflated / t.n > 0.05).map(([l]) => l)) };
}

function readCsv(dir, name) {
  const file = path.join(dir, name);
  if (!fs.existsSync(file)) throw new Error(`missing ${file}`);
  return parse(fs.readFileSync(file, 'utf8'), { from_line: 2, relax_column_count: true });
}

/** `BITS_CRSE_CATALOG.csv` -> code -> {units, careers}. Units repeat per component row. */
function parseCatalog(dir) {
  const out = new Map();
  for (const r of readCsv(dir, 'BITS_CRSE_CATALOG.csv')) {
    const key = code(r[1], r[2]);
    const entry = out.get(key) ?? { units: 0, careers: new Set() };
    entry.units = Math.max(entry.units, Number(r[4]) || 0);
    entry.careers.add(r[8]);
    out.set(key, entry);
  }
  return out;
}

/**
 * `BITS_COURSE.csv` -> code -> long title, newest effective date wins.
 *
 * Two thirds of the file is `WILPD` — the off-campus work-integrated
 * programmes, which share code space with us and would overwrite on-campus
 * titles with distance-learning ones. Only the `BITS` institution is us.
 * Col 3 is the long title and is blank on 20,114 of 23,079 rows; col 2 is the
 * same 30-character abbreviation we already store, so it is no use here.
 */
function parseLongTitles(dir) {
  const out = new Map();
  const stamp = (d) => {
    const [dd, mm, yyyy] = (d || '').split('/');
    return `${yyyy}${mm}${dd}`;
  };
  for (const r of readCsv(dir, 'BITS_COURSE.csv')) {
    if (r[4] !== 'BITS') continue;
    const long = ascii(r[3]);
    if (!long) continue;
    const key = code(r[5], r[6]);
    const prev = out.get(key);
    if (!prev || stamp(r[1]) >= prev.date) out.set(key, { title: long, date: stamp(r[1]) });
  }
  return new Map([...out].map(([k, v]) => [k, v.title]));
}

/** Same bundle + freshness write the admin screen and the uploader both do. */
async function writeCampus(db, campusId, rows, edits) {
  const collection = db.collection(`campuses/${campusId}/courses_master`);
  const batch = db.batch();
  for (const edit of edits) {
    // Written by the doc id the row actually has. Deriving it locally is what
    // broke hyphenated codes before: the uploader wrote `BITS_F101_2` while the
    // Dart client derives `BITS_F101-2`.
    batch.set(collection.doc(edit.docId), { ...edit.fields, updated_at: new Date().toISOString() }, { merge: true });
  }
  await batch.commit();

  const entries = rows
    .map((r) => ({ course_code: r.course_code, title: r.title, credits: r.credits, type: r.type || 'Normal' }))
    .sort((a, b) => a.course_code.localeCompare(b.course_code));
  const entriesJson = JSON.stringify(entries);
  const bytes = Buffer.byteLength(entriesJson, 'utf8');
  if (bytes > MAX_BUNDLE_BYTES) throw new Error(`${campusId}: bundle ${(bytes / 1024).toFixed(1)}KB over budget`);

  const at = new Date();
  await db.doc(`campuses/${campusId}/catalog/courses_master`).set({
    version: at.toISOString(),
    count: entries.length,
    entriesJson,
  });
  // Clients only re-read the catalogue when campus metadata says it is newer.
  // Merged, because this document also holds totalCourses/campus/parserVersion.
  await db
    .doc(`campuses/${campusId}/metadata/current`)
    .set({ lastUpdated: at.toISOString(), version: String(at.getTime()) }, { merge: true });
  console.log(`  ${campusId}: ${edits.length} row(s) written, bundle ${(bytes / 1024).toFixed(1)} KB, metadata bumped`);
}

function selfCheck() {
  // Real rows from the export. Truncations that should apply:
  assert.ok(expandsAbbreviation('Water,Sanita & Solid Waste Mgm', 'WATER SANITATION AND SOLID WASTE MANAGEMENT'));
  assert.ok(expandsAbbreviation('RECOMBINANT DNA TECH', 'RECOMBINANT DNA TECHNOLOGY'));
  assert.ok(expandsAbbreviation('MOLECULAR BIO OF CELL', 'MOLECULAR BIOLOGY OF THE CELL'));
  assert.ok(expandsAbbreviation('INTRO TO PLANT BIOTECH', 'INTRODUCTION TO PLANT BIOTECHNOLOGY'));

  // A different course wearing the same code — the BITS F241 trap.
  assert.ok(!expandsAbbreviation('PRACTICE SCHOOL I', 'SYSTEMS ENGINEERING PRINCIPLES'));
  // Typos in their column, which are longer but not expansions.
  assert.ok(!expandsAbbreviation('ENGINEERING DESIGN AND PROTOTYPE', 'ENGGINEERING DESIGN AND PROTOTYPE'));
  assert.ok(!expandsAbbreviation('ESSENTIALS OF STRATE MGT', 'SSENTIALS OF STRATEGIC MANAGEMENT'));
  // SCM G511: a digit stuck on the end of a word is a slip, not an expansion...
  assert.ok(!expandsAbbreviation('FUNDAMENTALS OF SUPPLY CHAIN – CONCEPTS', 'FUNDAMENTALS OF SUPPLY CHAIN CONCEPTS2'));
  // ...while a numeral of its own is part of the real title.
  assert.ok(expandsAbbreviation('GENERAL MATHEMATICS', 'GENERAL MATHEMATICS I'));
  assert.ok(expandsAbbreviation('MODERN EXPERIMENTAL TECH - I', 'MODERN EXPERIMENTAL TECHNIQUES I'));
  // Equal once `&` and the mojibake are normalised: nothing to write.
  assert.ok(!expandsAbbreviation('APPLIED NUTRITION & NUTRACEUTICALS', 'Applied Nutrition and NutraceuticalsÂ'));
  // Losing a word is never an expansion.
  assert.ok(!expandsAbbreviation('QUANTUM INFORMATION AND COMPUTATION', 'QUANTUM INFORMATION'));
  // An empty live title proves nothing either way; leave it to the admin screen.
  assert.ok(!expandsAbbreviation('', 'PRINCIPLES OF ECONOMICS'));

  const trusted = true;
  const suspect = false;
  assert.strictEqual(creditVerdict(3, 3, [], trusted), 'ok');
  assert.strictEqual(creditVerdict(5, 15, [], trusted), 'scale', 'BITS G513: the 3x higher-degree scale');
  assert.strictEqual(creditVerdict(3, 4, [], trusted), 'review', 'ME F324: a real conflict');
  assert.strictEqual(creditVerdict(0, 3, [], trusted), 'fill', 'EEE F438: 0 everywhere, clean series');
  assert.strictEqual(creditVerdict(0, 3, [], suspect), 'review', 'PHY U110: 0 everywhere, but U runs inflated');
  assert.strictEqual(creditVerdict(0, 9, [3], trusted), 'scale', 'BIO U101: Hyderabad holds 3, so 9 is the scale');
  assert.strictEqual(creditVerdict(0, 7, [2], trusted), 'review', 'CHEM U101: not a multiple, but a sibling still says no');
  assert.strictEqual(creditVerdict(0, 3, [3], suspect), 'fill', 'a sibling campus already agrees with the export');
  assert.strictEqual(creditVerdict(0, 0, [], trusted), 'ok', 'MUSIC N303T is genuinely 0');
  assert.strictEqual(creditVerdict(3, 300, [], trusted), 'ok', 'HSS F398: 300 units is a broken row');

  // One clean series, one on another scale, one borderline that stays trusted.
  const pairs = [
    ...Array.from({ length: 20 }, (_, i) => ({ code: `CS F${i}`, mine: 3, theirs: 3 })),
    ...Array.from({ length: 20 }, (_, i) => ({ code: `CS G${i}`, mine: 3, theirs: 9 })),
    // Three ordinary `ME F324`-shaped conflicts (3 against 4). Higher, but
    // nowhere near another unit scale, so the series stays trusted.
    ...Array.from({ length: 17 }, (_, i) => ({ code: `CS C${i}`, mine: 3, theirs: 3 })),
    ...Array.from({ length: 3 }, (_, i) => ({ code: `CS C9${i}`, mine: 3, theirs: 4 })),
    // No value on one side proves nothing about the scale and must not count.
    { code: 'CS F99', mine: 0, theirs: 12 },
  ];
  const { tally, inflated } = inflatedSeries(pairs);
  assert.deepStrictEqual([...inflated], ['G']);
  assert.strictEqual(tally.get('F').n, 20, 'the 0-credit row is excluded from the tally');

  console.log('self-check passed');
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--self-check')) return selfCheck();
  const apply = args.includes('--apply');
  const raw = args.find((a) => !a.startsWith('--'));
  if (!raw) throw new Error('usage: node audit-erp-export.js <export-dir> [--apply]');
  const dir = raw.startsWith('~') ? path.join(os.homedir(), raw.slice(1)) : raw;

  const catalog = parseCatalog(dir);
  const longTitles = parseLongTitles(dir);
  const prereqs = (() => {
    const byTarget = new Map();
    for (const r of readCsv(dir, 'BITS_PREREQ_LIST.csv')) {
      const target = code(r[1], r[2]);
      if (!byTarget.has(target)) byTarget.set(target, []);
      byTarget.get(target).push(r);
    }
    return [...byTarget].map(([course_code, rs]) => {
      const groups = rowsToGroups(rs, course_code);
      return { course_code, groups, has_prerequisites: groups.length > 0 };
    });
  })();
  console.log(
    `Export: ${catalog.size} catalogue codes, ${longTitles.size} long titles, ${prereqs.length} courses with requisites\n`,
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

  const review = [['section', 'campus', 'course_code', 'field', 'live', 'export', 'note']];
  const plan = new Map();

  // ── credits + titles, per campus ─────────────────────────────────────────
  //
  // Per campus and never mirrored across them: the catalogues have genuinely
  // drifted (2852/2854/2857 rows) and some of that is deliberate curation, so a
  // campus only gets a row rewritten when that campus's own value is the wrong
  // one. All three are read before any of them is judged, though, because a
  // sibling campus's credit value is the only way to spot the 3x scale on a row
  // where our own value is 0 — see `creditVerdict`.
  for (const campusId of CAMPUSES) {
    // Read the collection, not the bundle, so every write goes to the doc id
    // that exists rather than one re-derived from the code.
    const snap = await db.collection(`campuses/${campusId}/courses_master`).get();
    plan.set(campusId, { rows: snap.docs.map((d) => ({ docId: d.id, ...d.data() })), edits: [] });
  }

  // Two documents for one course code means the catalogue answers "how many
  // credits" twice. Not fixed here — choosing which of the two to keep is a
  // judgement call, and this script only writes changes it can justify — but it
  // is reported because nothing else looks for it. The cause is the two
  // disagreeing doc-id conventions: `courseCodeToDocId` replaces spaces only,
  // the bulk uploader replaces every non-alphanumeric, and they part company on
  // exactly the hyphenated codes.
  for (const [campusId, { rows }] of plan) {
    const byCode = new Map();
    for (const row of rows) {
      if (!byCode.has(row.course_code)) byCode.set(row.course_code, []);
      byCode.get(row.course_code).push(row);
    }
    for (const [dupCode, dups] of [...byCode].filter(([, v]) => v.length > 1)) {
      const shown = dups.map((d) => `${d.docId}: ${d.credits} credits, ${JSON.stringify(d.title)}`).join('  vs  ');
      console.log(`  ${campusId} holds ${dupCode} twice — ${shown}`);
      review.push(['duplicate', campusId, dupCode, 'document', shown, '', 'same course code under both doc-id conventions; delete the wrong one in the admin screen']);
    }
  }

  // course code -> every non-zero credit value any campus holds for it.
  const liveCredits = new Map();
  for (const { rows } of plan.values()) {
    for (const row of rows) {
      const credits = Number(row.credits) || 0;
      if (credits <= 0) continue;
      if (!liveCredits.has(row.course_code)) liveCredits.set(row.course_code, []);
      liveCredits.get(row.course_code).push(credits);
    }
  }

  const { tally, inflated } = inflatedSeries(
    [...plan.values()].flatMap(({ rows }) =>
      rows.map((r) => ({ code: r.course_code, mine: Number(r.credits) || 0, theirs: catalog.get(r.course_code)?.units ?? 0 })),
    ),
  );
  console.log(
    'Unit scale by code series (share of agreed-code overlaps where the export runs high):\n  ' +
      [...tally]
        .sort()
        .map(([l, t]) => `${l} ${((t.inflated / t.n) * 100).toFixed(0)}% of ${t.n}${inflated.has(l) ? ' INFLATED' : ''}`)
        .join('   '),
  );
  console.log('  Series marked INFLATED never have a 0 credit filled from this export unless a campus corroborates it.\n');

  for (const [campusId, entryPlan] of plan) {
    const { rows, edits } = entryPlan;
    const counts = { fill: 0, scale: 0, reviewCredits: 0, title: 0, reviewTitle: 0 };

    for (const row of rows) {
      const key = row.course_code;
      const fields = {};

      const entry = catalog.get(key);
      if (entry) {
        const mine = Number(row.credits) || 0;
        const peers = (liveCredits.get(key) ?? []).filter((v) => v !== mine);
        const verdict = creditVerdict(mine, entry.units, peers, !inflated.has((key.split(' ')[1] ?? '')[0]));
        if (verdict === 'fill') {
          fields.credits = entry.units;
          counts.fill++;
        } else if (verdict === 'scale') {
          counts.scale++;
        } else if (verdict === 'review') {
          counts.reviewCredits++;
          review.push([
            'credits', campusId, key, 'credits', mine, entry.units,
            `careers ${[...entry.careers].join('/')} — export disagrees, not a 3x scale artifact`,
          ]);
        }
      }

      const long = longTitles.get(key);
      if (long && long !== row.title) {
        if (expandsAbbreviation(row.title ?? '', long)) {
          fields.title = long;
          counts.title++;
        } else if (words(long).join(' ') !== words(row.title ?? '').join(' ')) {
          counts.reviewTitle++;
          review.push(['titles', campusId, key, 'title', row.title ?? '', long, 'not a provable expansion — read both before choosing']);
        }
      }

      if (Object.keys(fields).length) {
        // `was` is only for the report; `row` is mutated so the rebuilt bundle
        // carries the same values as the documents.
        edits.push({ docId: row.docId, fields, was: { credits: row.credits, title: row.title } });
        Object.assign(row, fields);
      }
    }

    console.log(
      `${campusId}: ${rows.length} rows | credits: ${counts.fill} fill, ${counts.scale} 3x-scale ignored, ` +
      `${counts.reviewCredits} to review | titles: ${counts.title} expand, ${counts.reviewTitle} to review`,
    );
    // Every pending change is listed, never a sample: a dry run exists to be
    // read before it is authorised, and a change hidden behind "and N more" is a
    // change nobody approved. Pipe through a pager or a file if it is long.
    const codeOf = (e) => rows.find((r) => r.docId === e.docId).course_code;
    for (const e of edits.filter((e) => 'credits' in e.fields)) {
      console.log(`    credits  ${codeOf(e)}  ${e.was.credits ?? 0} -> ${e.fields.credits}`);
    }
    for (const e of edits.filter((e) => 'title' in e.fields)) {
      console.log(`    title    ${codeOf(e)}  ${JSON.stringify(e.was.title)} -> ${JSON.stringify(e.fields.title)}`);
    }
  }

  const missing = [...catalog.keys()].filter(
    (k) => !plan.get('hyderabad').rows.some((r) => r.course_code === k),
  );
  console.log(`\nExport codes absent from the Hyderabad catalogue: ${missing.length} (not added, listed so the claim can be checked)`);
  console.log(missing.sort().map((c) => `  · ${c}`).join('\n'));

  // ── prerequisites ────────────────────────────────────────────────────────
  const existing = new Map(
    (await db.collection('reference').doc('prerequisites').collection('courses').get()).docs.map((d) => [d.id, d.data()]),
  );
  const summary = (c) =>
    JSON.stringify((c.groups ?? []).map((g) => g.options.map((o) => `${o.course_code}:${o.type}`)));

  let prereqAdded = 0;
  let prereqChanged = 0;
  let prereqSame = 0;
  for (const course of prereqs) {
    const live = existing.get(course.course_code.replace(/ /g, '_'));
    const dropped = restoreCrossListings(course, live);
    for (const lost of dropped) {
      review.push(['prereqs', 'all', course.course_code, 'prerequisite', lost, '(removed)', 'export does not list it and it is not a cross-listing — a requirement students will stop seeing']);
    }
    if (!live) {
      prereqAdded++;
    } else if (summary(live) !== summary(course)) {
      prereqChanged++;
      review.push(['prereqs', 'all', course.course_code, 'groups', summary(live), summary(course), 'export differs from live — applied, listed so it can be checked']);
    } else {
      prereqSame++;
    }
  }
  const nanLeft = [...existing].filter(
    ([id, d]) =>
      !prereqs.some((c) => c.course_code.replace(/ /g, '_') === id) &&
      (d.groups ?? []).some((g) => g.options.some((o) => o.type === 'nan')),
  );
  console.log(
    `\nPrerequisites: ${prereqAdded} new, ${prereqChanged} changed, ${prereqSame} identical | ` +
    `${nanLeft.length} live course(s) keep an untyped 'nan' requirement the export does not cover`,
  );

  // Printed in full as well as written, for the same reason the edits are: the
  // CSV is the better place to sort and filter them, but a run should never
  // require opening another file to find out what it found.
  const [header, ...rows] = review;
  console.log(`\nTo review — not written by --apply (${rows.length} row(s)):`);
  for (const section of [...new Set(rows.map((r) => r[0]))]) {
    const inSection = rows.filter((r) => r[0] === section);
    console.log(`\n  ${section} (${inSection.length}):`);
    for (const [, campus, courseCode, , live, exported, note] of inSection) {
      console.log(`    ${campus.padEnd(10)} ${courseCode.padEnd(12)} ${JSON.stringify(live)} vs export ${JSON.stringify(exported)}  — ${note}`);
    }
  }

  const reviewPath = path.join(dir, 'erp-review.csv');
  fs.writeFileSync(reviewPath, [header, ...rows].map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n'));
  console.log(`\nSame list as a spreadsheet: ${reviewPath}`);
  console.log('Work through it in the courses-master admin screen.');

  if (!apply) {
    console.log('\nDry run. Re-run with --apply to write.');
    return;
  }

  console.log('\nApplying:');
  for (const [campusId, { rows, edits }] of plan) {
    if (!edits.length) {
      console.log(`  ${campusId}: nothing to write`);
      continue;
    }
    await writeCampus(db, campusId, rows, edits);
  }
  await writePrereqs(db, prereqs);
  console.log('Done.');
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

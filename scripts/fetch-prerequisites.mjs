/**
 * fetch-prerequisites.js — Dumps the live prerequisite catalogue out of Firestore.
 *
 * Reads `reference/prerequisites/courses/{DOC_ID}` (doc id = course code with
 * spaces replaced by underscores, e.g. `CS F211` → `CS_F211`).
 *
 * Uses `listDocuments()` + `getAll()` rather than a collection `get()`:
 * `get()` only returns materialised documents, while `listDocuments()` also
 * surfaces *phantom* documents — ids that exist purely as parents of a
 * subcollection, or that were left behind by a partial delete. Those show up
 * here with `__missing__: true` so they can be spotted and cleaned up instead
 * of silently vanishing from the dump.
 *
 * Usage:
 *   node fetch-prerequisites.js                       # dump to prereqs-live.json
 *   node fetch-prerequisites.js --out path/to.json    # custom output path
 *   node fetch-prerequisites.js --stdout              # print JSON, write nothing
 */

import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ---------------------------------------------------------------------------
// Auth — service account key file if present, otherwise the FIREBASE_* env vars
// ---------------------------------------------------------------------------

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

const PREREQS_PATH = ['reference', 'prerequisites', 'courses'];
const GET_ALL_CHUNK = 300; // getAll() takes a bounded number of refs per call

const args = process.argv.slice(2);
const STDOUT_ONLY = args.includes('--stdout');
const outIdx = args.indexOf('--out');
const OUT_PATH = outIdx !== -1
  ? path.resolve(args[outIdx + 1])
  : path.join(__dirname, 'prereqs-live.json');

const prereqsRef = db
  .collection(PREREQS_PATH[0])
  .doc(PREREQS_PATH[1])
  .collection(PREREQS_PATH[2]);

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function main() {
  const refs = await prereqsRef.listDocuments();
  console.error(`listDocuments(): ${refs.length} document ids under ${PREREQS_PATH.join('/')}`);

  const docs = [];
  for (const batch of chunk(refs, GET_ALL_CHUNK)) {
    const snaps = await db.getAll(...batch);
    docs.push(...snaps);
  }

  const records = [];
  const phantoms = [];

  for (const snap of docs) {
    if (!snap.exists) {
      // Listed but not materialised — a phantom id. Report it with any
      // subcollections it is holding open, then move on.
      const subs = await snap.ref.listCollections();
      phantoms.push({ id: snap.id, subcollections: subs.map((c) => c.id) });
      records.push({ __docId: snap.id, __missing__: true });
      continue;
    }
    records.push({ __docId: snap.id, ...snap.data() });
  }

  records.sort((a, b) => a.__docId.localeCompare(b.__docId));

  // Shape summary — the reader tolerates both the grouped and the legacy shape,
  // so it matters which one is actually in prod.
  const grouped = records.filter((r) => Array.isArray(r.groups)).length;
  const legacy = records.filter((r) => !r.__missing__ && !Array.isArray(r.groups) && Array.isArray(r.prereqs)).length;
  const neither = records.filter((r) => !r.__missing__ && !Array.isArray(r.groups) && !Array.isArray(r.prereqs)).length;
  const withPrereqs = records.filter((r) => r.has_prerequisites === true).length;

  console.error('---');
  console.error(`total ids        : ${records.length}`);
  console.error(`materialised     : ${records.length - phantoms.length}`);
  console.error(`phantom ids      : ${phantoms.length}`);
  console.error(`grouped shape    : ${grouped}`);
  console.error(`legacy shape     : ${legacy}`);
  console.error(`neither shape    : ${neither}`);
  console.error(`has_prerequisites: ${withPrereqs}`);
  if (phantoms.length) {
    console.error('--- phantom ids ---');
    for (const p of phantoms) {
      console.error(`  ${p.id}${p.subcollections.length ? `  (subcollections: ${p.subcollections.join(', ')})` : ''}`);
    }
  }

  const payload = JSON.stringify(records, null, 2);
  if (STDOUT_ONLY) {
    process.stdout.write(payload);
  } else {
    fs.writeFileSync(OUT_PATH, payload);
    console.error(`\nWrote ${records.length} records to ${OUT_PATH}`);
  }

  process.exit(0);
}

main().catch((err) => { console.error(err); process.exit(1); });

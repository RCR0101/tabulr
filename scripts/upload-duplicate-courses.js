import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '..', '.env') });

const serviceAccount = {
  type: "service_account",
  project_id: process.env.FIREBASE_PROJECT_ID,
  private_key_id: process.env.FIREBASE_PRIVATE_KEY_ID,
  private_key: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  client_email: process.env.FIREBASE_CLIENT_EMAIL,
  client_id: process.env.FIREBASE_CLIENT_ID,
  auth_uri: process.env.FIREBASE_AUTH_URI,
  token_uri: process.env.FIREBASE_TOKEN_URI,
  auth_provider_x509_cert_url: process.env.FIREBASE_AUTH_PROVIDER_X509_CERT_URL,
  client_x509_cert_url: process.env.FIREBASE_CLIENT_X509_CERT_URL
};

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const EQUIV_GROUPS = [
  new Set(['ECE', 'EEE', 'INSTR']),
  new Set(['CS', 'IS', 'MAC']),
  new Set(['HSS', 'HUM']),
];

function canonical(prefix) {
  for (const group of EQUIV_GROUPS) {
    if (group.has(prefix)) {
      return [...group].sort()[0];
    }
  }
  return prefix;
}

function getPrefix(code) {
  return code.substring(0, code.lastIndexOf(' '));
}

async function uploadDuplicateCourses() {
  const rawPath = path.join(__dirname, '..', '..', 'duplicate_courses.json');
  const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8'));

  // Filter: group codes by canonical prefix within each course name,
  // only keep groups with 2+ codes
  const filtered = {};
  for (const [name, codes] of Object.entries(raw)) {
    const groups = {};
    for (const code of codes) {
      const key = canonical(getPrefix(code));
      if (!groups[key]) groups[key] = [];
      groups[key].push(code);
    }
    const kept = [];
    for (const groupCodes of Object.values(groups)) {
      if (groupCodes.length >= 2) {
        kept.push(...groupCodes);
      }
    }
    if (kept.length >= 2) {
      filtered[name] = kept;
    }
  }

  console.log(`Filtered: ${Object.keys(filtered).length} entries (from ${Object.keys(raw).length} original)`);

  // Build reverse map: course_code -> list of duplicate codes (same-prefix group only)
  const codeMap = {};
  for (const [name, codes] of Object.entries(filtered)) {
    // Re-group by canonical prefix to build per-group duplicates
    const groups = {};
    for (const code of codes) {
      const key = canonical(getPrefix(code));
      if (!groups[key]) groups[key] = [];
      groups[key].push(code);
    }
    for (const groupCodes of Object.values(groups)) {
      if (groupCodes.length >= 2) {
        for (const code of groupCodes) {
          codeMap[code] = groupCodes.filter(c => c !== code);
        }
      }
    }
  }

  console.log(`Code map: ${Object.keys(codeMap).length} course codes with duplicates`);

  // Upload as a single document (well within Firestore 1MB doc limit)
  const ref = db.collection('reference').doc('duplicate_courses');
  await ref.set({
    codeMap,
    lastUpdated: new Date().toISOString(),
    version: '1.0.0',
  });

  console.log('Uploaded to reference/duplicate_courses');

  // Show a few examples
  const examples = Object.entries(codeMap).slice(0, 6);
  for (const [code, dupes] of examples) {
    console.log(`  ${code} -> ${dupes.join(', ')}`);
  }
}

uploadDuplicateCourses().catch(console.error);

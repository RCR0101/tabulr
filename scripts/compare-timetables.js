import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const serviceAccount = {
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

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

function deepEqual(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return a == b;
  if (typeof a !== typeof b) return false;
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    return a.every((v, i) => deepEqual(v, b[i]));
  }
  if (typeof a === 'object') {
    const keysA = Object.keys(a).sort();
    const keysB = Object.keys(b).sort();
    if (keysA.length !== keysB.length) return false;
    return keysA.every((k, i) => k === keysB[i] && deepEqual(a[k], b[k]));
  }
  return false;
}

async function compare() {
  const campuses = process.argv[2] ? [process.argv[2]] : ['hyderabad', 'pilani', 'goa'];

  for (const campus of campuses) {
    console.log(`\n=== ${campus.toUpperCase()} ===`);
    const liveSnap = await db.collection(`campuses/${campus}/timetable`).get();
    const safeSnap = await db.collection(`safety/${campus}/timetable`).get();

    const liveMap = new Map();
    liveSnap.forEach(d => liveMap.set(d.id, d.data()));
    const safeMap = new Map();
    safeSnap.forEach(d => safeMap.set(d.id, d.data()));

    const allIds = new Set([...liveMap.keys(), ...safeMap.keys()]);
    let added = 0, removed = 0, changed = 0, same = 0;
    const diffs = [];

    for (const id of allIds) {
      const live = liveMap.get(id);
      const safe = safeMap.get(id);
      if (!safe) { added++; diffs.push(`+ ${id} (new)`); continue; }
      if (!live) { removed++; diffs.push(`- ${id} (removed)`); continue; }
      if (deepEqual(live, safe)) { same++; continue; }
      changed++;
      const changes = [];
      const lSec = (live.sections || []).length;
      const sSec = (safe.sections || []).length;
      if (lSec !== sSec) changes.push(`sections: ${sSec} -> ${lSec}`);
      if (!deepEqual(live.mid_sem_exam, safe.mid_sem_exam)) changes.push('mid_sem_exam');
      if (!deepEqual(live.end_sem_exam, safe.end_sem_exam)) changes.push('end_sem_exam');
      if (live.lecture_credits !== safe.lecture_credits) changes.push(`lec_credits: ${safe.lecture_credits} -> ${live.lecture_credits}`);
      if (live.practical_credits !== safe.practical_credits) changes.push(`prac_credits: ${safe.practical_credits} -> ${live.practical_credits}`);
      if (!changes.length && !deepEqual(live.sections, safe.sections)) changes.push('section data');
      diffs.push(`~ ${id}: ${changes.join(', ') || 'data differs'}`);
    }

    console.log(`Live: ${liveMap.size} | Safety: ${safeMap.size}`);
    console.log(`Same: ${same} | Changed: ${changed} | Added: ${added} | Removed: ${removed}`);
    if (diffs.length > 0) {
      console.log('Changes:');
      diffs.forEach(d => console.log(`  ${d}`));
    } else {
      console.log('No differences found.');
    }
  }
}

compare().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });

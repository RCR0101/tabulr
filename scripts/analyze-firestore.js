/**
 * analyze-firestore.js — Dump Firestore collection structure and sample data.
 *
 * Outputs: doc counts, all field names with types, sample values, document IDs,
 * and subcollection contents. Pure data dump — no analysis or recommendations.
 *
 * Usage:
 *   node scripts/analyze-firestore.js
 *   node scripts/analyze-firestore.js --collection cgpa
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

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

const ALL_COLLECTIONS = [
  'all_courses',
  'cgpa',
  'course_announcements',
  'course_guide',
  'courses',
  'discipline_electives',
  'exam-seating-user',
  'files',
  'goa-courses',
  'huel_guide',
  'hyd-courses',
  'hyd-exam-seating',
  'metadata',
  'metadataAcad',
  'pilani-courses',
  'prerequisites',
  'professors',
  'submissions',
  'tags',
  'timetable_metadata',
  'user-settings',
  'user_timetables',
];

// Subcollections to probe (parent collection -> list of subcollection names to check)
const SUBCOLLECTIONS_TO_PROBE = {
  user_timetables: ['timetables'],
  cgpa: ['semesters'],
  course_announcements: ['votes', 'flags', 'verifications'],
  'exam-seating-user': ['preferences'],
};

function getType(value) {
  if (value === null || value === undefined) return 'null';
  if (value._seconds !== undefined && value._nanoseconds !== undefined) return 'timestamp';
  if (value.latitude !== undefined && value.longitude !== undefined) return 'geopoint';
  if (Array.isArray(value)) {
    if (value.length === 0) return 'array(empty)';
    const innerType = getType(value[0]);
    return `array(${innerType})`;
  }
  if (typeof value === 'object') {
    if (value._path !== undefined || (value.path !== undefined && value.id !== undefined && value.firestore !== undefined)) {
      return 'reference';
    }
    return 'map';
  }
  return typeof value;
}

function truncate(value, maxLen = 120) {
  if (value === null || value === undefined) return 'null';
  if (value._seconds !== undefined) {
    return new Date(value._seconds * 1000).toISOString();
  }
  if (Array.isArray(value)) {
    const str = JSON.stringify(value);
    return str.length > maxLen ? str.slice(0, maxLen) + '...' : str;
  }
  if (typeof value === 'object') {
    const str = JSON.stringify(value);
    return str.length > maxLen ? str.slice(0, maxLen) + '...' : str;
  }
  const str = String(value);
  return str.length > maxLen ? str.slice(0, maxLen) + '...' : str;
}

async function dumpCollection(collectionName) {
  const ref = db.collection(collectionName);

  // Get total count
  const countSnap = await ref.count().get();
  const totalDocs = countSnap.data().count;

  // Get sample docs (up to 10 for field analysis, 3 full dumps)
  const snapshot = await ref.limit(10).get();
  const docs = snapshot.docs;

  console.log(`\n${'═'.repeat(70)}`);
  console.log(`COLLECTION: ${collectionName}`);
  console.log(`Total documents: ${totalDocs}`);
  console.log(`${'─'.repeat(70)}`);

  if (docs.length === 0) {
    console.log('  (empty collection)');
    return;
  }

  // Document IDs
  console.log(`\nDocument IDs (first ${docs.length}):`);
  for (const doc of docs) {
    console.log(`  - "${doc.id}"`);
  }

  // Build unified field map across all sampled docs
  const fieldMap = {}; // field -> { types: Set, values: [] }
  for (const doc of docs) {
    const data = doc.data();
    for (const [key, value] of Object.entries(data)) {
      if (!fieldMap[key]) fieldMap[key] = { types: new Set(), values: [], presentIn: 0 };
      fieldMap[key].types.add(getType(value));
      fieldMap[key].presentIn++;
      if (fieldMap[key].values.length < 3) {
        fieldMap[key].values.push(truncate(value));
      }
    }
  }

  // Print fields
  console.log(`\nFields (across ${docs.length} sampled docs):`);
  for (const [field, info] of Object.entries(fieldMap)) {
    const types = [...info.types].join(' | ');
    const presence = info.presentIn === docs.length ? 'all' : `${info.presentIn}/${docs.length}`;
    console.log(`  ${field}`);
    console.log(`    type: ${types}  |  present in: ${presence}`);
    console.log(`    samples: ${info.values.slice(0, 2).join('  |||  ')}`);
  }

  // Full dump of first 3 docs
  console.log(`\nFull document samples:`);
  for (const doc of docs.slice(0, 3)) {
    console.log(`\n  [doc: "${doc.id}"]`);
    const data = doc.data();
    for (const [key, value] of Object.entries(data)) {
      console.log(`    ${key}: ${truncate(value, 200)}`);
    }
  }

  // Probe subcollections
  const subsToCheck = SUBCOLLECTIONS_TO_PROBE[collectionName];
  if (subsToCheck && docs.length > 0) {
    console.log(`\nSubcollections (probing on first 2 parent docs):`);
    for (const parentDoc of docs.slice(0, 2)) {
      for (const subName of subsToCheck) {
        const subRef = parentDoc.ref.collection(subName);
        const subCount = await subRef.count().get();
        const count = subCount.data().count;
        if (count > 0) {
          console.log(`\n  [${collectionName}/"${parentDoc.id}"/${subName}] — ${count} docs`);
          const subSnap = await subRef.limit(3).get();
          for (const subDoc of subSnap.docs) {
            console.log(`    [subdoc: "${subDoc.id}"]`);
            const subData = subDoc.data();
            for (const [key, value] of Object.entries(subData)) {
              console.log(`      ${key}: ${truncate(value, 150)}`);
            }
          }
        } else {
          console.log(`  [${collectionName}/"${parentDoc.id}"/${subName}] — empty`);
        }
      }
    }
  }

  // Also try to auto-discover subcollections on first doc via listCollections
  if (docs.length > 0) {
    const discoveredSubs = await docs[0].ref.listCollections();
    if (discoveredSubs.length > 0) {
      const subNames = discoveredSubs.map((s) => s.id);
      const alreadyProbed = subsToCheck || [];
      const newSubs = subNames.filter((s) => !alreadyProbed.includes(s));
      if (newSubs.length > 0) {
        console.log(`\n  Discovered subcollections on "${docs[0].id}": ${subNames.join(', ')}`);
        for (const subName of newSubs) {
          const subRef = docs[0].ref.collection(subName);
          const subCount = await subRef.count().get();
          const count = subCount.data().count;
          console.log(`  [${collectionName}/"${docs[0].id}"/${subName}] — ${count} docs`);
          if (count > 0) {
            const subSnap = await subRef.limit(2).get();
            for (const subDoc of subSnap.docs) {
              console.log(`    [subdoc: "${subDoc.id}"]`);
              const subData = subDoc.data();
              for (const [key, value] of Object.entries(subData)) {
                console.log(`      ${key}: ${truncate(value, 150)}`);
              }
            }
          }
        }
      }
    }
  }
}

async function main() {
  const args = process.argv.slice(2);
  const singleIdx = args.indexOf('--collection');
  const collectionsToAnalyze =
    singleIdx !== -1 && args[singleIdx + 1]
      ? [args[singleIdx + 1]]
      : ALL_COLLECTIONS;

  console.log('FIRESTORE DATA DUMP');
  console.log(`Project: ${process.env.FIREBASE_PROJECT_ID}`);
  console.log(`Date: ${new Date().toISOString()}`);
  console.log(`Collections to dump: ${collectionsToAnalyze.length}`);

  for (const collection of collectionsToAnalyze) {
    try {
      await dumpCollection(collection);
    } catch (err) {
      console.log(`\n${'═'.repeat(70)}`);
      console.log(`COLLECTION: ${collection}`);
      console.log(`  ERROR: ${err.message}`);
    }
  }

  console.log(`\n${'═'.repeat(70)}`);
  console.log('DUMP COMPLETE');
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});

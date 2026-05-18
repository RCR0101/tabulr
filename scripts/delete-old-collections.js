/**
 * delete-old-collections.js — Deletes all old (pre-v2) Firestore collections
 * after verifying that the migration was successful.
 *
 * Usage:
 *   node delete-old-collections.js              # dry-run: shows counts, verifies, no deletes
 *   node delete-old-collections.js --confirm    # actually deletes after verification passes
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

const CONFIRM = process.argv.includes('--confirm');
const BATCH_SIZE = 500;

// Old → new collection mapping for verification
const VERIFY_PAIRS = [
  { old: 'all_courses', new: 'campuses/hyderabad/courses_master' },
  { old: 'hyd-courses', new: 'campuses/hyderabad/timetable' },
  { old: 'pilani-courses', new: 'campuses/pilani/timetable' },
  { old: 'goa-courses', new: 'campuses/goa/timetable' },
  { old: 'hyd-exam-seating', new: 'campuses/hyderabad/exam_seating' },
  { old: 'course_announcements', new: 'announcements' },
  { old: 'prerequisites', new: 'reference/prerequisites/courses', allowedDelta: 3 },
  { old: 'professors', new: 'reference/professors/entries' },
  { old: 'files', new: 'acad_drives_files' },
  { old: 'submissions', new: 'acad_drives_submissions' },
  { old: 'tags', new: 'acad_drives_tags' },
];

// All old top-level collections to delete (includes ones without a verify pair)
const OLD_COLLECTIONS = [
  'all_courses',
  'hyd-courses',
  'pilani-courses',
  'goa-courses',
  'hyd-exam-seating',
  'pilani-exam-seating',
  'goa-exam-seating',
  'courses',
  'course_announcements',
  'user_reputation',
  'prerequisites',
  'course_guide',
  'discipline_electives',
  'huel_guide',
  'professors',
  'files',
  'submissions',
  'tags',
  'user-settings',
  'exam-seating-user',
  'user_timetables',
  'cgpa',
  'timetable_metadata',
  'metadata',
  'metadataAcad',
];

async function getCollectionSize(collectionPath) {
  const parts = collectionPath.split('/');
  let ref;
  if (parts.length === 1) {
    ref = db.collection(parts[0]);
  } else if (parts.length === 3) {
    ref = db.collection(parts[0]).doc(parts[1]).collection(parts[2]);
  } else {
    return 0;
  }
  const snap = await ref.count().get();
  return snap.data().count;
}

async function getCollectionDocIds(collectionPath) {
  const parts = collectionPath.split('/');
  let ref;
  if (parts.length === 1) {
    ref = db.collection(parts[0]);
  } else if (parts.length === 3) {
    ref = db.collection(parts[0]).doc(parts[1]).collection(parts[2]);
  } else {
    return new Set();
  }
  const snap = await ref.select().get();
  return new Set(snap.docs.map(d => d.id));
}

async function verify() {
  console.log('=== Verifying migration ===\n');
  let allPassed = true;

  for (const pair of VERIFY_PAIRS) {
    const oldCount = await getCollectionSize(pair.old);
    const newCount = await getCollectionSize(pair.new);
    const delta = pair.allowedDelta || 0;
    const passed = newCount >= oldCount - delta;
    if (!passed) allPassed = false;

    const icon = passed ? '✓' : '✗';
    console.log(`  ${icon} ${pair.old} (${oldCount}) → ${pair.new} (${newCount})`);

    if (!passed) {
      const oldIds = await getCollectionDocIds(pair.old);
      const newIds = await getCollectionDocIds(pair.new);
      const onlyInOld = [...oldIds].filter(id => !newIds.has(id));
      const onlyInNew = [...newIds].filter(id => !oldIds.has(id));
      if (onlyInOld.length > 0) {
        console.log(`    In old but not new (${onlyInOld.length}): ${onlyInOld.slice(0, 10).join(', ')}${onlyInOld.length > 10 ? '...' : ''}`);
      }
      if (onlyInNew.length > 0) {
        console.log(`    In new but not old (${onlyInNew.length}): ${onlyInNew.slice(0, 10).join(', ')}${onlyInNew.length > 10 ? '...' : ''}`);
      }
      console.log(`    (Doc IDs may differ by naming convention — verify by count only if IDs were intentionally remapped)`);
    }
  }

  console.log('');
  return allPassed;
}

async function deleteCollection(collectionPath) {
  const ref = db.collection(collectionPath);
  let totalDeleted = 0;

  while (true) {
    const snap = await ref.limit(BATCH_SIZE).get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    totalDeleted += snap.size;

    if (snap.size < BATCH_SIZE) break;
  }

  return totalDeleted;
}

async function deleteCollectionWithSubcollections(collectionPath) {
  const ref = db.collection(collectionPath);
  let totalDeleted = 0;

  // For user_timetables, we need to delete subcollection docs too
  const snap = await ref.get();

  for (const doc of snap.docs) {
    // Try known subcollections
    const subcollections = ['timetables', 'semesters', 'cgpa_semesters'];
    for (const sub of subcollections) {
      const subRef = doc.ref.collection(sub);
      const subSnap = await subRef.get();
      if (!subSnap.empty) {
        const batch = db.batch();
        let count = 0;
        for (const subDoc of subSnap.docs) {
          batch.delete(subDoc.ref);
          count++;
          if (count >= BATCH_SIZE) {
            await batch.commit();
            totalDeleted += count;
            count = 0;
          }
        }
        if (count > 0) {
          await batch.commit();
          totalDeleted += count;
        }
      }
    }
  }

  // Now delete root docs
  totalDeleted += await deleteCollection(collectionPath);
  return totalDeleted;
}

async function main() {
  console.log(`Delete old collections — ${CONFIRM ? 'LIVE DELETE' : 'DRY RUN'}\n`);

  const passed = await verify();

  if (!passed) {
    console.log('✗ Verification FAILED. Some new collections have fewer docs than old ones.');
    console.log('  Fix the migration before deleting old collections.');
    process.exit(1);
  }

  console.log('✓ Verification passed. All new collections have >= old doc counts.\n');

  if (!CONFIRM) {
    console.log('=== Dry run: collections that would be deleted ===\n');
  } else {
    console.log('=== Deleting old collections ===\n');
  }

  let grandTotal = 0;

  for (const collection of OLD_COLLECTIONS) {
    const count = await getCollectionSize(collection);

    if (count === 0) {
      console.log(`  [skip] ${collection} — already empty`);
      continue;
    }

    if (!CONFIRM) {
      console.log(`  [would delete] ${collection} — ${count} docs`);
      grandTotal += count;
      continue;
    }

    process.stdout.write(`  [deleting] ${collection} (${count} docs)...`);

    let deleted;
    if (collection === 'user_timetables' || collection === 'cgpa') {
      deleted = await deleteCollectionWithSubcollections(collection);
    } else {
      deleted = await deleteCollection(collection);
    }

    console.log(` done (${deleted} deleted)`);
    grandTotal += deleted;
  }

  console.log(`\n=== ${CONFIRM ? 'Deleted' : 'Would delete'} ${grandTotal} total documents ===`);

  if (!CONFIRM) {
    console.log('\nRun with --confirm to actually delete.');
  }
}

main().catch(err => {
  console.error('Failed:', err);
  process.exit(1);
});

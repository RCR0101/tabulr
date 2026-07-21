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

const CAMPUSES = ['pilani', 'goa', 'hyderabad'];

// Firestore's hard document limit is 1MiB; leave headroom.
const MAX_BUNDLE_BYTES = 900 * 1024;

function sanitize(s) {
  return (s || '').replace(/[\n\r]/g, ' ').replace(/\s+/g, ' ').trim();
}

/**
 * Writes the single-document catalogue bundle the app reads on cold start.
 *
 * Without this the client would have to read every courses_master document
 * (~2.8k per campus) on each load. Built from the same in-memory `courses`
 * array we just uploaded, so it costs no extra reads.
 */
async function writeCatalogBundle(campusId, courses) {
  const entries = courses
    .map((c) => ({
      // Keys must match CourseMasterEntry.fromMap in the Dart client.
      course_code: c.course_code,
      title: c.title,
      credits: typeof c.credits === 'number' ? c.credits : Number(c.credits) || 0,
      type: c.type || 'Normal',
    }))
    .sort((a, b) => a.course_code.localeCompare(b.course_code));

  const entriesJson = JSON.stringify(entries);
  const bytes = Buffer.byteLength(entriesJson, 'utf8');
  if (bytes > MAX_BUNDLE_BYTES) {
    throw new Error(
      `${campusId}: bundle is ${(bytes / 1024).toFixed(1)}KB, over the ` +
      `${MAX_BUNDLE_BYTES / 1024}KB single-document budget — needs chunking`
    );
  }

  const stamp = new Date();
  await db.doc(`campuses/${campusId}/catalog/courses_master`).set({
    version: stamp.toISOString(),
    count: entries.length,
    entriesJson,
  });

  // Clients cache the catalogue locally and only re-read when the campus
  // metadata says it's newer. Without this bump they'd serve the stale bundle
  // until their 72h TTL expired.
  await db.doc(`campuses/${campusId}/metadata/current`).set(
    { lastUpdated: stamp.toISOString(), version: String(stamp.getTime()) },
    { merge: true }
  );

  console.log(
    `  Bundle written: ${entries.length} entries, ${(bytes / 1024).toFixed(1)} KB` +
    ` (+ metadata bumped so clients refresh)`
  );
}

async function clearCollection(collectionRef) {
  const snapshot = await collectionRef.get();
  if (snapshot.empty) return 0;

  let deleted = 0;
  const batchSize = 450;

  for (let i = 0; i < snapshot.docs.length; i += batchSize) {
    const batch = db.batch();
    const chunk = snapshot.docs.slice(i, i + batchSize);
    chunk.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    deleted += chunk.length;
  }
  return deleted;
}

async function uploadForCampus(campusId, courses) {
  console.log(`\nUploading to campus: ${campusId}`);
  const masterRef = db.collection(`campuses/${campusId}/courses_master`);

  const deleted = await clearCollection(masterRef);
  console.log(`  Cleared ${deleted} existing documents`);

  let batchCount = 0;
  let currentBatch = db.batch();
  let opCount = 0;
  let totalDocs = 0;

  for (const course of courses) {
    const docId = course.course_code.replace(/[^a-zA-Z0-9]/g, '_');
    const docRef = masterRef.doc(docId);

    currentBatch.set(docRef, {
      course_code: course.course_code,
      title: course.title,
      credits: course.credits,
      type: course.type,
      updated_at: new Date().toISOString(),
    });
    opCount++;
    totalDocs++;

    if (opCount >= 450) {
      await currentBatch.commit();
      batchCount++;
      console.log(`  Batch ${batchCount} committed (${opCount} ops)`);
      currentBatch = db.batch();
      opCount = 0;
    }
  }

  if (opCount > 0) {
    await currentBatch.commit();
    batchCount++;
    console.log(`  Final batch committed (${opCount} ops)`);
  }

  console.log(`  ${campusId}: ${totalDocs} courses uploaded`);

  await writeCatalogBundle(campusId, courses);
}

async function uploadCoursesMaster() {
  console.log('Starting courses_master upload...');

  const dataPath = path.join(__dirname, '..', '..', 'courses_final.json');
  if (!fs.existsSync(dataPath)) throw new Error('courses_final.json not found at ' + dataPath);

  const rawData = JSON.parse(fs.readFileSync(dataPath, 'utf8'));

  // Flatten: top-level key is department prefix, nested entries have code suffix
  const courses = [];
  for (const [prefix, entries] of Object.entries(rawData)) {
    for (const entry of entries) {
      const courseCode = `${prefix} ${entry.code}`;
      const type = entry.type === 'ATC' ? 'ATC' : 'Normal';
      courses.push({
        course_code: sanitize(courseCode),
        title: sanitize(entry.title),
        credits: entry.units || 0,
        type,
      });
    }
  }

  console.log(`Parsed ${courses.length} courses from courses_final.json`);

  for (const campus of CAMPUSES) {
    await uploadForCampus(campus, courses);
  }

  console.log(`\nUpload complete: ${courses.length} courses to ${CAMPUSES.length} campuses`);
}

async function main() {
  try {
    await uploadCoursesMaster();
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

process.on('SIGINT', () => { console.log('\nInterrupted'); process.exit(1); });
main().catch(console.error);

/**
 * migrate-to-v2.js — Migrates Firestore data from flat collections to the new
 * hierarchical campus-parameterized layout with courses_master as single source of truth.
 *
 * Usage:
 *   node migrate-to-v2.js                    # full migration
 *   node migrate-to-v2.js --dry-run          # read + log, no writes
 *   node migrate-to-v2.js --dry-run --report # show sample transforms
 *   node migrate-to-v2.js --verify           # compare old vs new doc counts
 *   node migrate-to-v2.js --step a           # run only step a
 *   node migrate-to-v2.js --scratch          # nuke all new collections then re-run migration
 *   node migrate-to-v2.js --scratch --step e # nuke then run only step e
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp, FieldPath } from 'firebase-admin/firestore';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// ─── Firebase init ──────────────────────────────────────────────────────────

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

// ─── CLI flags ──────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const REPORT = args.includes('--report');
const VERIFY = args.includes('--verify');
const SCRATCH = args.includes('--scratch');
const NO_E = args.includes('--no-e');
const stepIdx = args.indexOf('--step');
const ONLY_STEP = stepIdx !== -1 ? args[stepIdx + 1] : null;

// ─── Transformation helpers ─────────────────────────────────────────────────

function sanitizeString(str) {
  if (typeof str !== 'string') return str;
  return str.replace(/[\n\r]/g, ' ').replace(/\s+/g, ' ').trim();
}

function sanitizeAllStrings(obj) {
  if (obj === null || obj === undefined) return obj;
  if (typeof obj === 'string') return sanitizeString(obj);
  if (Array.isArray(obj)) return obj.map(sanitizeAllStrings);
  if (obj instanceof Timestamp) return obj;
  if (typeof obj === 'object' && obj.constructor === Object) {
    const result = {};
    for (const [k, v] of Object.entries(obj)) {
      result[k] = sanitizeAllStrings(v);
    }
    return result;
  }
  return obj;
}

function stripKeys(obj, keys) {
  if (obj === null || obj === undefined || typeof obj !== 'object') return;
  if (Array.isArray(obj)) {
    for (const item of obj) stripKeys(item, keys);
    return;
  }
  for (const key of keys) delete obj[key];
  for (const val of Object.values(obj)) {
    if (val && typeof val === 'object') stripKeys(val, keys);
  }
}

function primaryCourseCode(code) {
  const sanitized = sanitizeString(code);
  return sanitized.includes('/') ? sanitized.split('/')[0].trim() : sanitized;
}

function courseCodeToDocId(code) {
  return primaryCourseCode(code).replace(/\s+/g, '_');
}

function toTimestamp(val) {
  if (!val) return null;
  if (val instanceof Timestamp) return val;
  if (val._seconds !== undefined) return new Timestamp(val._seconds, val._nanoseconds || 0);
  if (typeof val === 'string') {
    const d = new Date(val);
    if (!isNaN(d.getTime())) return Timestamp.fromDate(d);
  }
  if (val instanceof Date) return Timestamp.fromDate(val);
  return null;
}

function extractCourseCode(prereqName) {
  if (!prereqName) return null;
  const match = prereqName.match(/^([A-Z]+\s[A-Z]\d{3})/);
  return match ? match[1] : sanitizeString(prereqName);
}

function stripEnumPrefix(val) {
  if (typeof val !== 'string') return val;
  const dotIdx = val.lastIndexOf('.');
  if (dotIdx === -1) return val;
  const stripped = val.substring(dotIdx + 1);
  return stripped.replace(/([A-Z])/g, (m, c, i) => i > 0 ? `_${c.toLowerCase()}` : c.toLowerCase());
}

function deriveNewUid(email) {
  if (!email || typeof email !== 'string') return null;
  const atIdx = email.indexOf('@');
  if (atIdx === -1) return email + '_NOTUIDEMAIL';
  const username = email.substring(0, atIdx);
  const domain = email.substring(atIdx + 1).toLowerCase();

  if (domain === 'hyderabad.bits-pilani.ac.in') return username + 'H';
  if (domain === 'pilani.bits-pilani.ac.in') return username + 'P';
  if (domain === 'goa.bits-pilani.ac.in') return username + 'G';
  if (domain === 'dubai.bits-pilani.ac.in') return username + 'D';
  return username + '_NOTUIDEMAIL';
}

// ─── Batch writer ───────────────────────────────────────────────────────────

const BATCH_SIZE = 500;

class BatchWriter {
  constructor(label, batchSize = BATCH_SIZE) {
    this.label = label;
    this.batchSize = batchSize;
    this.batch = db.batch();
    this.count = 0;
    this.total = 0;
    this.sanitized = 0;
    this.rekeyed = 0;
  }

  set(ref, data) {
    if (DRY_RUN) {
      this.total++;
      return;
    }
    this.batch.set(ref, data);
    this.count++;
    this.total++;
    if (this.count >= this.batchSize) {
      return this.flush();
    }
    return Promise.resolve();
  }

  async flush() {
    if (this.count > 0 && !DRY_RUN) {
      await this.batch.commit();
      this.batch = db.batch();
      this.count = 0;
    }
  }

  log() {
    console.log(`[${this.label}] migrated ${this.total} docs (${this.sanitized} sanitized, ${this.rekeyed} re-keyed)`);
  }
}

// ─── UID Mapping ────────────────────────────────────────────────────────────

const uidMap = new Map(); // oldDocId → newUid

async function buildUidMap() {
  console.log('[uid-map] Building UID mapping from user_timetables...');


  let totalDocs = 0;
  let noSubcollCount = 0;
  let noEmailCount = 0;
  let mapped = 0;

  // listDocuments() returns ALL doc refs including "phantom" parents (docs that
  // only exist because a subcollection was created under them)
  const allDocRefs = await db.collection('user_timetables').listDocuments();
  totalDocs = allDocRefs.length;
  console.log(`[uid-map] listDocuments() returned ${totalDocs} doc refs`);

  for (const docRef of allDocRefs) {
    const oldUid = docRef.id;
    const timetablesSnap = await db.collection('user_timetables').doc(oldUid)
      .collection('timetables').limit(1).get();

    if (timetablesSnap.empty) {
      noSubcollCount++;
      continue;
    }

    const firstTimetable = timetablesSnap.docs[0].data();
    const email = firstTimetable.userEmail;

    if (!email || typeof email !== 'string') {
      noEmailCount++;
      uidMap.set(oldUid, oldUid + '_NOTUIDEMAIL');
      continue;
    }

    const newUid = deriveNewUid(email);
    uidMap.set(oldUid, newUid || oldUid + '_NOTUIDEMAIL');
    mapped++;
  }

  console.log(`[uid-map] Done: ${totalDocs} doc refs, ${mapped} mapped, ${noSubcollCount} no subcoll, ${noEmailCount} no email`);
}

function getNewUid(oldDocId) {
  return uidMap.get(oldDocId) || oldDocId + '_NOTUIDEMAIL';
}

// ─── Scratch: nuke all new collections ─────────────────────────────────────

async function nukeCollection(collectionPath) {
  const parts = collectionPath.split('/');
  let ref;
  if (parts.length === 1) {
    ref = db.collection(parts[0]);
  } else if (parts.length === 3) {
    ref = db.collection(parts[0]).doc(parts[1]).collection(parts[2]);
  } else {
    return 0;
  }

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

async function nukeUsersCollection() {
  let totalDeleted = 0;
  const subsToNuke = NO_E
    ? ['exam_seating_prefs', 'settings', 'cgpa_semesters']
    : ['timetables', 'exam_seating_prefs', 'settings', 'cgpa_semesters'];

  const allDocRefs = await db.collection('users').listDocuments();
  for (const docRef of allDocRefs) {
    for (const sub of subsToNuke) {
      const subSnap = await docRef.collection(sub).limit(BATCH_SIZE).get();
      if (!subSnap.empty) {
        const batch = db.batch();
        for (const subDoc of subSnap.docs) {
          batch.delete(subDoc.ref);
          totalDeleted++;
        }
        await batch.commit();
      }
    }
    // Only delete the user root doc if we're nuking everything
    if (!NO_E) {
      await docRef.delete();
      totalDeleted++;
    }
  }
  if (NO_E) console.log('  [skip] users/*/timetables — --no-e flag set');
  return totalDeleted;
}

async function scratchAll() {
  console.log('\n=== SCRATCH: Deleting all new collections ===\n');

  const collections = [
    'campuses/hyderabad/courses_master',
    'campuses/hyderabad/timetable',
    'campuses/hyderabad/exam_seating',
    'campuses/hyderabad/metadata',
    'campuses/pilani/courses_master',
    'campuses/pilani/timetable',
    'campuses/pilani/exam_seating',
    'campuses/pilani/metadata',
    'campuses/goa/courses_master',
    'campuses/goa/timetable',
    'campuses/goa/exam_seating',
    'campuses/goa/metadata',
    'announcements',
    'reference/prerequisites/courses',
    'reference/course_guide/semesters',
    'reference/course_guide/metadata',
    'reference/discipline_electives/branches',
    'reference/discipline_electives/metadata',
    'reference/huel_guide/courses',
    'reference/huel_guide/metadata',
    'reference/professors/entries',
    'acad_drives_files',
    'acad_drives_submissions',
    'acad_drives_tags',
    'admin_metadata',
    'reputation',
  ];

  for (const col of collections) {
    const deleted = await nukeCollection(col);
    if (deleted > 0) {
      console.log(`  [nuked] ${col} — ${deleted} docs`);
    }
  }

  const usersDeleted = await nukeUsersCollection();
  if (usersDeleted > 0) {
    console.log(`  [nuked] users (recursive) — ${usersDeleted} docs`);
  }

  console.log('\n=== Scratch complete ===\n');
}

// ─── Step A: Build courses_master per campus ────────────────────────────────

async function stepA() {
  console.log('\n=== Step A: Build courses_master ===');

  // Hyderabad: start from all_courses
  const allCoursesSnap = await db.collection('all_courses').get();
  const hydWriter = new BatchWriter('campuses/hyderabad/courses_master');
  const hydCodes = new Set();

  for (const doc of allCoursesSnap.docs) {
    const data = doc.data();
    const rawCode = sanitizeString(data.course_code || doc.id.replace(/_/g, ' '));
    const code = primaryCourseCode(rawCode);
    const docId = courseCodeToDocId(rawCode);
    hydCodes.add(code);

    const newDoc = {
      course_code: code,
      title: sanitizeString(data.course_title || ''),
      credits: parseInt(data.u, 10) || 0,
      type: data.type || 'Normal',
    };

    hydWriter.sanitized++;
    if (REPORT && hydWriter.total < 3) {
      console.log(`  [sample] ${doc.id} → ${docId}:`, JSON.stringify(newDoc));
    }

    const ref = db.collection('campuses').doc('hyderabad').collection('courses_master').doc(docId);
    await hydWriter.set(ref, newDoc);
  }

  // Fill gaps from hyd-courses
  const hydCoursesSnap = await db.collection('hyd-courses').get();
  for (const doc of hydCoursesSnap.docs) {
    const data = doc.data();
    const rawCode = sanitizeString(data.courseCode || doc.id.replace(/_/g, ' '));
    const code = primaryCourseCode(rawCode);
    if (hydCodes.has(code)) continue;
    hydCodes.add(code);

    const docId = courseCodeToDocId(rawCode);
    const newDoc = {
      course_code: code,
      title: sanitizeString(data.courseTitle || ''),
      credits: parseInt(data.totalCredits, 10) || 0,
      type: 'Normal',
    };

    hydWriter.sanitized++;
    const ref = db.collection('campuses').doc('hyderabad').collection('courses_master').doc(docId);
    await hydWriter.set(ref, newDoc);
  }

  await hydWriter.flush();
  hydWriter.log();

  // Pilani
  const pilaniWriter = new BatchWriter('campuses/pilani/courses_master');
  const pilaniSnap = await db.collection('pilani-courses').get();
  for (const doc of pilaniSnap.docs) {
    const data = doc.data();
    const rawCode = sanitizeString(data.courseCode || doc.id.replace(/_/g, ' '));
    const code = primaryCourseCode(rawCode);
    const docId = courseCodeToDocId(rawCode);

    const newDoc = {
      course_code: code,
      title: sanitizeString(data.courseTitle || ''),
      credits: parseInt(data.totalCredits, 10) || 0,
      type: 'Normal',
    };

    pilaniWriter.sanitized++;
    if (REPORT && pilaniWriter.total < 3) {
      console.log(`  [sample] ${doc.id} → ${docId}:`, JSON.stringify(newDoc));
    }

    const ref = db.collection('campuses').doc('pilani').collection('courses_master').doc(docId);
    await pilaniWriter.set(ref, newDoc);
  }
  await pilaniWriter.flush();
  pilaniWriter.log();

  // Goa
  const goaWriter = new BatchWriter('campuses/goa/courses_master');
  const goaSnap = await db.collection('goa-courses').get();
  for (const doc of goaSnap.docs) {
    const data = doc.data();
    const rawCode = sanitizeString(data.courseCode || doc.id.replace(/_/g, ' '));
    const code = primaryCourseCode(rawCode);
    const docId = courseCodeToDocId(rawCode);

    const newDoc = {
      course_code: code,
      title: sanitizeString(data.courseTitle || ''),
      credits: parseInt(data.totalCredits, 10) || 0,
      type: 'Normal',
    };

    goaWriter.sanitized++;
    const ref = db.collection('campuses').doc('goa').collection('courses_master').doc(docId);
    await goaWriter.set(ref, newDoc);
  }
  await goaWriter.flush();
  goaWriter.log();
}

// ─── Step B: Write timetable per campus ─────────────────────────────────────

async function stepB() {
  console.log('\n=== Step B: Write timetable ===');

  const campuses = [
    { id: 'hyderabad', old: 'hyd-courses' },
    { id: 'pilani', old: 'pilani-courses' },
    { id: 'goa', old: 'goa-courses' },
  ];

  for (const campus of campuses) {
    const writer = new BatchWriter(`campuses/${campus.id}/timetable`);
    const snap = await db.collection(campus.old).get();

    for (const doc of snap.docs) {
      const data = doc.data();
      const rawCode = sanitizeString(data.courseCode || doc.id.replace(/_/g, ' '));
      const docId = courseCodeToDocId(rawCode);

      const sections = (data.sections || []).map(s => sanitizeAllStrings(s));

      const newDoc = {
        sections,
        mid_sem_exam: sanitizeAllStrings(data.midSemExam || null),
        end_sem_exam: sanitizeAllStrings(data.endSemExam || null),
        lecture_credits: parseInt(data.lectureCredits, 10) || 0,
        practical_credits: parseInt(data.practicalCredits, 10) || 0,
      };

      writer.sanitized++;
      if (REPORT && writer.total < 3) {
        console.log(`  [sample] ${campus.id}/${doc.id} → ${docId}:`, JSON.stringify(newDoc).substring(0, 200));
      }

      const ref = db.collection('campuses').doc(campus.id).collection('timetable').doc(docId);
      await writer.set(ref, newDoc);
    }
    await writer.flush();
    writer.log();
  }
}

// ─── Step C: Write exam_seating ─────────────────────────────────────────────

async function stepC() {
  console.log('\n=== Step C: Write exam_seating ===');

  const campuses = [
    { id: 'hyderabad', old: 'hyd-exam-seating' },
    { id: 'pilani', old: 'pilani-exam-seating' },
    { id: 'goa', old: 'goa-exam-seating' },
  ];

  for (const campus of campuses) {
    const writer = new BatchWriter(`campuses/${campus.id}/exam_seating`);
    let snap;
    try {
      snap = await db.collection(campus.old).get();
    } catch (e) {
      console.log(`  [skip] ${campus.old} does not exist or is empty`);
      continue;
    }

    if (snap.empty) {
      console.log(`  [skip] ${campus.old} is empty`);
      continue;
    }

    for (const doc of snap.docs) {
      const data = doc.data();
      const rawCode = sanitizeString(data.courseCode || doc.id.replace(/_/g, ' '));

      const rawExamDate = data.examDate || data.exam_date || '';
      const examDate = (rawExamDate instanceof Timestamp) ? rawExamDate
        : (rawExamDate && typeof rawExamDate === 'string') ? sanitizeString(rawExamDate)
        : null;

      const newDoc = {
        exam_date: examDate,
        rooms: sanitizeAllStrings(data.rooms || []),
      };

      // Write a doc for each course code in slash-separated codes
      const codes = rawCode.includes('/') ? rawCode.split('/').map(c => c.trim()) : [rawCode];
      for (const code of codes) {
        const docId = code.replace(/\s+/g, '_');
        writer.sanitized++;
        if (REPORT && writer.total < 3) {
          console.log(`  [sample] ${campus.id}/${doc.id} → ${docId}:`, JSON.stringify(newDoc).substring(0, 200));
        }

        const ref = db.collection('campuses').doc(campus.id).collection('exam_seating').doc(docId);
        await writer.set(ref, newDoc);
      }
    }
    await writer.flush();
    writer.log();
  }
}

// ─── Step D: Write campus metadata ──────────────────────────────────────────

async function stepD() {
  console.log('\n=== Step D: Write campus metadata ===');

  const mappings = [
    { old: 'timetable_metadata/current-hyderabad', newPath: 'campuses/hyderabad/metadata/current' },
    { old: 'timetable_metadata/current-pilani', newPath: 'campuses/pilani/metadata/current' },
    { old: 'timetable_metadata/current-goa', newPath: 'campuses/goa/metadata/current' },
  ];

  for (const m of mappings) {
    const [col, docId] = m.old.split('/');
    const oldDoc = await db.collection(col).doc(docId).get();
    if (!oldDoc.exists) {
      console.log(`  [skip] ${m.old} does not exist`);
      continue;
    }

    const data = sanitizeAllStrings(oldDoc.data());

    if (DRY_RUN) {
      console.log(`  [dry-run] ${m.old} → ${m.newPath}`);
      if (REPORT) console.log(`    data:`, JSON.stringify(data).substring(0, 200));
      continue;
    }

    const [c1, d1, c2, d2] = m.newPath.split('/');
    await db.collection(c1).doc(d1).collection(c2).doc(d2).set(data);
    console.log(`  [done] ${m.old} → ${m.newPath}`);
  }
}

// ─── Step E: Write user data ────────────────────────────────────────────────

async function stepE() {
  console.log('\n=== Step E: Write user data ===');

  await buildUidMap();

  // E1: user_timetables → users/{newUid}/timetables/{tid}
  if (NO_E) {
    console.log('  [E1] Skipped (--no-e flag)');
  } else {
  // Only migrates users who have at least one timetable in the subcollection.
  console.log('  [E1] Migrating user timetables...');
  const timetableWriter = new BatchWriter('users/*/timetables', 20);
  let usersProcessed = 0;
  let usersSkipped = 0;

  const allUserDocRefs = await db.collection('user_timetables').listDocuments();
  console.log(`  [E1] user_timetables listDocuments() returned ${allUserDocRefs.length} doc refs`);

  for (const docRef of allUserDocRefs) {
    const oldUid = docRef.id;
    const newUid = getNewUid(oldUid);
    const subSnap = await db.collection('user_timetables').doc(oldUid)
      .collection('timetables').get();

    if (subSnap.empty) {
      usersSkipped++;
      continue;
    }

    for (const tDoc of subSnap.docs) {
      const data = sanitizeAllStrings(tDoc.data());
      stripKeys(data, ['availableCourses', 'userEmail']);

      if (REPORT && timetableWriter.total < 3) {
        console.log(`    [sample] ${oldUid}/${tDoc.id} → ${newUid}/${tDoc.id}`);
      }

      const ref = db.collection('users').doc(newUid).collection('timetables').doc(tDoc.id);
      await timetableWriter.set(ref, data);
    }

    timetableWriter.rekeyed++;
    usersProcessed++;
  }

  await timetableWriter.flush();
  console.log(`  [E1] Total: ${usersProcessed} users migrated, ${usersSkipped} skipped (empty timetables subcollection)`);
  timetableWriter.log();
  } // end NO_E else

  // E2: cgpa/{uid}/semesters/* → users/{newUid}/cgpa_semesters/*
  console.log('  [E2] Migrating CGPA data...');
  const cgpaWriter = new BatchWriter('users/*/cgpa_semesters', 20);
  let cgpaUsersProcessed = 0;
  let cgpaUsersSkipped = 0;

  const cgpaDocRefs = await db.collection('cgpa').listDocuments();
  console.log(`  [E2] cgpa listDocuments() returned ${cgpaDocRefs.length} doc refs`);

  for (const docRef of cgpaDocRefs) {
    const oldUid = docRef.id;
    const newUid = getNewUid(oldUid);
    const semSnap = await db.collection('cgpa').doc(oldUid).collection('semesters').get();

    if (semSnap.empty) {
      cgpaUsersSkipped++;
      continue;
    }

    for (const semDoc of semSnap.docs) {
      const data = sanitizeAllStrings(semDoc.data());
      const ref = db.collection('users').doc(newUid).collection('cgpa_semesters').doc(semDoc.id);
      await cgpaWriter.set(ref, data);
    }

    cgpaUsersProcessed++;
  }

  await cgpaWriter.flush();
  console.log(`  [E2] Total: ${cgpaUsersProcessed} users migrated, ${cgpaUsersSkipped} skipped (no semesters)`);
  cgpaWriter.log();

  // E3: exam-seating-user → users/{newUid}/exam_seating_prefs/data
  console.log('  [E3] Migrating exam seating user prefs...');
  const examUserWriter = new BatchWriter('users/*/exam_seating_prefs');
  const examUserSnap = await db.collection('exam-seating-user').get();

  for (const doc of examUserSnap.docs) {
    const oldUid = doc.id;
    const newUid = getNewUid(oldUid);
    const data = doc.data();

    // Sanitize selectedCourseCodes (strip newlines from codes)
    const newData = {};
    for (const [k, v] of Object.entries(data)) {
      if (k === 'selectedCourseCodes' && Array.isArray(v)) {
        newData.selected_course_codes = v.map(c => sanitizeString(c));
      } else {
        newData[k] = sanitizeAllStrings(v);
      }
    }
    delete newData.userId;

    examUserWriter.rekeyed++;
    const ref = db.collection('users').doc(newUid).collection('exam_seating_prefs').doc('data');
    await examUserWriter.set(ref, newData);
  }
  await examUserWriter.flush();
  examUserWriter.log();

  // E4: user-settings — SKIPPED (no reliable UID mapping without timetable email)
  console.log('  [E4] User settings — skipped (no UID mapping source)');
  // Settings will be recreated fresh when users log in with the new app.
}

// ─── Step F: Write announcements ────────────────────────────────────────────

async function stepF() {
  console.log('\n=== Step F: Write announcements ===');

  const writer = new BatchWriter('announcements');
  const snap = await db.collection('course_announcements').get();

  for (const doc of snap.docs) {
    const data = sanitizeAllStrings(doc.data());

    const ref = db.collection('announcements').doc(doc.id);
    await writer.set(ref, data);

    // Migrate subcollections: votes, flags, verifications
    for (const sub of ['votes', 'flags', 'verifications']) {
      const subSnap = await db.collection('course_announcements').doc(doc.id)
        .collection(sub).get();
      for (const subDoc of subSnap.docs) {
        const subRef = db.collection('announcements').doc(doc.id).collection(sub).doc(subDoc.id);
        await writer.set(subRef, subDoc.data());
      }
    }
  }

  await writer.flush();
  writer.log();
}

// ─── Step G: Write reference data ───────────────────────────────────────────

async function stepG() {
  console.log('\n=== Step G: Write reference data ===');

  // G1: prerequisites
  console.log('  [G1] Prerequisites...');
  const prereqWriter = new BatchWriter('reference/prerequisites/courses');
  const prereqSnap = await db.collection('prerequisites').get();
  const prereqSeenIds = new Map();

  for (const doc of prereqSnap.docs) {
    const data = doc.data();
    const rawCode = sanitizeString(data.course_code || '');
    if (!rawCode) continue;

    const prereqs = (data.prereqs || []).map(p => ({
      course_code: extractCourseCode(p.prereq_name || p.course_code || ''),
      type: (p.pre_cop || p.type || 'pre').toLowerCase(),
    }));

    // Write a doc for each course code in slash-separated codes
    const codes = rawCode.includes('/') ? rawCode.split('/').map(c => c.trim()) : [rawCode];
    for (const code of codes) {
      const docId = code.replace(/\s+/g, '_');
      if (prereqSeenIds.has(docId)) {
        console.log(`    [collision] ${docId} ← "${rawCode}" (already written by "${prereqSeenIds.get(docId)}")`);
      }
      prereqSeenIds.set(docId, rawCode);

      const newDoc = {
        course_code: code,
        has_prerequisites: data.has_prerequisites || prereqs.length > 0,
        prereqs,
        last_updated: toTimestamp(data.lastUpdated) || Timestamp.now(),
      };

      prereqWriter.rekeyed++;
      if (REPORT && prereqWriter.total < 3) {
        console.log(`    [sample] ${doc.id} → ${docId}:`, JSON.stringify(newDoc));
      }

      const ref = db.collection('reference').doc('prerequisites').collection('courses').doc(docId);
      await prereqWriter.set(ref, newDoc);
    }
  }
  await prereqWriter.flush();
  prereqWriter.log();

  // G2: course_guide
  console.log('  [G2] Course guide...');
  const guideWriter = new BatchWriter('reference/course_guide/semesters');
  const guideSnap = await db.collection('course_guide').get();

  for (const doc of guideSnap.docs) {
    const data = doc.data();

    if (doc.id === '_metadata') {
      if (!DRY_RUN) {
        await db.collection('reference').doc('course_guide').collection('metadata').doc('info').set(sanitizeAllStrings(data));
      }
      console.log('    [done] _metadata → reference/course_guide/metadata/info');
      continue;
    }

    // Strip course names from groups.courses[]
    let rawGroups = data.groups || [];
    if (!Array.isArray(rawGroups)) {
      // Some docs store groups as a map {0: {...}, 1: {...}} — convert to array
      if (typeof rawGroups === 'object' && rawGroups !== null) {
        rawGroups = Object.values(rawGroups);
      } else {
        console.warn(`    [warn] ${doc.id}: groups is neither array nor object, skipping`);
        rawGroups = [];
      }
    }
    const groups = rawGroups.map(g => {
      if (!g || typeof g !== 'object') return g;
      let courses = g.courses || [];
      if (!Array.isArray(courses)) {
        courses = typeof courses === 'object' ? Object.values(courses) : [];
      }
      return {
        ...sanitizeAllStrings(g),
        courses: courses.map(c => {
          if (!c || typeof c !== 'object') return c;
          const { name, course_name, ...rest } = c;
          return sanitizeAllStrings(rest);
        }),
      };
    });

    const newDoc = { ...sanitizeAllStrings(data), groups };

    if (REPORT && guideWriter.total < 3) {
      console.log(`    [sample] ${doc.id}:`, JSON.stringify(newDoc).substring(0, 200));
    }

    const ref = db.collection('reference').doc('course_guide').collection('semesters').doc(doc.id);
    await guideWriter.set(ref, newDoc);
  }
  await guideWriter.flush();
  guideWriter.log();

  // G3: discipline_electives
  console.log('  [G3] Discipline electives...');
  const deWriter = new BatchWriter('reference/discipline_electives/branches');
  const deSnap = await db.collection('discipline_electives').get();

  for (const doc of deSnap.docs) {
    const data = doc.data();

    if (doc.id === '_metadata') {
      if (!DRY_RUN) {
        await db.collection('reference').doc('discipline_electives').collection('metadata').doc('info').set(sanitizeAllStrings(data));
      }
      continue;
    }

    // Flatten courses to just code array
    const courses = (data.courses || []).map(c =>
      typeof c === 'string' ? sanitizeString(c) : sanitizeString(c.course_code || '')
    ).filter(Boolean);

    const newDoc = {
      branch_name: sanitizeString(data.branchName || ''),
      branch_code: sanitizeString(data.branchCode || ''),
      course_count: data.courseCount || courses.length,
      courses,
    };

    if (REPORT && deWriter.total < 3) {
      console.log(`    [sample] ${doc.id}:`, JSON.stringify(newDoc).substring(0, 200));
    }

    const ref = db.collection('reference').doc('discipline_electives').collection('branches').doc(doc.id);
    await deWriter.set(ref, newDoc);
  }
  await deWriter.flush();
  deWriter.log();

  // G4: huel_guide
  console.log('  [G4] HUEL guide...');
  const huelWriter = new BatchWriter('reference/huel_guide/courses');
  const huelSnap = await db.collection('huel_guide').get();

  for (const doc of huelSnap.docs) {
    const data = doc.data();

    if (doc.id === '_metadata') {
      if (!DRY_RUN) {
        await db.collection('reference').doc('huel_guide').collection('metadata').doc('info').set(sanitizeAllStrings(data));
      }
      continue;
    }

    const code = sanitizeString(data.course_code || '');
    if (!code) continue;
    const docId = courseCodeToDocId(code);

    const newDoc = { course_code: code };

    huelWriter.rekeyed++;
    const ref = db.collection('reference').doc('huel_guide').collection('courses').doc(docId);
    await huelWriter.set(ref, newDoc);
  }
  await huelWriter.flush();
  huelWriter.log();

  // G5: professors
  console.log('  [G5] Professors...');
  const profWriter = new BatchWriter('reference/professors/entries');
  const profSnap = await db.collection('professors').get();

  for (const doc of profSnap.docs) {
    const data = doc.data();

    // Drop 'id' field, strip courseTitle from schedule
    const { id, ...rest } = data;
    const schedule = (rest.schedule || []).map(entry => {
      const { courseTitle, course_title, ...entryRest } = entry;
      return sanitizeAllStrings(entryRest);
    });

    const newDoc = {
      ...sanitizeAllStrings(rest),
      schedule,
    };

    if (REPORT && profWriter.total < 3) {
      console.log(`    [sample] ${doc.id}:`, JSON.stringify(newDoc).substring(0, 200));
    }

    const ref = db.collection('reference').doc('professors').collection('entries').doc(doc.id);
    await profWriter.set(ref, newDoc);
  }
  await profWriter.flush();
  profWriter.log();
}

// ─── Step H: Write acad_drives ──────────────────────────────────────────────

async function stepH() {
  console.log('\n=== Step H: Write acad_drives ===');

  // H1: files → acad_drives_files
  console.log('  [H1] Files...');
  const filesWriter = new BatchWriter('acad_drives_files');
  const filesSnap = await db.collection('files').get();

  for (const doc of filesSnap.docs) {
    const data = doc.data();

    const newDoc = { ...sanitizeAllStrings(data) };
    // Drop firebaseUrl (FIX3)
    delete newDoc.firebaseUrl;
    // Rename storageUrl → url
    if (newDoc.storageUrl !== undefined) {
      newDoc.url = newDoc.storageUrl;
      delete newDoc.storageUrl;
    }
    // Drop courseCode singular and courseName (FIX4, FIX13)
    delete newDoc.courseCode;
    delete newDoc.courseName;
    // Rename courseCodes → course_codes
    if (newDoc.courseCodes !== undefined) {
      newDoc.course_codes = newDoc.courseCodes;
      delete newDoc.courseCodes;
    }

    filesWriter.sanitized++;
    if (REPORT && filesWriter.total < 3) {
      console.log(`    [sample] ${doc.id}:`, JSON.stringify(newDoc).substring(0, 200));
    }

    const ref = db.collection('acad_drives_files').doc(doc.id);
    await filesWriter.set(ref, newDoc);
  }
  await filesWriter.flush();
  filesWriter.log();

  // H2: submissions → acad_drives_submissions
  console.log('  [H2] Submissions...');
  const subWriter = new BatchWriter('acad_drives_submissions');
  const subSnap = await db.collection('submissions').get();

  for (const doc of subSnap.docs) {
    const ref = db.collection('acad_drives_submissions').doc(doc.id);
    await subWriter.set(ref, sanitizeAllStrings(doc.data()));
  }
  await subWriter.flush();
  subWriter.log();

  // H3: tags → acad_drives_tags
  console.log('  [H3] Tags...');
  const tagsWriter = new BatchWriter('acad_drives_tags');
  const tagsSnap = await db.collection('tags').get();

  for (const doc of tagsSnap.docs) {
    const ref = db.collection('acad_drives_tags').doc(doc.id);
    await tagsWriter.set(ref, sanitizeAllStrings(doc.data()));
  }
  await tagsWriter.flush();
  tagsWriter.log();
}

// ─── Step I: Write admin metadata ───────────────────────────────────────────

async function stepI() {
  console.log('\n=== Step I: Write admin metadata ===');

  const mappings = [
    { old: 'metadata/professors', new: 'admin_metadata/professors' },
    { old: 'metadata/prerequisites', new: 'admin_metadata/prerequisites' },
    { old: 'metadata/all_courses', new: 'admin_metadata/all_courses' },
    { old: 'metadata/exam_seating', new: 'admin_metadata/exam_seating' },
    { old: 'metadata/announcement', new: 'admin_metadata/announcement' },
    { old: 'metadataAcad/stats', new: 'admin_metadata/acad_drives' },
  ];

  for (const m of mappings) {
    const [col, docId] = m.old.split('/');
    const oldDoc = await db.collection(col).doc(docId).get();
    if (!oldDoc.exists) {
      console.log(`  [skip] ${m.old} does not exist`);
      continue;
    }

    const data = sanitizeAllStrings(oldDoc.data());
    // Drop stale 'collection' field from exam_seating metadata
    if (m.old === 'metadata/exam_seating') {
      delete data.collection;
    }

    if (DRY_RUN) {
      console.log(`  [dry-run] ${m.old} → ${m.new}`);
      continue;
    }

    const parts = m.new.split('/');
    let ref;
    if (parts.length === 4) {
      ref = db.collection(parts[0]).doc(parts[1]).collection(parts[2]).doc(parts[3]);
    } else if (parts.length === 2) {
      ref = db.collection(parts[0]).doc(parts[1]);
    } else {
      console.warn(`  [skip] ${m.new}: invalid path (${parts.length} segments)`);
      continue;
    }
    await ref.set(data);
    console.log(`  [done] ${m.old} → ${m.new}`);
  }
}

// ─── Verify mode ────────────────────────────────────────────────────────────

async function verify() {
  console.log('\n=== Verification: comparing doc counts ===');

  const checks = [
    { old: 'all_courses', new: 'campuses/hyderabad/courses_master' },
    { old: 'hyd-courses', new: 'campuses/hyderabad/timetable' },
    { old: 'pilani-courses', new: 'campuses/pilani/timetable' },
    { old: 'goa-courses', new: 'campuses/goa/timetable' },
    { old: 'hyd-exam-seating', new: 'campuses/hyderabad/exam_seating' },
    { old: 'course_announcements', new: 'announcements' },
    { old: 'prerequisites', new: 'reference/prerequisites/courses' },
    { old: 'professors', new: 'reference/professors/entries' },
    { old: 'files', new: 'acad_drives_files' },
  ];

  for (const check of checks) {
    const oldParts = check.old.split('/');
    let oldCount;
    if (oldParts.length === 1) {
      oldCount = (await db.collection(oldParts[0]).get()).size;
    } else {
      oldCount = (await db.collection(oldParts[0]).doc(oldParts[1]).collection(oldParts[2]).get()).size;
    }

    const newParts = check.new.split('/');
    let newCount;
    if (newParts.length === 1) {
      newCount = (await db.collection(newParts[0]).get()).size;
    } else if (newParts.length === 3) {
      newCount = (await db.collection(newParts[0]).doc(newParts[1]).collection(newParts[2]).get()).size;
    } else {
      newCount = (await db.collection(newParts[0]).get()).size;
    }

    const status = newCount >= oldCount ? '✓' : '✗';
    console.log(`  ${status} ${check.old}: ${oldCount} → ${check.new}: ${newCount}`);
  }
}

// ─── Main ───────────────────────────────────────────────────────────────────

const STEPS = {
  a: stepA,
  b: stepB,
  c: stepC,
  d: stepD,
  e: stepE,
  f: stepF,
  g: stepG,
  h: stepH,
  i: stepI,
};

async function main() {
  console.log(`Migration to v2 — ${DRY_RUN ? 'DRY RUN' : 'LIVE'}`);
  if (REPORT) console.log('Report mode: showing sample transforms');
  if (ONLY_STEP) console.log(`Running only step: ${ONLY_STEP}`);

  if (VERIFY) {
    await verify();
    return;
  }

  if (SCRATCH) {
    await scratchAll();
  }

  let stepsToRun = ONLY_STEP ? [ONLY_STEP] : Object.keys(STEPS);

  for (const step of stepsToRun) {
    if (!STEPS[step]) {
      console.error(`Unknown step: ${step}. Valid: ${Object.keys(STEPS).join(', ')}`);
      process.exit(1);
    }
    await STEPS[step]();
  }

  console.log('\n=== Migration complete ===');
}

main().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});

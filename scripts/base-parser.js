/**
 * base-parser.js — Shared infrastructure for all campus upload scripts.
 *
 * Provides:
 *   initializeFirebase()          — reads service account from env, returns { db }
 *   getCampusCollection(code)     — maps campus code to Firestore collection name
 *   getCampusName(code)           — maps campus code to display name
 *   uploadCoursesToFirestore(db, courses, collectionName, opts)
 *                                 — batch upload with optional clear-first
 *   updateMetadata(db, collectionName, metadata)
 *                                 — writes to timetable_metadata collection
 *   CellUtils                     — static helpers shared by every parser class
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from parent directory (.env in project root)
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// ─── Firebase initialisation ────────────────────────────────────────────────

let _db = null;

/**
 * Initialise Firebase Admin SDK from environment variables.
 * Safe to call multiple times — returns the same Firestore instance.
 */
export function initializeFirebase() {
  if (_db) return { db: _db };

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
  _db = getFirestore();
  return { db: _db };
}

// ─── Campus helpers ─────────────────────────────────────────────────────────

const CAMPUS_IDS = {
  pilani: 'pilani',
  hyderabad: 'hyderabad',
  hyd: 'hyderabad',
  goa: 'goa',
};

const CAMPUS_DISPLAY_NAMES = {
  pilani: 'Pilani',
  hyderabad: 'Hyderabad',
  hyd: 'Hyderabad',
  goa: 'Goa',
};

export function getCampusId(campusCode) {
  return CAMPUS_IDS[campusCode.toString().toLowerCase()] || 'hyderabad';
}

export function getTimetableCollection(campusCode) {
  return `campuses/${getCampusId(campusCode)}/timetable`;
}

export function getCoursesMasterCollection(campusCode) {
  return `campuses/${getCampusId(campusCode)}/courses_master`;
}

export function sanitizeString(str) {
  if (typeof str !== 'string') return str;
  return str.replace(/[\n\r]/g, ' ').replace(/\s+/g, ' ').trim();
}

export function courseCodeToDocId(code) {
  const sanitized = sanitizeString(code);
  const primary = sanitized.includes('/') ? sanitized.split('/')[0].trim() : sanitized;
  return primary.replace(/\s+/g, '_');
}

/**
 * Return a human-readable campus name for logging.
 */
export function getCampusName(campusCode) {
  const key = campusCode.toString().toLowerCase();
  return CAMPUS_DISPLAY_NAMES[key] || 'Hyderabad';
}

// ─── Batch upload ───────────────────────────────────────────────────────────

const BATCH_SIZE = 500;

/**
 * Upload an array of course objects, splitting into courses_master + timetable.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {Object[]} courses — each must have a `courseCode` property
 * @param {string}   campusCode — e.g. 'hyderabad', 'pilani', 'goa'
 * @param {Object}   [opts]
 * @param {boolean}  [opts.clearFirst=true] — delete all existing docs before uploading
 */
export async function uploadCoursesToFirestore(db, courses, campusCode, opts = {}) {
  const { clearFirst = true } = opts;
  const campusId = getCampusId(campusCode);
  const masterRef = db.collection(`campuses/${campusId}/courses_master`);
  const timetableRef = db.collection(`campuses/${campusId}/timetable`);

  console.log(`Uploading ${courses.length} courses to campus: ${campusId}`);

  if (clearFirst) {
    console.log('Clearing existing courses...');
    for (const ref of [masterRef, timetableRef]) {
      const existingDocs = await ref.get();
      let batch = db.batch();
      let count = 0;
      for (const doc of existingDocs.docs) {
        batch.delete(doc.ref);
        count++;
        if (count >= BATCH_SIZE) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
      console.log(`Cleared ${existingDocs.size} docs from ${ref.path}`);
    }
  }

  console.log('Uploading courses_master + timetable...');
  for (let i = 0; i < courses.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const slice = courses.slice(i, i + BATCH_SIZE);

    for (const course of slice) {
      const docId = courseCodeToDocId(course.courseCode);
      const code = sanitizeString(course.courseCode);

      // courses_master: identity only
      batch.set(masterRef.doc(docId), {
        course_code: code,
        title: sanitizeString(course.courseTitle || ''),
        credits: parseInt(course.totalCredits || course.lectureCredits || '0', 10) || 0,
        type: course.type || 'Normal',
      });

      // timetable: scheduling data
      const timetableData = {
        sections: (course.sections || []).map(s => ({
          ...s,
          instructor: sanitizeString(s.instructor || ''),
          room: sanitizeString(s.room || ''),
        })),
        mid_sem_exam: course.midSemExam || null,
        end_sem_exam: course.endSemExam || null,
        lecture_credits: parseInt(course.lectureCredits || '0', 10) || 0,
        practical_credits: parseInt(course.practicalCredits || '0', 10) || 0,
      };
      batch.set(timetableRef.doc(docId), timetableData);
    }

    await batch.commit();
    console.log(`Uploaded courses ${i + 1} to ${Math.min(i + BATCH_SIZE, courses.length)}`);
  }
}

// ─── Metadata ───────────────────────────────────────────────────────────────

/**
 * Write (or merge) a metadata document for a campus upload.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} campusCode — campus code
 * @param {Object} metadata   — fields to write
 * @param {Object} [opts]
 * @param {boolean} [opts.merge=false]
 */
export async function updateMetadata(db, campusCode, metadata, opts = {}) {
  const { merge = false } = opts;
  const campusId = getCampusId(campusCode);
  const ref = db.collection('campuses').doc(campusId).collection('metadata').doc('current');
  await ref.set(metadata, { merge });
  console.log(`Updated metadata: campuses/${campusId}/metadata/current`);
}

// ─── Shared cell / row utilities ────────────────────────────────────────────

/**
 * Static utility methods used by every campus-specific parser class.
 * Extend or call these directly — they carry no state.
 */
export class CellUtils {
  static getCellValue(row, index) {
    if (!row || index >= row.length) return null;
    const value = row[index];
    return value !== null && value !== undefined ? value : null;
  }

  static getNumericValue(row, index) {
    const value = this.getCellValue(row, index);
    if (value === null || value === undefined) return 0;

    if (typeof value === 'number') {
      return Math.round(value);
    }
    const str = value.toString().trim();
    if (str === '' || str === '-') return 0;
    const num = parseFloat(str);
    return isNaN(num) ? 0 : Math.round(num);
  }

  static formatCellValue(value) {
    if (value === null || value === undefined) return '';
    return value.toString();
  }

  static isEmptyRow(row) {
    if (!row) return true;
    return row.every(
      (cell) => cell === null || cell === undefined || cell.toString().trim() === ''
    );
  }

  static parseSectionType(sectionId) {
    if (sectionId.startsWith('L')) return 'SectionType.L';
    if (sectionId.startsWith('P')) return 'SectionType.P';
    if (sectionId.startsWith('T')) return 'SectionType.T';
    return 'SectionType.L';
  }
}

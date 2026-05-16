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

const CAMPUS_COLLECTIONS = {
  pilani: 'pilani-courses',
  hyderabad: 'hyd-courses',
  hyd: 'hyd-courses',
  goa: 'goa-courses',
  default: 'courses',
};

const CAMPUS_DISPLAY_NAMES = {
  pilani: 'Pilani',
  hyderabad: 'Hyderabad',
  hyd: 'Hyderabad',
  goa: 'Goa',
  default: 'Default',
};

/**
 * Return the Firestore collection name for a campus code.
 */
export function getCampusCollection(campusCode) {
  const key = campusCode.toString().toLowerCase();
  return CAMPUS_COLLECTIONS[key] || 'courses';
}

/**
 * Return a human-readable campus name for logging.
 */
export function getCampusName(campusCode) {
  const key = campusCode.toString().toLowerCase();
  return CAMPUS_DISPLAY_NAMES[key] || 'Default Campus';
}

// ─── Batch upload ───────────────────────────────────────────────────────────

const BATCH_SIZE = 500;

/**
 * Upload an array of course objects to a Firestore collection.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {Object[]} courses — each must have a `courseCode` property used as doc id
 * @param {string}   collectionName
 * @param {Object}   [opts]
 * @param {boolean}  [opts.clearFirst=true] — delete all existing docs before uploading
 */
export async function uploadCoursesToFirestore(db, courses, collectionName, opts = {}) {
  const { clearFirst = true } = opts;
  const coursesRef = db.collection(collectionName);

  console.log(`Uploading ${courses.length} courses to Firestore collection: ${collectionName}`);

  // Optionally clear existing data
  if (clearFirst) {
    console.log('Clearing existing courses...');
    const existingDocs = await coursesRef.get();
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
    if (count > 0) {
      await batch.commit();
    }
    console.log(`Cleared ${existingDocs.size} existing courses`);
  }

  // Upload in batches
  console.log('Adding new courses...');
  for (let i = 0; i < courses.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const slice = courses.slice(i, i + BATCH_SIZE);

    for (const course of slice) {
      const docRef = coursesRef.doc(course.courseCode);
      batch.set(docRef, course);
    }

    await batch.commit();
    console.log(`Uploaded courses ${i + 1} to ${Math.min(i + BATCH_SIZE, courses.length)}`);
  }
}

// ─── Metadata ───────────────────────────────────────────────────────────────

/**
 * Write (or merge) a metadata document for a collection upload.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} collectionName — used to derive the metadata doc name
 * @param {Object} metadata      — fields to write
 * @param {Object} [opts]
 * @param {boolean} [opts.merge=false] — merge into existing doc instead of overwrite
 */
export async function updateMetadata(db, collectionName, metadata, opts = {}) {
  const { merge = false } = opts;
  const metadataCollection = process.env.TIMETABLE_METADATA_COLLECTION || 'timetable_metadata';

  // Derive doc name from collection: "pilani-courses" -> "current-pilani", "courses" -> "current"
  const campus = collectionName.replace('-courses', '');
  const docName = campus === 'courses' ? 'current' : `current-${campus}`;

  const ref = db.collection(metadataCollection).doc(docName);
  await ref.set(metadata, { merge });
  console.log(`Updated metadata: ${metadataCollection}/${docName}`);
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

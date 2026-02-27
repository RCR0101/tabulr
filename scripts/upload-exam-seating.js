import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';
import { parse } from 'csv-parse/sync';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from parent directory (.env in project root)
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// Initialize Firebase Admin
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

initializeApp({
  credential: cert(serviceAccount)
});

const db = getFirestore();

// Helper function to get campus-specific collection name
function getCampusCollection(campus) {
  const campusMap = {
    'hyderabad': 'hyd-exam-seating',
    'hyd': 'hyd-exam-seating',
    'goa': 'goa-exam-seating',
    'pilani': 'pilani-exam-seating',
    'default': 'exam-seating'
  };

  const campusKey = campus.toString().toLowerCase();
  return campusMap[campusKey] || 'exam-seating';
}

// Helper function to get campus name for display
function getCampusName(campus) {
  const campusMap = {
    'hyderabad': 'Hyderabad',
    'hyd': 'Hyderabad',
    'goa': 'Goa',
    'pilani': 'Pilani',
    'default': 'Default'
  };

  const campusKey = campus.toString().toLowerCase();
  return campusMap[campusKey] || 'Default Campus';
}

/**
 * Parses exam seating CSV and extracts structured data
 * CSV Format: course_code, course_title, exam_date, room_no, id_range, student_count
 *
 * Important: A single exam can have multiple rooms listed consecutively.
 * Rows without a course code belong to the same course as the previous row.
 */
class ExamSeatingParser {
  static parseCsvFile(filePath) {
    try {
      const csvContent = fs.readFileSync(filePath, 'utf8');
      const records = parse(csvContent, {
        columns: true,
        skip_empty_lines: true,
        trim: true,
        relax_column_count: true,
        relax_quotes: true
      });

      return this.parseRecords(records);
    } catch (error) {
      throw new Error(`Error parsing CSV file: ${error.message}`);
    }
  }

  static parseRecords(records) {
    const exams = [];
    let currentExam = null;
    const skippedCourses = [];

    for (const record of records) {
      const courseCode = (record.course_code || '').trim();
      const courseTitle = (record.course_title || '').trim();
      const examDate = (record.exam_date || '').trim();
      const roomNo = (record.room_no || '').trim();
      const idRange = (record.id_range || '').trim();
      const studentCount = parseInt(record.student_count) || null;

      // Skip rows without room or ID range data
      if (!roomNo || !idRange) {
        if (courseCode) {
          skippedCourses.push({ courseCode, reason: 'missing room or id_range', roomNo, idRange });
        }
        continue;
      }

      // Parse ID range (e.g., "2022A7PS0001H - 2022A7PS0060H")
      const idRangeParsed = this.parseIdRange(idRange);
      if (!idRangeParsed) {
        if (courseCode) {
          skippedCourses.push({ courseCode, reason: 'invalid id_range format', idRange });
        }
        continue;
      }

      // If we have a course code, start a new exam entry
      if (courseCode) {
        // Save previous exam if exists
        if (currentExam && currentExam.rooms.length > 0) {
          exams.push(currentExam);
        }

        currentExam = {
          courseCode: courseCode,
          courseTitle: courseTitle,
          examDate: examDate,
          rooms: []
        };
      }

      // Add room data to current exam
      if (currentExam) {
        currentExam.rooms.push({
          roomNo: roomNo,
          idFrom: idRangeParsed.from,
          idTo: idRangeParsed.to,
          studentCount: studentCount
        });
      }
    }

    // Don't forget the last exam
    if (currentExam && currentExam.rooms.length > 0) {
      exams.push(currentExam);
    }

    // Log skipped courses
    if (skippedCourses.length > 0) {
      console.log(`\nSkipped ${skippedCourses.length} course entries:`);
      for (const skipped of skippedCourses) {
        console.log(`  - ${skipped.courseCode}: ${skipped.reason}`);
        if (skipped.idRange) {
          console.log(`    id_range: "${skipped.idRange}"`);
        }
      }
    }

    return exams;
  }

  static parseIdRange(idRange) {
    // Pattern for ID range - handles multiple formats:
    // "2022A7PS0001H - 2022A7PS0060H" (dash)
    // "2022A7PS0001H to 2022A7PS0060H" (word "to")
    // Can also span multiple lines in CSV
    const normalizedRange = idRange.replace(/\n/g, ' ').trim();

    // Check for "ALL THE STUDENTS" or similar - means single room for all
    if (/all\s*(the)?\s*students/i.test(normalizedRange)) {
      return {
        from: null,
        to: null,
        allStudents: true
      };
    }

    // ID format: \d{4}[A-Z0-9]{4}\d{4}[HG] (e.g., 2022A7PS0001H, 2023AAPS0168G)
    const idPattern = '(\\d{4}[A-Z0-9]{4}\\d{4}[HGPD])';

    // Try dash/en-dash format first
    let idRangePattern = new RegExp(idPattern + '\\s*[-–]\\s*' + idPattern);
    let match = normalizedRange.match(idRangePattern);

    if (match) {
      return {
        from: match[1],
        to: match[2]
      };
    }

    // Try "to" format (e.g., "2020B4A40988H to 2023A4PS0607H")
    idRangePattern = new RegExp(idPattern + '\\s+to\\s+' + idPattern, 'i');
    match = normalizedRange.match(idRangePattern);

    if (match) {
      return {
        from: match[1],
        to: match[2]
      };
    }

    return null;
  }
}

async function uploadExamSeating(csvPath, campus = 'default') {
  console.log(`\nParsing exam seating CSV: ${csvPath}`);

  const exams = ExamSeatingParser.parseCsvFile(csvPath);

  console.log(`Found ${exams.length} courses with seating data`);

  if (exams.length === 0) {
    console.log('No exam seating data found in CSV');
    return;
  }

  // Show sample of parsed data
  console.log('\nSample parsed data:');
  for (let i = 0; i < Math.min(3, exams.length); i++) {
    const exam = exams[i];
    console.log(`  ${exam.courseCode}: ${exam.courseTitle || 'N/A'} - ${exam.rooms.length} rooms`);
    for (const room of exam.rooms) {
      console.log(`    Room ${room.roomNo}: ${room.idFrom} - ${room.idTo} (${room.studentCount || 'N/A'} students)`);
    }
  }

  const collectionName = getCampusCollection(campus);
  const campusDisplayName = getCampusName(campus);

  console.log(`\nUploading to collection: ${collectionName} (${campusDisplayName})`);

  // Upload in batches (Firestore limit is 500 operations per batch)
  let batch = db.batch();
  let operationCount = 0;
  let totalUploaded = 0;

  for (const exam of exams) {
    // Replace spaces with underscores and slashes with dashes for valid Firestore doc ID
    const docId = exam.courseCode.replace(/\s+/g, '_').replace(/\//g, '-');
    const docRef = db.collection(collectionName).doc(docId);

    batch.set(docRef, {
      courseCode: exam.courseCode,
      courseTitle: exam.courseTitle || '',
      examDate: exam.examDate || '',
      rooms: exam.rooms,
      updatedAt: new Date().toISOString()
    });

    operationCount++;
    totalUploaded++;

    if (operationCount >= 450) {
      await batch.commit();
      console.log(`  Committed batch of ${operationCount} documents`);
      batch = db.batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    await batch.commit();
    console.log(`  Committed final batch of ${operationCount} documents`);
  }

  // Update metadata
  const metadataRef = db.collection('metadata').doc('exam_seating');
  await metadataRef.set({
    lastUpdated: new Date().toISOString(),
    totalCourses: exams.length,
    campus: campusDisplayName,
    collection: collectionName
  }, { merge: true });

  console.log(`\nSuccessfully uploaded ${totalUploaded} courses to ${collectionName}`);
}

// Main execution
const args = process.argv.slice(2);

if (args.length < 1) {
  console.log('Usage: node upload-exam-seating.js <csv-path> [campus]');
  console.log('  csv-path: Path to the exam seating CSV file (converted from PDF using convert-exam-seating.py)');
  console.log('  campus: Optional campus name (hyderabad/hyd, goa, pilani, default)');
  console.log('\nSteps:');
  console.log('  1. Convert PDF to CSV: python convert-exam-seating.py ../ExamSA.pdf exam_seating.csv');
  console.log('  2. Upload CSV: node upload-exam-seating.js exam_seating.csv hyderabad');
  process.exit(1);
}

const csvPath = path.resolve(__dirname, args[0]);
const campus = args[1] || 'default';

if (!fs.existsSync(csvPath)) {
  console.error(`Error: File not found: ${csvPath}`);
  process.exit(1);
}

uploadExamSeating(csvPath, campus)
  .then(() => {
    console.log('\nDone!');
    process.exit(0);
  })
  .catch(error => {
    console.error('Error:', error.message);
    process.exit(1);
  });

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

// Pilani exam session mappings
const EXAM_SESSIONS = {
  'FN1': { start: '09:00', end: '10:30' },
  'FN2': { start: '11:00', end: '12:30' },
  'AN1': { start: '14:00', end: '15:30' },
  'AN2': { start: '16:00', end: '17:30' }
};

// Parser class for Pilani CSV data (adapted from original XlsxParser)
class PilaniCsvParser {
  static parseCsvFile(filePath) {
    try {
      const csvContent = fs.readFileSync(filePath, 'utf8');
      const records = parse(csvContent, {
        columns: false, // Don't use first row as headers since it's just column numbers
        skip_empty_lines: true,
        trim: true
      });
      
      return this.parseCsvData(records);
    } catch (error) {
      throw new Error(`Error parsing CSV file: ${error.message}`);
    }
  }

  static parseCsvData(data) {
    const courses = [];
    
    if (data.length < 2) {
      throw new Error('Invalid CSV format');
    }
    
    let currentRow = 1; // Skip header row with column numbers
    
    while (currentRow < data.length) {
      const row = data[currentRow];
      
      if (!row || this.isEmptyRow(row)) {
        currentRow++;
        continue;
      }
      
      const compCode = this.getCellValue(row, 0);
      if (!compCode || compCode.toString().trim() === '') {
        currentRow++;
        continue;
      }
      
      const courseResult = this.parseCourseGroup(data, currentRow);
      if (courseResult) {
        courses.push(courseResult.course);
        currentRow = courseResult.nextRow;
      } else {
        currentRow++;
      }
    }
    
    return courses;
  }
  
  static parseCourseGroup(data, startRow) {
    const mainRow = data[startRow];
    
    const compCode = this.getCellValue(mainRow, 0);
    const courseNo = this.getCellValue(mainRow, 1);
    const courseTitle = this.getCellValue(mainRow, 2);
    const lectureCredits = this.getNumericValue(mainRow, 3);
    const practicalCredits = this.getNumericValue(mainRow, 4);
    const totalCredits = this.getNumericValue(mainRow, 5);
    
    if (!compCode || !courseNo || !courseTitle) {
      return null;
    }
    
    const sections = [];
    let currentRow = startRow;
    
    while (currentRow < data.length) {
      const row = data[currentRow];
      
      if (currentRow === startRow) {
        const mainSection = this.parseSection(data, startRow);
        if (mainSection) {
          sections.push(mainSection.section);
          currentRow = mainSection.nextRow;
        } else {
          console.log(`Warning: Could not parse main section for course ${courseNo} at row ${startRow}`);
          currentRow++;
        }
      } else {
        const nextCompCode = this.getCellValue(row, 0);
        
        if (nextCompCode && nextCompCode.toString().trim() !== '') {
          break;
        }
        
        const sectionId = this.getCellValue(row, 6);
        if (sectionId && sectionId.toString().trim() !== '') {
          const sectionResult = this.parseSection(data, currentRow);
          if (sectionResult) {
            sections.push(sectionResult.section);
            currentRow = sectionResult.nextRow;
          } else {
            console.log(`Warning: Could not parse additional section ${sectionId} for course ${courseNo} at row ${currentRow}`);
            currentRow++;
          }
        } else {
          currentRow++;
        }
      }
    }
    
    const midSemExam = this.parseExamSchedule(this.getCellValue(mainRow, 10), true);
    const endSemExam = this.parseExamSchedule(this.getCellValue(mainRow, 11), false);
    
    // Validate that we have at least one section
    if (sections.length === 0) {
      console.log(`Warning: Course ${courseNo} has no sections, skipping...`);
      return null;
    }
    
    const course = {
      courseCode: courseNo.toString(),
      courseTitle: courseTitle.toString(),
      lectureCredits: lectureCredits,
      practicalCredits: practicalCredits,
      totalCredits: totalCredits,
      sections: sections,
      midSemExam: midSemExam,
      endSemExam: endSemExam,
    };
    
    return { course, nextRow: currentRow };
  }
  
  static parseSection(data, startRow) {
    const row = data[startRow];
    const sectionId = this.getCellValue(row, 6);
    
    if (!sectionId || sectionId.toString().trim() === '') {
      return null;
    }
    
    const sectionIdStr = sectionId.toString().trim();
    const sectionType = this.parseSectionType(sectionIdStr);
    
    const instructors = [];
    const rooms = [];
    const schedule = [];
    
    let currentRow = startRow;
    
    while (currentRow < data.length) {
      const currentRowData = data[currentRow];
      
      if (currentRow > startRow) {
        const nextSectionId = this.getCellValue(currentRowData, 6);
        const nextCompCode = this.getCellValue(currentRowData, 0);
        
        if ((nextSectionId && nextSectionId.toString().trim() !== '') ||
            (nextCompCode && nextCompCode.toString().trim() !== '')) {
          break;
        }
      }
      
      const instructor = this.getCellValue(currentRowData, 7);
      const room = this.getCellValue(currentRowData, 8);
      const mergedSchedule = this.getCellValue(currentRowData, 9); // Days and hours merged in Pilani
      
      if (instructor && instructor.toString().trim() !== '') {
        const instructorStr = instructor.toString().trim();
        if (!instructors.includes(instructorStr)) {
          instructors.push(instructorStr);
        }
      }
      
      if (room && room.toString().trim() !== '') {
        const roomStr = room.toString().trim();
        if (!rooms.includes(roomStr)) {
          rooms.push(roomStr);
        }
      }
      
      // Parse merged schedule (e.g., "T Th F 2" or "M W 3 Th 9")
      if (mergedSchedule && mergedSchedule.toString().trim() !== '') {
        const scheduleStr = mergedSchedule.toString().trim();
        const parsedSchedule = this.parseMergedSchedule(scheduleStr);
        
        if (parsedSchedule.length > 0) {
          schedule.push(...parsedSchedule);
        }
      }
      
      currentRow++;
    }
    
    const section = {
      sectionId: sectionIdStr,
      type: sectionType,
      instructor: instructors.join(', '),
      room: rooms.join(', '),
      schedule: schedule,
    };
    
    return { section, nextRow: currentRow };
  }
  
  static parseSectionType(sectionId) {
    if (sectionId.startsWith('L')) return 'SectionType.L';
    if (sectionId.startsWith('P')) return 'SectionType.P';
    if (sectionId.startsWith('T')) return 'SectionType.T';
    return 'SectionType.L';
  }
  
  // New method for parsing merged day/hour format specific to Pilani
  static parseMergedSchedule(scheduleStr) {
    if (!scheduleStr) return [];
    
    const schedule = [];
    const parts = scheduleStr.trim().split(/\s+/);
    
    let currentDays = [];
    
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      
      // Check if it's a day
      if (this.isDayOfWeek(part)) {
        currentDays.push(this.mapDayOfWeek(part));
      } 
      // Check if it's a time slot (number)
      else if (/^\d+$/.test(part)) {
        const hour = parseInt(part);
        if (currentDays.length > 0) {
          // Add this time slot for all current days
          schedule.push({
            days: [...currentDays],
            hours: [hour],
          });
          currentDays = []; // Reset for next group
        }
      }
    }
    
    return schedule;
  }
  
  static isDayOfWeek(str) {
    const dayMap = ['M', 'T', 'W', 'Th', 'F', 'S'];
    return dayMap.includes(str);
  }
  
  static mapDayOfWeek(day) {
    const dayMap = {
      'M': 'DayOfWeek.M',
      'T': 'DayOfWeek.T',
      'W': 'DayOfWeek.W',
      'Th': 'DayOfWeek.Th',
      'F': 'DayOfWeek.F',
      'S': 'DayOfWeek.S',
    };
    return dayMap[day] || day;
  }
  
  // Adapted exam schedule parser for Pilani sessions
  static parseExamSchedule(examStr, isMidSem) {
    if (!examStr || examStr.toString().trim() === '') {
      return null;
    }
    
    const examString = examStr.toString().trim();
    const parts = examString.split(/\s+/);
    
    // Look for date pattern (DD/MM/YYYY or DD/MM)
    const datePattern = /(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{4}))?/;
    let examDate = null;
    let session = null;
    
    for (const part of parts) {
      const dateMatch = part.match(datePattern);
      if (dateMatch) {
        const [, day, month, year] = dateMatch;
        const fullYear = year || '2025'; // Default year to 2025 to match original
        // Create date string in ISO format with T00:00:00.000Z
        examDate = `${fullYear}-${month.padStart(2, '0')}-${day.padStart(2, '0')}T00:00:00.000Z`;
      } else if (EXAM_SESSIONS[part]) {
        session = part;
      }
    }
    
    if (examDate) {
      if (session && EXAM_SESSIONS[session]) {
        // Map Pilani sessions to timeSlot format
        let timeSlot;
        if (isMidSem) {
          // For mid-sem, map FN1/FN2/AN1/AN2 to MS1/MS2/MS3/MS4
          if (session === 'FN1') timeSlot = 'TimeSlot.MS1';
          else if (session === 'FN2') timeSlot = 'TimeSlot.MS2';
          else if (session === 'AN1') timeSlot = 'TimeSlot.MS3';
          else if (session === 'AN2') timeSlot = 'TimeSlot.MS4';
          else timeSlot = 'TimeSlot.MS1'; // Default
        } else {
          // For end-sem, map FN1/FN2 to FN and AN1/AN2 to AN
          if (session === 'FN') timeSlot = 'TimeSlot.FN';
          else if (session === 'AN') timeSlot = 'TimeSlot.AN';
          else timeSlot = 'TimeSlot.FN'; // Default
        }
        
        return {
          date: examDate,
          timeSlot: timeSlot
        };
      } else {
        // Default timeSlot if no session specified
        const defaultTimeSlot = isMidSem ? 'TimeSlot.MS1' : 'TimeSlot.FN';
        return {
          date: examDate,
          timeSlot: defaultTimeSlot
        };
      }
    }
    
    return null;
  }
  
  // Utility methods (same as original)
  static getCellValue(row, index) {
    if (!row || index >= row.length) return null;
    const value = row[index];
    return value !== null && value !== undefined ? value : null;
  }
  
  static getNumericValue(row, index) {
    const value = this.getCellValue(row, index);
    if (value === null || value === undefined) return 0;
    
    const str = value.toString().trim();
    if (str === '' || str === '-') return 0;
    
    const num = parseFloat(str);
    return isNaN(num) ? 0 : num;
  }
  
  static formatCellValue(value) {
    if (value === null || value === undefined) return '';
    return value.toString().trim();
  }
  
  static isEmptyRow(row) {
    if (!row) return true;
    return row.every(cell => !cell || cell.toString().trim() === '');
  }
}

async function uploadToFirestore(courses) {
  const collectionName = 'pilani-courses';
  console.log(`🔄 Uploading ${courses.length} courses to Firestore collection: ${collectionName}`);

  let batch = db.batch();
  let batchCount = 0;
  const BATCH_SIZE = 500;

  // Clear existing data
  console.log('🗑️  Clearing existing courses...');
  const existingDocs = await db.collection(collectionName).get();
  for (const doc of existingDocs.docs) {
    batch.delete(doc.ref);
    batchCount++;
    
    if (batchCount >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch(); // Create new batch after commit
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
    batch = db.batch(); // Create new batch after commit
    batchCount = 0;
  }

  console.log('📝 Adding new courses...');
  
  for (const course of courses) {
    const docRef = db.collection(collectionName).doc(course.courseCode);
    batch.set(docRef, course);
    batchCount++;

    if (batchCount >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch(); // Create new batch after commit
      batchCount = 0;
      console.log(`📊 Uploaded batch`);
    }
  }

  if (batchCount > 0) {
    await batch.commit();
    console.log(`📊 Uploaded final batch (${batchCount} courses)`);
  }

  // Update metadata
  const metadata = {
    lastUpdated: new Date(),
    totalCourses: courses.length,
    campus: 'pilani',
    uploadTimestamp: Date.now()
  };

  await db.collection('timetable_metadata').doc('current-pilani').set(metadata);
  console.log('📋 Updated metadata');
}

async function main() {
  try {
    const csvPath = path.join(__dirname, 'pilani_courses.csv');
    
    if (!fs.existsSync(csvPath)) {
      console.error(`❌ CSV file not found: ${csvPath}`);
      console.log('🔍 Expected file: pilani_courses.csv');
      process.exit(1);
    }

    console.log('🚀 Starting Pilani timetable upload...');
    console.log(`📁 Processing: ${csvPath}`);

    const courses = PilaniCsvParser.parseCsvFile(csvPath);
    
    if (courses.length === 0) {
      console.error('❌ No courses found to upload');
      process.exit(1);
    }

    await uploadToFirestore(courses);
    
    console.log('✨ Upload completed successfully!');
    console.log(`📊 Total courses uploaded: ${courses.length}`);
    
  } catch (error) {
    console.error('❌ Upload failed:', error);
    process.exit(1);
  }
}

main();
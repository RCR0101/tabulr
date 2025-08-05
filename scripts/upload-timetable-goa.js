import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import XLSX from 'xlsx';
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

// Goa-specific parser (copied from Hyderabad parser for now)
class XlsxParserGoa {
  static parseXlsxFile(filePath) {
    try {
      const workbook = XLSX.readFile(filePath);
      const sheetName = 'Table 1';
      const worksheet = workbook.Sheets[sheetName];
      
      if (!worksheet) {
        throw new Error('Table 1 sheet not found');
      }
      
      return this.parseSheet(worksheet);
    } catch (error) {
      throw new Error(`Error parsing XLSX file: ${error.message}`);
    }
  }
  
  static parseSheet(worksheet) {
    const data = XLSX.utils.sheet_to_json(worksheet, { header: 1 });
    const courses = [];
    
    if (data.length < 3) {
      throw new Error('Invalid sheet format');
    }
    
    let currentRow = 2; // Skip header rows, same as Hyderabad script
    
    while (currentRow < data.length) {
      const row = data[currentRow];
      
      if (!row || this.isEmptyRow(row)) {
        currentRow++;
        continue;
      }
      
      
      const courseNo = this.getCellValue(row, 1); // Course No is second column
      const courseTitle = this.getCellValue(row, 2); // Course Title is third column
      
      // Start a new course if we have a course number
      if (courseNo && courseNo.toString().trim() !== '') {
        const courseResult = this.parseCourseGroup(data, currentRow);
        if (courseResult) {
          courses.push(courseResult.course);
          currentRow = courseResult.nextRow;
        } else {
          currentRow++;
        }
      } else {
        currentRow++;
      }
    }
    
    return courses;
  }


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
    
    let currentRow = 1; // Skip first header row, same as Hyderabad script
    
    while (currentRow < data.length) {
      const row = data[currentRow];
      
      if (!row || this.isEmptyRow(row)) {
        currentRow++;
        continue;
      }
      
      
      const courseNo = this.getCellValue(row, 1); // Course No is second column
      
      // Start a new course if we have a course number
      if (courseNo && courseNo.toString().trim() !== '') {
        const courseResult = this.parseCourseGroup(data, currentRow);
        if (courseResult) {
          courses.push(courseResult.course);
          currentRow = courseResult.nextRow;
        } else {
          currentRow++;
        }
      } else {
        currentRow++;
      }
    }
    
    return courses;
  }
  
  static parseCourseGroup(data, startRow) {
    const mainRow = data[startRow];
    
    // New Goa column structure:
    // 0: ?, 1: Course No, 2: Course Title, 3: L P U, 4: Stat, 5: Sec, 
    // 6: Instructor in Charge/Instructor, 7: Days/Hr, 8: Room, 
    // 9: Compre Date, 10: Midsem Date, 11: Midsem Time
    
    const courseNo = this.getCellValue(mainRow, 1);
    const courseTitle = this.getCellValue(mainRow, 2);
    const lpuStr = this.getCellValue(mainRow, 3); // L P U space separated
    
    if (!courseNo || !courseTitle || 
        courseNo.toString().trim() === '' || 
        courseTitle.toString().trim() === '' ||
        courseNo.toString().trim() === '#N/A' ||
        courseTitle.toString().trim() === '#N/A') {
      console.log(`Skipping invalid course: courseNo="${courseNo}", courseTitle="${courseTitle}"`);
      return null;
    }
    
    // Parse L P U (space separated)
    const lpu = this.parseLPU(lpuStr?.toString() || '');
    const lectureCredits = lpu.L;
    const practicalCredits = lpu.P;
    const totalCredits = lpu.U;
    
    const sections = [];
    let currentRow = startRow;
    
    // Get exam info from first row only
    const midSemExam = this.parseGoaMidSemExam(
      this.getCellValue(mainRow, 10), // Midsem Date
      this.getCellValue(mainRow, 11)  // Midsem Time
    );
    const endSemExam = this.parseGoaComprehensiveExam(
      this.getCellValue(mainRow, 9)  // Compre Date
    );
    
    while (currentRow < data.length) {
      const row = data[currentRow];
      
      // Check if we've moved to a different course
      const nextCourseNo = this.getCellValue(row, 1);
      if (currentRow > startRow && nextCourseNo && 
          nextCourseNo.toString().trim() !== '' && 
          nextCourseNo.toString() !== courseNo.toString()) {
        break;
      }
      
      const sectionResult = this.parseGoaSection(data, currentRow, courseNo.toString());
      if (sectionResult) {
        sections.push(sectionResult.section);
        currentRow = sectionResult.nextRow;
      } else {
        currentRow++;
      }
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

  static parseLPU(lpuStr) {
    // Parse "L P U" space separated string
    const parts = lpuStr.trim().split(/\s+/);
    return {
      L: parts.length > 0 ? (parseInt(parts[0]) || 0) : 0,
      P: parts.length > 1 ? (parseInt(parts[1]) || 0) : 0,
      U: parts.length > 2 ? (parseInt(parts[2]) || 0) : 0,
    };
  }
  
  static parseGoaSection(data, startRow, courseNo) {
    const row = data[startRow];
    
    // Goa columns: 4: Stat, 5: Sec, 6: Instructor, 7: Days/Hr, 8: Room
    const stat = this.getCellValue(row, 4);
    const sec = this.getCellValue(row, 5);
    
    if (!stat || !sec) {
      return null;
    }
    
    // Create section ID by concatenating Stat and Sec (like L1, P1, R1, I1)
    const sectionId = `${stat.toString().trim()}${sec.toString().trim()}`;
    const sectionType = this.parseGoaSectionType(stat.toString().trim());
    
    const instructor = this.getCellValue(row, 6);
    const daysHr = this.getCellValue(row, 7);
    const room = this.getCellValue(row, 8);
    
    // Parse instructors - all instructors for this section are in the same cell
    const instructors = this.parseGoaInstructors(instructor?.toString() || '');
    
    // Parse days/hours (similar to Pilani logic)
    const schedule = this.parseGoaDaysHours(daysHr?.toString() || '');
    
    const section = {
      sectionId: sectionId,
      type: sectionType,
      instructor: instructors.join(', '),
      room: room?.toString().trim() || '',
      schedule: schedule,
    };
    
    return { section, nextRow: startRow + 1 };
  }

  static parseGoaSectionType(stat) {
    const statUpper = stat.toUpperCase();
    switch (statUpper) {
      case 'L': return 'SectionType.L';
      case 'P': return 'SectionType.P';
      case 'T': return 'SectionType.T';
      case 'R': return 'SectionType.L'; // Treat R as L for now
      case 'I': return 'SectionType.L'; // Treat I as L for now
      default: return 'SectionType.L';
    }
  }

  static parseGoaInstructors(instructorStr) {
    if (!instructorStr || instructorStr.trim() === '') {
      return [];
    }
    
    // Split by common separators including / and clean up
    const instructors = instructorStr
      .split(/[,\/\n\r]+/)
      .map(name => name.trim())
      .filter(name => name !== '');
    
    return instructors;
  }

  static parseGoaDaysHours(daysHrStr) {
    if (!daysHrStr || daysHrStr.trim() === '') {
      return [];
    }
    
    // Similar to Pilani logic - parse days and hours together
    // Format might be like "M W F 2-3" or "T Th 4-5"
    const parts = daysHrStr.trim().split(/\s+/);
    const days = [];
    const hours = [];
    
    for (const part of parts) {
      // Check if it's a day
      const dayMapping = {
        'M': 'DayOfWeek.M',
        'T': 'DayOfWeek.T', 
        'W': 'DayOfWeek.W',
        'Th': 'DayOfWeek.Th',
        'TH': 'DayOfWeek.Th',  // Goa uses uppercase TH
        'F': 'DayOfWeek.F',
        'S': 'DayOfWeek.S'
      };
      
      if (dayMapping[part]) {
        days.push(dayMapping[part]);
      } else if (part.includes('-')) {
        // Parse hour range like "2-3" or "4-5"
        const hourRange = part.split('-');
        if (hourRange.length === 2) {
          const startHour = parseInt(hourRange[0]);
          const endHour = parseInt(hourRange[1]);
          for (let h = startHour; h <= endHour; h++) {
            if (h >= 1 && h <= 12) {
              hours.push(h);
            }
          }
        }
      } else {
        // Single hour
        const hour = parseInt(part);
        if (hour >= 1 && hour <= 12) {
          hours.push(hour);
        }
      }
    }
    
    if (days.length > 0 && hours.length > 0) {
      return [{
        days: days,
        hours: hours
      }];
    }
    
    return [];
  }
  
  // These methods are kept for compatibility but not used in Goa parsing
  static parseSectionType(sectionId) {
    if (sectionId.startsWith('L')) return 'SectionType.L';
    if (sectionId.startsWith('P')) return 'SectionType.P';
    if (sectionId.startsWith('T')) return 'SectionType.T';
    return 'SectionType.L';
  }
  
  static parseDays(daysStr) {
    // Legacy method - not used for Goa parsing
    if (!daysStr) return [];
    
    const days = [];
    const dayMap = {
      'M': 'DayOfWeek.M',
      'T': 'DayOfWeek.T',
      'W': 'DayOfWeek.W',
      'Th': 'DayOfWeek.Th',
      'TH': 'DayOfWeek.Th',  // Goa uses uppercase TH
      'F': 'DayOfWeek.F',
      'S': 'DayOfWeek.S',
    };
    
    const parts = daysStr.split(' ');
    for (const part of parts) {
      const trimmed = part.trim();
      if (dayMap[trimmed]) {
        days.push(dayMap[trimmed]);
      }
    }
    
    return days;
  }
  
  static parseHours(hoursStr) {
    // Legacy method - not used for Goa parsing
    if (!hoursStr) return [];
    
    const cleaned = hoursStr.trim();
    
    try {
      const hourParts = cleaned.split(/\s+/);
      const hours = [];
      
      for (const part of hourParts) {
        const hourValue = parseInt(part);
        if (hourValue >= 1 && hourValue <= 12) {
          hours.push(hourValue);
        }
      }
      
      return hours;
    } catch (error) {
      console.log(`Error parsing hours "${hoursStr}": ${error}`);
      return [];
    }
  }
  
  static parseGoaMidSemExam(midSemDate, midSemTime) {
    if (!midSemDate || !midSemTime) return null;
    
    const dateStr = midSemDate.toString().trim();
    const timeStr = midSemTime.toString().trim();
    
    // Skip if TBA or 0 (undecided)
    if (dateStr.toUpperCase() === 'TBA' || timeStr === '0' || timeStr === '') {
      return null;
    }
    
    try {
      // Parse date in DD/MM/YY format
      const dateParts = dateStr.split('/');
      if (dateParts.length !== 3) return null;
      
      const day = parseInt(dateParts[0]);
      const month = parseInt(dateParts[1]);
      let year = parseInt(dateParts[2]);
      
      // Convert 2-digit year to 4-digit (assuming 20xx)
      if (year < 100) {
        year += 2000;
      }
      
      // Map time to existing time slots
      let timeSlot;
      const timeNum = parseInt(timeStr);
      switch (timeNum) {
        case 1: timeSlot = 'TimeSlot.MS1'; break;
        case 2: timeSlot = 'TimeSlot.MS2'; break;
        case 3: timeSlot = 'TimeSlot.MS3'; break;
        case 4: timeSlot = 'TimeSlot.MS4'; break;
        default: timeSlot = 'TimeSlot.MS1'; break;
      }
      
      const dateString = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T00:00:00.000Z`;
      
      return {
        date: dateString,
        timeSlot: timeSlot,
      };
    } catch (error) {
      console.log(`Error parsing Goa MidSem exam: ${error}`);
      return null;
    }
  }

  static parseGoaComprehensiveExam(compreDateStr) {
    if (!compreDateStr) return null;
    
    const examStr = compreDateStr.toString().trim();
    if (examStr === '') return null;
    
    try {
      // Format: DD/MM/YY (FN/AN)
      const match = examStr.match(/(\d{1,2}\/\d{1,2}\/\d{1,2})\s*\(([FA]N)\)/);
      if (!match) return null;
      
      const datePart = match[1];
      const timeSlotPart = match[2];
      
      // Parse date
      const dateParts = datePart.split('/');
      if (dateParts.length !== 3) return null;
      
      const day = parseInt(dateParts[0]);
      const month = parseInt(dateParts[1]);
      let year = parseInt(dateParts[2]);
      
      // Convert 2-digit year to 4-digit (assuming 20xx)
      if (year < 100) {
        year += 2000;
      }
      
      let timeSlot;
      if (timeSlotPart === 'FN') {
        timeSlot = 'TimeSlot.FN';
      } else if (timeSlotPart === 'AN') {
        timeSlot = 'TimeSlot.AN';
      } else {
        return null;
      }
      
      const dateString = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T00:00:00.000Z`;
      
      return {
        date: dateString,
        timeSlot: timeSlot,
      };
    } catch (error) {
      console.log(`Error parsing Goa Comprehensive exam: ${error}`);
      return null;
    }
  }
  
  // Legacy exam parsing methods - not used for Goa
  static parseMidSemExam(examStr) {
    // Legacy method - Goa uses parseGoaMidSemExam instead
    return null;
  }
  
  static parseEndSemExam(examStr) {
    // Legacy method - Goa uses parseGoaComprehensiveExam instead
    return null;
  }

  static parseExamSchedule(examData, isMidSem) {
    // Legacy method - not used for Goa parsing
    return null;
  }
  
  static getCellValue(row, index) {
    return row && row[index] !== undefined ? row[index] : null;
  }
  
  static formatCellValue(value) {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number') {
      return value % 1 === 0 ? value.toString() : value.toString();
    }
    return value.toString();
  }
  
  static getNumericValue(row, index) {
    const value = this.getCellValue(row, index);
    if (value === null || value === undefined) return 0;
    
    if (typeof value === 'number') {
      return Math.round(value);
    } else if (typeof value === 'string') {
      try {
        const doubleValue = parseFloat(value);
        return Math.round(doubleValue);
      } catch (error) {
        return 0;
      }
    }
    
    return 0;
  }
  
  static isEmptyRow(row) {
    return !row || row.every(cell => cell === null || cell === undefined || cell.toString().trim() === '');
  }
}

async function uploadGoaTimetableData(filePath) {
  try {
    const fileExtension = path.extname(filePath).toLowerCase();
    let courses;
    
    if (fileExtension === '.csv') {
      console.log('🔄 Parsing Goa CSV file...');
      courses = XlsxParserGoa.parseCsvFile(filePath);
    } else if (fileExtension === '.xlsx') {
      console.log('🔄 Parsing Goa XLSX file...');
      courses = XlsxParserGoa.parseXlsxFile(filePath);
    } else {
      throw new Error('Unsupported file format. Please use .csv or .xlsx files.');
    }
    
    console.log(`✅ Parsed ${courses.length} courses for Goa campus`);
    
    // Filter out any courses with invalid course codes
    const validCourses = courses.filter(course => {
      if (!course.courseCode || 
          course.courseCode.trim() === '' || 
          course.courseCode.trim() === '#N/A') {
        console.log(`Filtering out invalid course: ${JSON.stringify(course)}`);
        return false;
      }
      return true;
    });
    
    console.log(`📋 Filtered to ${validCourses.length} valid courses (removed ${courses.length - validCourses.length} invalid courses)`);
    
    // Write course codes to text file
    const courseCodesFile = path.join(__dirname, 'course_codes_goa.txt');
    const courseCodes = validCourses.map(course => course.courseCode).sort();
    fs.writeFileSync(courseCodesFile, courseCodes.join('\n'));
    console.log(`📝 Written ${courseCodes.length} course codes to ${courseCodesFile}`);
    
    // Use Goa-specific collection name
    const collectionName = 'goa-courses';
    console.log(`📚 Using collection: ${collectionName}`);
    
    // Clear existing data
    console.log('🔄 Clearing existing Goa course data...');
    const coursesRef = db.collection(collectionName);
    const snapshot = await coursesRef.get();
    
    const batch = db.batch();
    snapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    if (!snapshot.empty) {
      await batch.commit();
      console.log(`✅ Cleared ${snapshot.size} existing courses`);
    }
    
    // Upload new data in batches
    console.log('🔄 Uploading new Goa course data...');
    const batchSize = 500; // Firestore batch limit
    
    for (let i = 0; i < validCourses.length; i += batchSize) {
      const batch = db.batch();
      const courseBatch = validCourses.slice(i, i + batchSize);
      
      courseBatch.forEach(course => {
        const docRef = coursesRef.doc(course.courseCode);
        batch.set(docRef, course);
      });
      
      await batch.commit();
      console.log(`✅ Uploaded courses ${i + 1} to ${Math.min(i + batchSize, validCourses.length)}`);
    }
    
    // Update metadata
    console.log('🔄 Updating metadata for Goa campus...');
    const metadataCollectionName = process.env.TIMETABLE_METADATA_COLLECTION || 'timetable_metadata';
    const metadataDocName = 'current-goa';
    const metadataRef = db.collection(metadataCollectionName).doc(metadataDocName);
    await metadataRef.set({
      lastUpdated: new Date().toISOString(),
      totalCourses: validCourses.length,
      uploadedAt: new Date().toISOString(),
      version: Date.now().toString(),
      campus: 'Goa',
      campusCode: 'goa'
    });
    
    console.log('🎉 Upload completed successfully for Goa campus!');
    console.log(`📊 Total courses uploaded: ${validCourses.length}`);
    
  } catch (error) {
    console.error('❌ Error uploading Goa timetable data:', error);
    process.exit(1);
  }
}

// Main execution
async function main() {
  let filePath = process.argv[2];
  
  // If no path provided, look for default files in parent directory
  if (!filePath) {
    const defaultCsvPath = path.join(__dirname, '.', 'output-goa.csv');
    const defaultXlsxPath = path.join(__dirname, '..', 'DRAFT TIMETABLE I SEM 2025 -26 GOA.xlsx');
    
    if (fs.existsSync(defaultCsvPath)) {
      filePath = defaultCsvPath;
      console.log(`📂 Using default Goa CSV file: ${path.basename(defaultCsvPath)}`);
    } else if (fs.existsSync(defaultXlsxPath)) {
      filePath = defaultXlsxPath;
      console.log(`📂 Using default Goa XLSX file: ${path.basename(defaultXlsxPath)}`);
    } else {
      console.error('❌ Please provide the path to a Goa CSV or XLSX file');
      console.log('Usage: npm run upload-goa [path-to-file]');
      console.log('Or place "output-goa.csv" or "DRAFT TIMETABLE I SEM 2025 -26 GOA.xlsx" in the project root');
      process.exit(1);
    }
  }
  
  if (!fs.existsSync(filePath)) {
    console.error('❌ File not found:', filePath);
    process.exit(1);
  }
  
  console.log('🏫 Processing for Goa campus');
  await uploadGoaTimetableData(filePath);
}

main().catch(console.error);
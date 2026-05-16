import XLSX from 'xlsx';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { parse } from 'csv-parse/sync';
import {
  initializeFirebase,
  getCampusCollection,
  getCampusName,
  uploadCoursesToFirestore,
  updateMetadata,
  CellUtils,
} from './base-parser.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Parser functions (same as regular upload script)
class XlsxParser extends CellUtils {
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

    let currentRow = 2; // Skip header rows
    let lastCompCode = null;

    while (currentRow < data.length) {
      const row = data[currentRow];

      if (!row || this.isEmptyRow(row)) {
        currentRow++;
        continue;
      }

      const compCode = this.getCellValue(row, 0);
      const courseNo = this.getCellValue(row, 1);

      if (compCode && compCode.toString().trim() !== '') {
        lastCompCode = compCode.toString().trim();
      }

      if ((compCode && compCode.toString().trim() !== '') ||
          (courseNo && courseNo.toString().trim() !== '')) {
        const courseResult = this.parseCourseGroup(data, currentRow, lastCompCode);
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
        columns: false,
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

    let currentRow = 1;
    let lastCompCode = null;

    while (currentRow < data.length) {
      const row = data[currentRow];

      if (!row || this.isEmptyRow(row)) {
        currentRow++;
        continue;
      }

      const compCode = this.getCellValue(row, 0);
      const courseNo = this.getCellValue(row, 1);

      if (compCode && compCode.toString().trim() !== '') {
        lastCompCode = compCode.toString().trim();
      }

      if ((compCode && compCode.toString().trim() !== '') ||
          (courseNo && courseNo.toString().trim() !== '')) {
        const courseResult = this.parseCourseGroup(data, currentRow, lastCompCode);
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

  static parseCourseGroup(data, startRow, inheritedCompCode = null) {
    const mainRow = data[startRow];

    let compCode = this.getCellValue(mainRow, 0);
    const courseNo = this.getCellValue(mainRow, 1);
    let courseTitle = this.getCellValue(mainRow, 2);
    const lectureCredits = this.getNumericValue(mainRow, 3);
    const practicalCredits = this.getNumericValue(mainRow, 4);
    const totalCredits = this.getNumericValue(mainRow, 5);

    if ((!compCode || compCode.toString().trim() === '') && inheritedCompCode) {
      compCode = inheritedCompCode;
    }

    if (!courseTitle || courseTitle.toString().trim() === '') {
      courseTitle = 'Unknown';
    }

    if (!compCode || !courseNo) {
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
          currentRow++;
        }
      } else {
        const nextCompCode = this.getCellValue(row, 0);
        const nextCourseNo = this.getCellValue(row, 1);

        if (nextCompCode && nextCompCode.toString().trim() !== '') {
          break;
        }

        if (nextCourseNo && nextCourseNo.toString().trim() !== '' &&
            nextCourseNo.toString() !== courseNo.toString()) {
          break;
        }

        const sectionId = this.getCellValue(row, 6);
        if (sectionId && sectionId.toString().trim() !== '') {
          const sectionResult = this.parseSection(data, currentRow);
          if (sectionResult) {
            sections.push(sectionResult.section);
            currentRow = sectionResult.nextRow;
          } else {
            currentRow++;
          }
        } else {
          currentRow++;
        }
      }
    }

    const midSemExam = this.parseExamSchedule(this.getCellValue(mainRow, 11), true);
    const endSemExam = this.parseExamSchedule(this.getCellValue(mainRow, 12), false);

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
      const days = this.getCellValue(currentRowData, 9);
      const hours = this.getCellValue(currentRowData, 10);

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

      if (days && days.toString().trim() !== '' &&
          hours && hours.toString().trim() !== '') {
        const daysStr = days.toString().trim();
        const hoursStr = this.formatCellValue(hours);

        const daysList = this.parseDays(daysStr);
        const hoursList = this.parseHours(hoursStr);

        if (daysList.length > 0 && hoursList.length > 0) {
          schedule.push({
            days: daysList,
            hours: hoursList,
          });
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

  static parseDays(daysStr) {
    if (!daysStr) return [];

    const days = [];
    const dayMap = {
      'M': 'DayOfWeek.M',
      'T': 'DayOfWeek.T',
      'W': 'DayOfWeek.W',
      'Th': 'DayOfWeek.Th',
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

  static parseExamSchedule(examData, isMidSem) {
    if (!examData) return null;

    const examStr = examData.toString().trim();
    if (examStr === '') return null;

    try {
      if (isMidSem) {
        return this.parseMidSemExam(examStr);
      } else {
        return this.parseEndSemExam(examStr);
      }
    } catch (error) {
      return null;
    }
  }

  static parseMidSemExam(examStr) {
    const parts = examStr.split(' - ');
    if (parts.length < 2) return null;

    const datePart = parts[0].trim();
    const timePart = parts[1].trim();

    const dateComponents = datePart.split('/');
    if (dateComponents.length !== 2) return null;

    const day = parseInt(dateComponents[0]);
    const month = parseInt(dateComponents[1]);
    const year = 2025;

    let timeSlot;
    const cleanTimePart = timePart.replaceAll('.', ':').replaceAll(' ', '');

    // Updated for new midsem timeslots: 9:30-11, 11:30-1, 2-3:30, 4-5:30
    if (cleanTimePart.includes('9:30') && (cleanTimePart.includes('11:00') || cleanTimePart.includes('11'))) {
      timeSlot = 'TimeSlot.MS1';
    } else if (cleanTimePart.includes('11:30') && (cleanTimePart.includes('1:00') || cleanTimePart.includes('1'))) {
      timeSlot = 'TimeSlot.MS2';
    } else if ((cleanTimePart.includes('2:00') || cleanTimePart.includes('2')) && cleanTimePart.includes('3:30')) {
      timeSlot = 'TimeSlot.MS3';
    } else if ((cleanTimePart.includes('4:00') || cleanTimePart.includes('4')) && cleanTimePart.includes('5:30')) {
      timeSlot = 'TimeSlot.MS4';
    } else {
      if (cleanTimePart.includes('9:30') || cleanTimePart.includes('930')) {
        timeSlot = 'TimeSlot.MS1';
      } else if (cleanTimePart.includes('11:30') || cleanTimePart.includes('1130')) {
        timeSlot = 'TimeSlot.MS2';
      } else if (cleanTimePart.includes('2:00') || cleanTimePart.includes('200') || cleanTimePart.includes('2.00') || timePart === '2.00') {
        timeSlot = 'TimeSlot.MS3';
      } else if (cleanTimePart.includes('4:00') || cleanTimePart.includes('400') || cleanTimePart.includes('4.00') || timePart === '4.00') {
        timeSlot = 'TimeSlot.MS4';
      } else {
        console.log(`Unknown MidSem time format: ${timePart}`);
        timeSlot = 'TimeSlot.MS1';
      }
    }

    const dateString = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T00:00:00.000Z`;

    return {
      date: dateString,
      timeSlot: timeSlot,
    };
  }

  static parseEndSemExam(examStr) {
    const parts = examStr.split(' ');
    if (parts.length < 2) return null;

    const datePart = parts[0].trim();
    const timeSlotPart = parts[1].trim();

    const dateComponents = datePart.split('/');
    if (dateComponents.length !== 2) return null;

    const day = parseInt(dateComponents[0]);
    const month = parseInt(dateComponents[1]);
    const year = 2025;

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
  }
}

// Main execution
async function main() {
  let filePath = process.argv[2];
  let campus = process.argv[3] || 'hyderabad'; // Default to hyderabad for fresh updates

  // If no path provided, look for default files
  if (!filePath) {
    const defaultCsvPath = path.join(__dirname, '.', 'output-fresh.csv');
    const defaultXlsxPath = path.join(__dirname, '..', 'TIMETABLE-FRESH-HYD.xlsx');

    if (fs.existsSync(defaultCsvPath)) {
      filePath = defaultCsvPath;
      console.log(`Using default fresh CSV file: ${path.basename(defaultCsvPath)}`);
    } else if (fs.existsSync(defaultXlsxPath)) {
      filePath = defaultXlsxPath;
      console.log(`Using default fresh XLSX file: ${path.basename(defaultXlsxPath)}`);
    } else {
      console.error('Please provide the path to a fresh timetable CSV or XLSX file');
      console.log('Usage: node upload-timetable-fresh-hyd.js [path-to-file] [campus]');
      console.log('Campus options: hyderabad, hyd (default: hyderabad)');
      console.log('Or place "output-fresh.csv" or "TIMETABLE-FRESH-HYD.xlsx" in the project root');
      process.exit(1);
    }
  }

  if (!fs.existsSync(filePath)) {
    console.error('File not found:', filePath);
    process.exit(1);
  }

  console.log(`Processing SELECTIVE UPDATE for ${getCampusName(campus)} campus`);
  console.log(`Source: ${path.basename(filePath)}`);

  try {
    const fileExtension = path.extname(filePath).toLowerCase();
    let courses;

    if (fileExtension === '.csv') {
      console.log('Parsing CSV file...');
      courses = XlsxParser.parseCsvFile(filePath);
    } else if (fileExtension === '.xlsx') {
      console.log('Parsing XLSX file...');
      courses = XlsxParser.parseXlsxFile(filePath);
    } else {
      throw new Error('Unsupported file format. Please use .csv or .xlsx files.');
    }

    console.log(`Parsed ${courses.length} courses for ${campus}`);

    // Write course codes to text file
    const courseCodesFile = path.join(__dirname, `course_codes_fresh_${campus}.txt`);
    const courseCodes = courses.map(course => course.courseCode).sort();
    fs.writeFileSync(courseCodesFile, courseCodes.join('\n'));
    console.log(`Written ${courseCodes.length} course codes to ${courseCodesFile}`);

    const { db } = initializeFirebase();
    const collectionName = getCampusCollection(campus);

    // SELECTIVE UPDATE: Don't clear existing data, just overwrite matching docs
    await uploadCoursesToFirestore(db, courses, collectionName, { clearFirst: false });

    // Get current total course count for metadata update
    console.log('Getting updated course count...');
    const allCoursesSnapshot = await db.collection(collectionName).get();
    const totalCourses = allCoursesSnapshot.size;

    await updateMetadata(db, collectionName, {
      lastUpdated: new Date().toISOString(),
      totalCourses: totalCourses, // Total courses in collection after selective update
      uploadedAt: new Date().toISOString(),
      version: Date.now().toString(),
      campus: getCampusName(campus),
      campusCode: campus,
      lastSelectiveUpdate: {
        coursesUpdated: courses.length,
        updatedAt: new Date().toISOString(),
        sourcefile: path.basename(filePath)
      }
    }, { merge: true }); // Use merge to preserve existing metadata fields

    console.log('Selective upload completed successfully!');
    console.log(`Courses updated: ${courses.length}`);
    console.log(`Total courses in collection: ${totalCourses}`);
    console.log(`Updated course codes saved to: ${courseCodesFile}`);

  } catch (error) {
    console.error('Error uploading selective timetable data:', error);
    process.exit(1);
  }
}

main().catch(console.error);

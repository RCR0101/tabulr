import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/course.dart';

class XlsxParser {
  static Future<List<Course>> parseXlsxFile(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      return parseXlsxBytes(bytes);
    } catch (e) {
      throw Exception('Error parsing XLSX file: $e');
    }
  }

  static Future<List<Course>> parseXlsxBytes(Uint8List bytes) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      
      final sheet = excel.tables['Table 1'];
      if (sheet == null) {
        throw Exception('Table 1 sheet not found');
      }
      
      return _parseSheet(sheet);
    } catch (e) {
      throw Exception('Error parsing XLSX bytes: $e');
    }
  }

  static List<Course> _parseSheet(Sheet sheet) {
    List<Course> courses = [];
    final rows = sheet.rows;
    
    if (rows.length < 3) {
      throw Exception('Invalid sheet format');
    }
    
    // Skip the first two rows (title and header)
    int currentRow = 2;
    
    while (currentRow < rows.length) {
      final row = rows[currentRow];
      
      if (row.isEmpty || _isEmptyRow(row)) {
        currentRow++;
        continue;
      }
      
      final compCode = _getCellValue(row, 0);
      
      if (compCode != null && compCode.toString().isNotEmpty) {
        final courseData = _parseCourseGroup(rows, currentRow);
        if (courseData != null) {
          courses.add(courseData.course);
          currentRow = courseData.nextRow;
        } else {
          currentRow++;
        }
      } else {
        currentRow++;
      }
    }
    
    return courses;
  }

  static CourseParseResult? _parseCourseGroup(List<List<Data?>> rows, int startRow) {
    final mainRow = rows[startRow];
    
    final compCode = _getCellValue(mainRow, 0);
    final courseNo = _getCellValue(mainRow, 1);
    final courseTitle = _getCellValue(mainRow, 2);
    final lectureCredits = _getNumericValue(mainRow, 3);
    final practicalCredits = _getNumericValue(mainRow, 4);
    final totalCredits = _getNumericValue(mainRow, 5);
    
    if (compCode == null || courseNo == null || courseTitle == null) {
      return null;
    }
    
    List<Section> sections = [];
    int currentRow = startRow;
    
    while (currentRow < rows.length) {
      final row = rows[currentRow];
      
      if (currentRow == startRow) {
        final mainSection = _parseSection(row, startRow);
        if (mainSection != null) {
          sections.add(mainSection);
        }
      } else {
        final nextCompCode = _getCellValue(row, 0);
        
        if (nextCompCode != null && nextCompCode.toString().isNotEmpty) {
          break;
        }
        
        final sectionId = _getCellValue(row, 6);
        if (sectionId != null && sectionId.toString().isNotEmpty) {
          final section = _parseSection(row, currentRow);
          if (section != null) {
            sections.add(section);
          }
        }
      }
      
      currentRow++;
    }
    
    final midSemExam = _parseExamSchedule(_getCellValue(mainRow, 11), true);
    final endSemExam = _parseExamSchedule(_getCellValue(mainRow, 12), false);
    
    final course = Course(
      courseCode: courseNo.toString(),
      courseTitle: courseTitle.toString(),
      lectureCredits: lectureCredits,
      practicalCredits: practicalCredits,
      totalCredits: totalCredits,
      sections: sections,
      midSemExam: midSemExam,
      endSemExam: endSemExam,
    );
    
    return CourseParseResult(course: course, nextRow: currentRow);
  }

  static Section? _parseSection(List<Data?> row, int rowIndex) {
    final sectionId = _getCellValue(row, 6);
    final instructor = _getCellValue(row, 7);
    final room = _getCellValue(row, 8);
    final days = _getCellValue(row, 9);
    final hours = _getCellValue(row, 10);
    
    if (sectionId == null || sectionId.toString().isEmpty) {
      return null;
    }
    
    final sectionIdStr = sectionId.toString().trim();
    final sectionType = _parseSectionType(sectionIdStr);
    final daysList = _parseDays(days?.toString() ?? '');
    final hoursList = _parseHours(hours?.toString() ?? '');
    
    return Section(
      sectionId: sectionIdStr,
      type: sectionType,
      instructor: instructor?.toString() ?? '',
      room: room?.toString() ?? '',
      days: daysList,
      hours: hoursList,
    );
  }

  static SectionType _parseSectionType(String sectionId) {
    if (sectionId.startsWith('L')) return SectionType.L;
    if (sectionId.startsWith('P')) return SectionType.P;
    if (sectionId.startsWith('T')) return SectionType.T;
    return SectionType.L;
  }

  static List<DayOfWeek> _parseDays(String daysStr) {
    if (daysStr.isEmpty) return [];
    
    final days = <DayOfWeek>[];
    final dayMap = {
      'M': DayOfWeek.M,
      'T': DayOfWeek.T,
      'W': DayOfWeek.W,
      'Th': DayOfWeek.Th,
      'F': DayOfWeek.F,
      'S': DayOfWeek.S,
    };
    
    final parts = daysStr.split(' ');
    for (final part in parts) {
      final trimmed = part.trim();
      if (dayMap.containsKey(trimmed)) {
        days.add(dayMap[trimmed]!);
      }
    }
    
    return days;
  }

  static List<int> _parseHours(String hoursStr) {
    if (hoursStr.isEmpty) return [];
    
    try {
      final hourValue = int.parse(hoursStr.trim());
      return [hourValue];
    } catch (e) {
      return [];
    }
  }

  static ExamSchedule? _parseExamSchedule(dynamic examData, bool isMidSem) {
    if (examData == null) return null;
    
    final examStr = examData.toString().trim();
    if (examStr.isEmpty) return null;
    
    try {
      if (isMidSem) {
        return _parseMidSemExam(examStr);
      } else {
        return _parseEndSemExam(examStr);
      }
    } catch (e) {
      return null;
    }
  }

  static ExamSchedule? _parseMidSemExam(String examStr) {
    final parts = examStr.split(' - ');
    if (parts.length < 2) return null;
    
    final datePart = parts[0].trim();
    final timePart = parts[1].trim();
    
    final dateComponents = datePart.split('/');
    if (dateComponents.length != 2) return null;
    
    final day = int.parse(dateComponents[0]);
    final month = int.parse(dateComponents[1]);
    final year = 2025;
    
    // Parse MidSem time slot based on time string
    TimeSlot timeSlot;
    switch (timePart) {
      case '9:30-11:00AM':
      case '9:30AM-11:00AM':
        timeSlot = TimeSlot.MS1;
        break;
      case '11:30AM-1:00PM':
      case '11:30-1:00PM':
        timeSlot = TimeSlot.MS2;
        break;
      case '1:30-3:00PM':
      case '1:30PM-3:00PM':
        timeSlot = TimeSlot.MS3;
        break;
      case '3:30-5:00PM':
      case '3:30PM-5:00PM':
        timeSlot = TimeSlot.MS4;
        break;
      default:
        // Default to first slot if format doesn't match
        timeSlot = TimeSlot.MS1;
    }
    
    return ExamSchedule(
      date: DateTime(year, month, day),
      timeSlot: timeSlot,
    );
  }

  static ExamSchedule? _parseEndSemExam(String examStr) {
    final parts = examStr.split(' ');
    if (parts.length < 2) return null;
    
    final datePart = parts[0].trim();
    final timeSlotPart = parts[1].trim();
    
    final dateComponents = datePart.split('/');
    if (dateComponents.length != 2) return null;
    
    final day = int.parse(dateComponents[0]);
    final month = int.parse(dateComponents[1]);
    final year = 2025;
    
    TimeSlot timeSlot;
    if (timeSlotPart == 'FN') {
      timeSlot = TimeSlot.FN;
    } else if (timeSlotPart == 'AN') {
      timeSlot = TimeSlot.AN;
    } else {
      return null;
    }
    
    return ExamSchedule(
      date: DateTime(year, month, day),
      timeSlot: timeSlot,
    );
  }

  static dynamic _getCellValue(List<Data?> row, int index) {
    if (index >= row.length) return null;
    return row[index]?.value;
  }

  static int _getNumericValue(List<Data?> row, int index) {
    final value = _getCellValue(row, index);
    if (value == null) return 0;
    
    if (value is num) {
      return value.round();
    } else if (value is String) {
      try {
        final doubleValue = double.parse(value);
        return doubleValue.round();
      } catch (e) {
        return 0;
      }
    }
    
    return 0;
  }

  static bool _isEmptyRow(List<Data?> row) {
    return row.every((cell) => cell?.value == null || (cell?.value.toString().trim().isEmpty ?? true));
  }
}

class CourseParseResult {
  final Course course;
  final int nextRow;
  
  CourseParseResult({required this.course, required this.nextRow});
}
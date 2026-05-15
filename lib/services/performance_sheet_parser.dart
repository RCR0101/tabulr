import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/cgpa_data.dart';
import '../models/all_course.dart';

/// Parsed course entry from performance sheet (minimal data)
class ParsedCourseEntry {
  final String courseCode;
  final String grade;
  final String? tag; // HEL, DEL, EL

  ParsedCourseEntry({
    required this.courseCode,
    required this.grade,
    this.tag,
  });

  @override
  String toString() => '$courseCode: $grade${tag != null ? ' ($tag)' : ''}';
}

/// Parsed semester from performance sheet
class ParsedSemester {
  final String rawName; // e.g., "FIRST SEMESTER 2023-2024"
  final String normalizedName; // e.g., "Year 1 Sem 1"
  final List<ParsedCourseEntry> courses;

  ParsedSemester({
    required this.rawName,
    required this.normalizedName,
    required this.courses,
  });

  @override
  String toString() => '$normalizedName: ${courses.length} courses';
}

/// Result of parsing
class ParsedPerformanceSheet {
  final String? studentId;
  final String? studentName;
  final double? cgpa;
  final List<ParsedSemester> semesters;
  final List<String> warnings;

  ParsedPerformanceSheet({
    this.studentId,
    this.studentName,
    this.cgpa,
    required this.semesters,
    this.warnings = const [],
  });

  int get totalCourses =>
      semesters.fold(0, (sum, sem) => sum + sem.courses.length);
}

/// Service to parse BITS Pilani Performance Sheet PDFs
class PerformanceSheetParser {
  /// Parse performance sheet and extract course codes + grades
  static Future<ParsedPerformanceSheet> parse(Uint8List pdfBytes) async {
    final warnings = <String>[];
    String? studentId;
    String? studentName;
    double? cgpa;
    final semesters = <ParsedSemester>[];

    try {
      final document = PdfDocument(inputBytes: pdfBytes);
      final textExtractor = PdfTextExtractor(document);
      final fullText = textExtractor.extractText();
      document.dispose();

      warnings.add('Extracted ${fullText.length} chars');

      // Extract student info
      final studentIdMatch = RegExp(r'Student ID:\s*(\w+)').firstMatch(fullText);
      if (studentIdMatch != null) studentId = studentIdMatch.group(1);

      final nameMatch = RegExp(r'Name:\s*([A-Z][A-Z\s]+?)(?=\s*CGPA|\s*ERP|\n)').firstMatch(fullText);
      if (nameMatch != null) studentName = nameMatch.group(1)?.trim();

      final cgpaMatch = RegExp(r'CGPA:\s*([\d.]+)').firstMatch(fullText);
      if (cgpaMatch != null) cgpa = double.tryParse(cgpaMatch.group(1) ?? '');

      // Find all academic years for semester normalization
      final academicYears = <String>[];
      for (final match in RegExp(r'Academic Year (\d{4})\s*-\s*(\d{4})').allMatches(fullText)) {
        final year = '${match.group(1)}-${match.group(2)}';
        if (!academicYears.contains(year)) {
          academicYears.add(year);
        }
      }

      // Simple approach: Find course code followed by grade anywhere in text
      // Course code: 2-4 uppercase letters, space, F/G + 3 digits
      // Grade: A, A-, B, B-, C, C-, D, D-, E, NC, GD, PR
      // Pattern: Look for CODE followed eventually by a grade (with units in between)

      // First find all course codes
      final codePattern = RegExp(r'\b([A-Z]{2,4})\s+([FG]\d{3})\b');
      final allCodes = <String>{};
      for (final m in codePattern.allMatches(fullText)) {
        allCodes.add('${m.group(1)} ${m.group(2)}');
      }
      warnings.add('Found ${allCodes.length} unique course codes');

      // For each code, find the grade that follows it
      // The PDF structure is: CODE TITLE UNITS GRADE [TAG]
      // We look for: CODE ... (number like 1.0, 2.0, 3.0, 4.0, 5.0) ... GRADE
      final courseGrades = <String, ParsedCourseEntry>{};

      for (final code in allCodes) {
        // Escape the code for regex
        final escapedCode = code.replaceAll(' ', r'\s+');

        // Look for the code followed by units (number) and grade
        // More flexible pattern: CODE, then any text, then a number (units), then grade
        final pattern = RegExp(
          '$escapedCode[A-Z\\s&\\-\\.]+?(\\d+\\.?\\d*)\\s*([A-Z][+-]?|GD|PR|NC)(?:\\s*(HEL|DEL|EL))?',
          caseSensitive: true,
        );

        final match = pattern.firstMatch(fullText);
        if (match != null) {
          final grade = match.group(2)!;
          final tag = match.group(3);

          // Skip if grade looks like part of course title (e.g., "I" in "MATHEMATICS I")
          if (grade.length == 1 && 'IVX'.contains(grade)) continue;

          courseGrades[code] = ParsedCourseEntry(
            courseCode: code,
            grade: grade,
            tag: tag,
          );
        }
      }

      warnings.add('Matched ${courseGrades.length} courses with grades');

      // Group by semester
      final semesterPattern = RegExp(
        r'(FIRST|SECOND)\s+SEMESTER\s+(\d{4})\s*-?\s*(\d{4})',
        caseSensitive: false,
      );
      final summerPattern = RegExp(
        r'SUMMER\s+TERM\s+(\d{4})\s*-?\s*(\d{4})',
        caseSensitive: false,
      );

      // Find semester positions
      final semPositions = <int, String>{};
      for (final m in semesterPattern.allMatches(fullText)) {
        semPositions[m.start] = m.group(0)!;
      }
      for (final m in summerPattern.allMatches(fullText)) {
        semPositions[m.start] = m.group(0)!;
      }

      final sortedPos = semPositions.keys.toList()..sort();
      warnings.add('Found ${sortedPos.length} semester markers');

      if (sortedPos.isEmpty && courseGrades.isNotEmpty) {
        // No semester markers found, put all in one
        semesters.add(ParsedSemester(
          rawName: 'All Courses',
          normalizedName: 'Year 1 Sem 1',
          courses: courseGrades.values.toList(),
        ));
      } else {
        // For each semester section, find which courses appear in it
        for (int i = 0; i < sortedPos.length; i++) {
          final startPos = sortedPos[i];
          final endPos = i + 1 < sortedPos.length ? sortedPos[i + 1] : fullText.length;
          final section = fullText.substring(startPos, endPos);
          final semName = semPositions[startPos]!;
          final normName = _normalizeSemesterName(semName, academicYears);

          // Find courses in this section
          final semCourses = <ParsedCourseEntry>[];
          for (final code in allCodes) {
            if (section.contains(code) && courseGrades.containsKey(code)) {
              semCourses.add(courseGrades[code]!);
            }
          }

          if (semCourses.isNotEmpty) {
            semesters.add(ParsedSemester(
              rawName: semName,
              normalizedName: normName,
              courses: semCourses,
            ));
          }
        }
      }

      // If still no semesters but we have courses, something went wrong with sectioning
      if (semesters.isEmpty && courseGrades.isNotEmpty) {
        semesters.add(ParsedSemester(
          rawName: 'Imported Courses',
          normalizedName: 'Year 1 Sem 1',
          courses: courseGrades.values.toList(),
        ));
      }
    } catch (e) {
      warnings.add('Parse error: $e');
    }

    return ParsedPerformanceSheet(
      studentId: studentId,
      studentName: studentName,
      cgpa: cgpa,
      semesters: semesters,
      warnings: warnings,
    );
  }

  /// Normalize semester name to match app's format
  static String _normalizeSemesterName(
      String rawName, List<String> academicYears) {
    final upper = rawName.toUpperCase();

    // Handle summer term
    if (upper.contains('SUMMER')) {
      final match = RegExp(r'(\d{4})-(\d{4})').firstMatch(rawName);
      if (match != null) {
        return 'Summer ${match.group(1)}-${match.group(2)?.substring(2)}';
      }
      return 'Summer';
    }

    // Extract semester info
    final match = RegExp(
      r'(FIRST|SECOND)\s+SEMESTER\s+(\d{4})-(\d{4})',
      caseSensitive: false,
    ).firstMatch(rawName);

    if (match != null) {
      final isFirst = match.group(1)!.toUpperCase() == 'FIRST';
      final startYear = match.group(2)!;
      final yearKey = '$startYear-${match.group(3)}';

      final yearIndex = academicYears.indexOf(yearKey);
      final yearNum = yearIndex >= 0 ? yearIndex + 1 : 1;
      final semNum = isFirst ? 1 : 2;

      return 'Year $yearNum Sem $semNum';
    }

    return rawName;
  }

  /// Convert parsed data to CGPAData using course database for details
  static CGPAData toCGPAData(
    ParsedPerformanceSheet parsed,
    List<AllCourse> allCourses,
  ) {
    // Build lookup map for courses
    final courseMap = <String, AllCourse>{};
    for (final course in allCourses) {
      courseMap[course.courseCode.toUpperCase()] = course;
    }

    final semesterMap = <String, SemesterData>{};

    for (final semester in parsed.semesters) {
      final courses = <CourseEntry>[];

      for (final entry in semester.courses) {
        final lookup = courseMap[entry.courseCode.toUpperCase()];

        // Determine course type
        final isATC = entry.grade == 'GD' || entry.grade == 'PR';

        courses.add(CourseEntry(
          courseCode: entry.courseCode,
          courseTitle: lookup?.courseTitle ?? entry.courseCode,
          credits: lookup?.credits ?? 3.0, // Default to 3 if not found
          courseType: isATC ? 'ATC' : 'Normal',
          grade: entry.grade,
        ));
      }

      semesterMap[semester.normalizedName] = SemesterData(
        semesterName: semester.normalizedName,
        courses: courses,
      );
    }

    return CGPAData(semesters: semesterMap);
  }
}

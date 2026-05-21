import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/cgpa_data.dart';
import '../models/all_course.dart';

class ParsedCourseEntry {
  final String courseCode;
  final String grade;
  final String? tag;

  ParsedCourseEntry({
    required this.courseCode,
    required this.grade,
    this.tag,
  });

  @override
  String toString() => '$courseCode: $grade${tag != null ? ' ($tag)' : ''}';
}

class ParsedSemester {
  final String rawName;
  final String normalizedName;
  final List<ParsedCourseEntry> courses;

  ParsedSemester({
    required this.rawName,
    required this.normalizedName,
    required this.courses,
  });

  @override
  String toString() => '$normalizedName: ${courses.length} courses';
}

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

class PerformanceSheetParser {
  static const _validGrades = {
    'A', 'A-', 'B', 'B-', 'C', 'C-', 'D', 'D-', 'E', 'NC', 'GD', 'PR'
  };

  static const _validTags = {'HEL', 'DEL', 'EL'};

  // Course code: 2-4 uppercase letters + 1-3 spaces + F/G + 3 digits
  static final _courseCodePattern = RegExp(r'([A-Z]{2,4})\s{1,3}([FG]\d{3})');

  static final _semHeaderPattern = RegExp(
    r'(FIRST|SECOND)\s+SEMESTER\s+(\d{4})\s*-\s*(\d{4})',
    caseSensitive: false,
  );

  static final _summerHeaderPattern = RegExp(
    r'SUMMER\s+TERM\s+(\d{4})\s*-\s*(\d{4})',
    caseSensitive: false,
  );

  static final _pendingPattern = RegExp(
    r'Pending\s+Courses',
    caseSensitive: false,
  );

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

      final lines = fullText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      // Extract student info from early lines
      for (final line in lines.take(10)) {
        if (studentId == null) {
          final m = RegExp(r'Student ID:\s*(\w+)').firstMatch(line);
          if (m != null) studentId = m.group(1);
        }
        if (studentName == null) {
          final m = RegExp(r'Name:\s*([A-Z][A-Z\s]+?)(?=CGPA|ERP|\n|$)').firstMatch(line);
          if (m != null) studentName = m.group(1)?.trim();
        }
        if (cgpa == null) {
          final m = RegExp(r'CGPA:\s*([\d.]+)').firstMatch(line);
          if (m != null) cgpa = double.tryParse(m.group(1) ?? '');
        }
      }

      // Build academic year list for normalization
      final academicYears = <String>[];
      for (final line in lines) {
        for (final m in RegExp(r'Academic Year (\d{4})\s*-\s*(\d{4})').allMatches(line)) {
          final year = '${m.group(1)}-${m.group(2)}';
          if (!academicYears.contains(year)) academicYears.add(year);
        }
      }

      // Find pending courses cutoff
      int pendingCutoff = lines.length;
      for (int i = 0; i < lines.length; i++) {
        if (_pendingPattern.hasMatch(lines[i])) {
          pendingCutoff = i;
          break;
        }
      }

      // Process each data line
      int summerCounter = 0;
      for (int i = 0; i < pendingCutoff; i++) {
        final line = lines[i];

        // Skip non-data lines
        if (line.startsWith('Academic Year') ||
            line.startsWith('Completed') ||
            line.startsWith('Performance') ||
            line.startsWith('Count of')) continue;

        // Find semester headers in this line
        final semHeaders = <String>[];
        for (final m in _semHeaderPattern.allMatches(line)) {
          semHeaders.add(m.group(0)!);
        }
        for (final m in _summerHeaderPattern.allMatches(line)) {
          semHeaders.add(m.group(0)!);
        }

        if (semHeaders.isEmpty) continue;

        // Strip headers and column headers from the data
        String dataText = line;
        for (final header in semHeaders) {
          dataText = dataText.replaceFirst(header, '');
        }
        dataText = dataText.replaceAll(RegExp(r'Course No\.'), '');
        dataText = dataText.replaceAll(RegExp(r'Course Title'), '');
        dataText = dataText.replaceAll(RegExp(r'Units'), '');
        dataText = dataText.replaceAll(RegExp(r'Grade'), '');
        dataText = dataText.replaceAll(RegExp(r'Tag'), '');

        // Split into semester chunks using large whitespace gaps (10+ spaces)
        // This separates left-table (sem1) from right-table (sem2) data
        final rawChunks = dataText.split(RegExp(r'\s{10,}'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();

        // Merge tag-only chunks (HEL/DEL/EL) back onto the previous chunk
        final chunks = <String>[];
        for (final chunk in rawChunks) {
          final tokens = chunk.split(RegExp(r'\s+'));
          final isTagOnly = tokens.every((t) => _validTags.contains(t));
          if (isTagOnly && chunks.isNotEmpty) {
            chunks.last = '${chunks.last} $chunk';
          } else {
            chunks.add(chunk);
          }
        }

        final parsedChunks = <List<ParsedCourseEntry>>[];
        for (final chunk in chunks) {
          final courses = _extractCoursesFromChunk(chunk);
          if (courses.isNotEmpty) {
            parsedChunks.add(courses);
          }
        }

        // Assign chunks to semester headers
        for (int h = 0; h < semHeaders.length && h < parsedChunks.length; h++) {
          final header = semHeaders[h];
          final normName = _normalizeSemesterName(
            header, academicYears, summerCounter,
          );
          if (header.toUpperCase().contains('SUMMER')) summerCounter++;

          semesters.add(ParsedSemester(
            rawName: header,
            normalizedName: normName,
            courses: parsedChunks[h],
          ));
        }

        // If only one header but multiple chunks (e.g., single semester line)
        if (semHeaders.length == 1 && parsedChunks.length > 1) {
          final allCourses = parsedChunks.expand((c) => c).toList();
          if (semesters.isNotEmpty) {
            semesters.last = ParsedSemester(
              rawName: semesters.last.rawName,
              normalizedName: semesters.last.normalizedName,
              courses: allCourses,
            );
          }
        }
      }

      if (semesters.isEmpty) {
        warnings.add('No semesters found in PDF');
      }

      final total = semesters.fold(0, (int s, sem) => s + sem.courses.length);
      warnings.add('Parsed $total courses across ${semesters.length} semesters');
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

  /// Extract course code + grade pairs from a text chunk.
  /// The chunk structure is: [codes...] [titles...] [units...] [grades...] [tags...]
  static List<ParsedCourseEntry> _extractCoursesFromChunk(String chunk) {
    final results = <ParsedCourseEntry>[];

    // Step 1: Find all course codes and their positions
    final codeMatches = _courseCodePattern.allMatches(chunk).toList();
    if (codeMatches.isEmpty) return results;

    final codes = <String>[];
    int lastCodeEnd = 0;
    for (final m in codeMatches) {
      codes.add('${m.group(1)} ${m.group(2)}');
      lastCodeEnd = m.end;
    }

    // Step 2: Everything after the last course code contains titles, units, grades, tags
    final remainder = chunk.substring(lastCodeEnd);
    final tokens = remainder.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // Step 3: Walk tokens from the end to find tags, then grades, then units
    // Tags are at the very end, grades before them, units before grades
    final tags = <String>[];
    final grades = <String>[];

    // Scan from end: collect tags first, then grades, then the rest is titles+units
    int idx = tokens.length - 1;

    // Collect trailing tags and grades (they're intermixed at the end)
    // Work backwards: anything that's a tag or grade, collect it
    final endTokens = <_TokenType>[];
    while (idx >= 0) {
      final tok = tokens[idx];
      if (_validTags.contains(tok)) {
        endTokens.insert(0, _TokenType(tok, isTag: true));
        idx--;
      } else if (_validGrades.contains(tok)) {
        endTokens.insert(0, _TokenType(tok, isGrade: true));
        idx--;
      } else if (tok.length == 1 && 'ABCDE'.contains(tok)) {
        // Single letter grade
        endTokens.insert(0, _TokenType(tok, isGrade: true));
        idx--;
      } else if (RegExp(r'^\d+$').hasMatch(tok)) {
        // Hit the units block — stop
        break;
      } else {
        // Hit a title word — stop
        break;
      }
    }

    // Separate grades and tags from endTokens
    // The pattern per course is: [grade] [optional tag]
    // So we walk forward through endTokens assigning grade, then optional tag
    int tokenIdx = 0;
    while (tokenIdx < endTokens.length) {
      final t = endTokens[tokenIdx];
      if (t.isGrade) {
        grades.add(t.value);
        // Check if next token is a tag
        if (tokenIdx + 1 < endTokens.length && endTokens[tokenIdx + 1].isTag) {
          tags.add(endTokens[tokenIdx + 1].value);
          tokenIdx += 2;
        } else {
          tags.add('');
          tokenIdx++;
        }
      } else if (t.isTag) {
        // Tag without a preceding grade — skip
        tokenIdx++;
      } else {
        tokenIdx++;
      }
    }

    // Step 4: Pair courses with grades
    for (int c = 0; c < codes.length; c++) {
      if (c < grades.length) {
        results.add(ParsedCourseEntry(
          courseCode: codes[c],
          grade: grades[c],
          tag: (c < tags.length && tags[c].isNotEmpty) ? tags[c] : null,
        ));
      }
      // If no grade for this course (current semester), skip it
    }

    return results;
  }

  static String _normalizeSemesterName(
    String rawName,
    List<String> academicYears,
    int summerCount,
  ) {
    final upper = rawName.toUpperCase();

    if (upper.contains('SUMMER')) {
      return 'ST ${summerCount + 1}';
    }

    final match = RegExp(
      r'(FIRST|SECOND)\s+SEMESTER\s+(\d{4})\s*-\s*(\d{4})',
      caseSensitive: false,
    ).firstMatch(rawName);

    if (match != null) {
      final isFirst = match.group(1)!.toUpperCase() == 'FIRST';
      final startYear = match.group(2)!;
      final yearKey = '$startYear-${match.group(3)}';

      final yearIndex = academicYears.indexOf(yearKey);
      final yearNum = yearIndex >= 0 ? yearIndex + 1 : 1;
      final semNum = isFirst ? 1 : 2;

      return '$yearNum-$semNum';
    }

    return rawName;
  }

  static CGPAData toCGPAData(
    ParsedPerformanceSheet parsed,
    List<AllCourse> allCourses,
  ) {
    final courseMap = <String, AllCourse>{};
    for (final course in allCourses) {
      courseMap[course.courseCode.toUpperCase()] = course;
    }

    final semesterMap = <String, SemesterData>{};

    for (final semester in parsed.semesters) {
      final courses = <CourseEntry>[];

      for (final entry in semester.courses) {
        final lookup = courseMap[entry.courseCode.toUpperCase()];
        final isATC = entry.grade == 'GD' || entry.grade == 'PR';

        courses.add(CourseEntry(
          courseCode: entry.courseCode,
          courseTitle: lookup?.courseTitle ?? entry.courseCode,
          credits: lookup?.credits ?? 3.0,
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

class _TokenType {
  final String value;
  final bool isGrade;
  final bool isTag;

  _TokenType(this.value, {this.isGrade = false, this.isTag = false});
}

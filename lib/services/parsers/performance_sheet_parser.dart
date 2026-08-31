import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
// Deferred: syncfusion_flutter_pdf is ~1 MB and only runs when a student
// imports a performance sheet, which most sessions never do. On web this keeps
// it out of the startup bundle until the first parse; on native the annotation
// is a harmless no-op.
import 'package:syncfusion_flutter_pdf/pdf.dart' deferred as sf;
import '../../constants/app_constants.dart';
import '../../models/cgpa_data.dart';
import '../../models/course_type.dart';
import '../../models/all_course.dart';

class ParsedCourseEntry {
  final String courseCode;
  final String? grade;
  final String? tag;

  ParsedCourseEntry({
    required this.courseCode,
    required this.grade,
    this.tag,
  });

  @override
  String toString() =>
      '$courseCode: ${grade ?? 'Pending'}${tag != null ? ' ($tag)' : ''}';
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
  // 'I' is excluded: the tokeniser walks backwards from the end of a course
  // line, and a lone "I" is indistinguishable from the trailing numeral in
  // titles like "Mathematics I". An Incomplete is transient anyway — clause
  // 4.13 requires it to be replaced with a real grade within two weeks — so
  // missing it costs far less than mis-reading a course title as a grade.
  static final _validGrades = GradeConstants.allValid.difference({'I'});
  static const _validTags = {...GradeConstants.electiveTags, 'R'};

  // Course code: 2-4 uppercase letters + 1-3 spaces + F/G + 3 digits
  static final _courseCodePattern = RegExp(r'([A-Z]{2,4})\s{1,3}([FGK]\d{3}(?:-\d)?)');

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

  static const _maxPdfSize = AppLimits.maxPdfSize;
  static const _pdfMagic = [0x25, 0x50, 0x44, 0x46]; // %PDF

  static Future<ParsedPerformanceSheet> parse(Uint8List pdfBytes) async {
    final warnings = <String>[];
    String? studentId;
    String? studentName;
    double? cgpa;
    final semesters = <ParsedSemester>[];

    if (pdfBytes.length < 4 ||
        pdfBytes[0] != _pdfMagic[0] ||
        pdfBytes[1] != _pdfMagic[1] ||
        pdfBytes[2] != _pdfMagic[2] ||
        pdfBytes[3] != _pdfMagic[3]) {
      return ParsedPerformanceSheet(
        semesters: [],
        warnings: ['File is not a valid PDF'],
      );
    }

    if (pdfBytes.length > _maxPdfSize) {
      return ParsedPerformanceSheet(
        semesters: [],
        warnings: ['File is too large (max 10 MB)'],
      );
    }

    try {
      await sf.loadLibrary();
      final document = sf.PdfDocument(inputBytes: pdfBytes);
      final textExtractor = sf.PdfTextExtractor(document);
      final fullText = textExtractor.extractText();
      document.dispose();

      final lines = fullText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      // Extract student info from early lines
      for (final line in lines.take(10)) {
        studentId ??= extractStudentId(line);
        if (studentName == null) {
          final m = RegExp(r'Name:\s*([A-Z][A-Z\s]+?)(?=CGPA|ERP|\n|$)').firstMatch(line);
          if (m != null) studentName = _sanitize(m.group(1)?.trim(), maxLen: 100);
        }
        if (cgpa == null) {
          final m = RegExp(r'CGPA:\s*([\d.]+)').firstMatch(line);
          if (m != null) {
            final parsed = double.tryParse(m.group(1) ?? '');
            if (parsed != null && parsed >= 0 && parsed <= 10) cgpa = parsed;
          }
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
            line.startsWith('Count of')) {
          continue;
        }

        // Find semester headers in this line
        final headerMatches = <RegExpMatch>[
          ..._semHeaderPattern.allMatches(line),
          ..._summerHeaderPattern.allMatches(line),
        ]..sort((a, b) => a.start.compareTo(b.start));
        final semHeaders = headerMatches.map((m) => m.group(0)!).toList();

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

        final chunks = splitSemesterChunks(dataText);

        // Keep empty/ungraded columns in place. Compacting this list used to
        // pair a later column with an earlier header when a term had no grades.
        final parsedChunks = chunks.map(extractCoursesFromChunk).toList();

        // Assign chunks to semester headers
        for (int h = 0; h < semHeaders.length; h++) {
          final header = semHeaders[h];
          final normName = normalizeSemesterName(
            header, academicYears, summerCounter,
          );
          if (header.toUpperCase().contains('SUMMER')) summerCounter++;

          semesters.add(ParsedSemester(
            rawName: header,
            normalizedName: normName,
            courses: h < parsedChunks.length
                ? parsedChunks[h]
                : const <ParsedCourseEntry>[],
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

      final mergedSemesters = _mergeSemesterFragments(semesters);
      semesters
        ..clear()
        ..addAll(mergedSemesters);

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
  @visibleForTesting
  static List<String> splitSemesterChunks(String dataText) {
    // Oracle BI Publisher separates table columns with a whitespace gutter.
    // Four spaces is the safe structural boundary: a course code itself may
    // contain up to three, while titles and values use single spaces.
    final rawChunks = dataText.split(RegExp(r'\s{4,}'))
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty)
        .toList();

    // A sparse tag column can become its own chunk. Keep it with the preceding
    // semester instead of mistaking it for another table column.
    final chunks = <String>[];
    for (final chunk in rawChunks) {
      final tokens = chunk.split(RegExp(r'\s+'));
      final isTagOnly = tokens.every(_validTags.contains);
      if (isTagOnly && chunks.isNotEmpty) {
        chunks.last = '${chunks.last} $chunk';
      } else {
        chunks.add(chunk);
      }
    }
    return chunks;
  }

  @visibleForTesting
  static List<ParsedCourseEntry> extractCoursesFromChunk(String chunk) {
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
      } else if (RegExp(r'^\d+(\.\d+)?$').hasMatch(tok)) {
        // Hit the units block — stop
        break;
      } else {
        // Hit a title word — stop
        break;
      }
    }

    grades.addAll(endTokens.where((token) => token.isGrade).map((t) => t.value));

    final tagTokens =
        endTokens.where((token) => token.isTag).map((t) => t.value).toList();
    final firstTag = endTokens.indexWhere((token) => token.isTag);
    final lastGrade = endTokens.lastIndexWhere((token) => token.isGrade);
    final tagsFollowGrades = firstTag > lastGrade;

    if (tagsFollowGrades && tagTokens.length == codes.length) {
      // BI Publisher flattens a complete tag column after the grade column.
      tags.addAll(tagTokens);
    } else if (!tagsFollowGrades) {
      // Also support interleaved grade/tag text produced by simpler PDFs.
      for (final token in endTokens) {
        if (token.isGrade) {
          tags.add('');
        } else if (token.isTag && tags.isNotEmpty) {
          tags[tags.length - 1] = token.value;
        }
      }
    }

    // Step 4: Pair courses with grades. Registered courses in the active term
    // have no grade yet, but keeping them makes that term available to the grade
    // planner after import instead of dropping the entire semester.
    for (int c = 0; c < codes.length; c++) {
      final code = codes[c];
      if (!_courseCodePattern.hasMatch(code)) continue;
      final grade = c < grades.length && _validGrades.contains(grades[c])
          ? grades[c]
          : null;
      results.add(ParsedCourseEntry(
        courseCode: code,
        grade: grade,
        tag: (c < tags.length && _validTags.contains(tags[c])) ? tags[c] : null,
      ));
    }

    return results;
  }

  @visibleForTesting
  static String normalizeSemesterName(
    String rawName,
    List<String> academicYears,
    int summerCount,
  ) {
    final upper = rawName.toUpperCase();

    if (upper.contains('SUMMER')) {
      final match = _summerHeaderPattern.firstMatch(rawName);
      if (match != null) {
        final yearKey = '${match.group(1)}-${match.group(2)}';
        final yearIndex = academicYears.indexOf(yearKey);
        if (yearIndex >= 0) {
          // ST 1 follows year 2, ST 2 follows year 3, and so on. Counting only
          // summer headers mislabeled a student's first recorded summer after
          // year 3 as ST 1, placing repeats before their older regular attempt.
          return 'ST ${yearIndex < 1 ? 1 : yearIndex}';
        }
      }
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
        // ATCs minus NC — an NC report doesn't mark a course as ATC.
        final isATC = GradeConstants.atc.contains(entry.grade) &&
            entry.grade != 'NC';

        courses.add(CourseEntry(
          courseCode: entry.courseCode,
          courseTitle: lookup?.courseTitle ?? entry.courseCode,
          credits: lookup?.credits ?? 3.0,
          courseType: isATC ? CourseType.atc : CourseType.normal,
          grade: entry.grade,
        ));
      }

      final existing = semesterMap[semester.normalizedName];
      semesterMap[semester.normalizedName] = SemesterData(
        semesterName: semester.normalizedName,
        courses: [...?existing?.courses, ...courses],
      );
    }

    return CGPAData(semesters: semesterMap);
  }

  static List<ParsedSemester> _mergeSemesterFragments(
    List<ParsedSemester> semesters,
  ) {
    final merged = <String, ParsedSemester>{};
    for (final semester in semesters) {
      final existing = merged[semester.normalizedName];
      merged[semester.normalizedName] = existing == null
          ? semester
          : ParsedSemester(
              rawName: existing.rawName,
              normalizedName: existing.normalizedName,
              courses: [...existing.courses, ...semester.courses],
            );
    }
    return merged.values.toList();
  }

  @visibleForTesting
  static String? extractStudentId(String line) {
    final match = RegExp(
      r'Student ID:\s*([A-Z0-9]+?)(?=\s*(?:ERP\s*ID:|Status:|Name:|CGPA:|$))',
      caseSensitive: false,
    ).firstMatch(line);
    return _sanitize(match?.group(1), maxLen: 20);
  }

  static String? _sanitize(String? input, {int maxLen = 50}) {
    if (input == null || input.isEmpty) return null;
    final trimmed = input.length > maxLen ? input.substring(0, maxLen) : input;
    final cleaned = trimmed.replaceAll(RegExp(r'[^\w\s.\-/]'), '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}

class _TokenType {
  final String value;
  final bool isGrade;
  final bool isTag;

  _TokenType(this.value, {this.isGrade = false, this.isTag = false});
}

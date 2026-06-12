import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import '../../models/cgpa_data.dart';
import '../../models/all_course.dart';
import '../data/cgpa_service.dart';
import '../data/course_guide_service.dart';
import '../data/courses_master_service.dart';
import '../parsers/performance_sheet_parser.dart';
import 'course_catalog_service.dart';

class CGPACalculatorController extends ChangeNotifier {
  final CGPAService? _cgpaService;
  final CourseCatalogService? _coursesService;

  CGPACalculatorController({CGPAService? cgpaService, CourseCatalogService? coursesService})
      : _cgpaService = cgpaService,
        _coursesService = coursesService;

  CGPAService get _cgpa => _cgpaService ?? CGPAService();
  CourseCatalogService get _courses => _coursesService ?? CourseCatalogService();

  List<String> _semesters = [];
  CGPAData _cgpaData = CGPAData();
  List<AllCourse> _allCourses = [];
  bool _isLoading = true;
  bool _isSaving = false;

  List<String> get semesters => _semesters;
  CGPAData get cgpaData => _cgpaData;
  List<AllCourse> get allCourses => _allCourses;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    final results = await Future.wait([
      _courses.fetchAllCourses(),
      _cgpa.loadAllCGPAData(),
    ]);

    final cgpaData = results[1] as CGPAData;
    _allCourses = results[0] as List<AllCourse>;
    _cgpaData = cgpaData;

    if (cgpaData.semesters.isNotEmpty) {
      final savedKeys = cgpaData.semesters.keys.toSet();
      final ordered = SemesterConstants.all.where(savedKeys.contains).toList();
      final extra = savedKeys.difference(ordered.toSet());
      _semesters = [...ordered, ...extra];
    } else {
      _semesters = List.from(CGPAService.defaultSemesters);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> saveSemester(String semesterName) async {
    if (_isSaving) return false;

    _isSaving = true;
    notifyListeners();

    final semesterData = _cgpaData.semesters[semesterName];
    bool success = true;
    if (semesterData != null) {
      success = await _cgpa.saveSemesterData(semesterName, semesterData);
    }

    _isSaving = false;
    notifyListeners();
    return success;
  }

  bool addCourseToSemester(String semesterName, AllCourse course) {
    final semester = _cgpaData.semesters[semesterName] ??
        SemesterData(semesterName: semesterName);

    if (semester.courses.any((c) => c.courseCode == course.courseCode)) {
      return false;
    }

    final courseEntry = CourseEntry(
      courseCode: course.courseCode,
      courseTitle: course.courseTitle,
      credits: course.credits,
      courseType: course.type,
    );

    semester.courses.add(courseEntry);
    _cgpaData.semesters[semesterName] = semester;
    notifyListeners();
    return true;
  }

  void removeCourseFromSemester(String semesterName, int index) {
    final semester = _cgpaData.semesters[semesterName];
    if (semester != null) {
      semester.courses.removeAt(index);
      _cgpaData.semesters[semesterName] = semester;
      notifyListeners();
    }
  }

  void updateGrade(String semesterName, int courseIndex, String? grade) {
    final semester = _cgpaData.semesters[semesterName];
    if (semester != null && courseIndex < semester.courses.length) {
      semester.courses[courseIndex] =
          semester.courses[courseIndex].copyWith(grade: grade);
      _cgpaData.semesters[semesterName] = semester;
      notifyListeners();
    }
  }

  Future<void> removeSemester(String semesterName) async {
    _semesters.remove(semesterName);
    final updatedSemesters =
        Map<String, SemesterData>.from(_cgpaData.semesters);
    updatedSemesters.remove(semesterName);
    _cgpaData = _cgpaData.copyWith(semesters: updatedSemesters);
    notifyListeners();
    await _cgpa.deleteSemesterData(semesterName);
  }

  String nextNormalSemester() {
    int maxYear = 0;
    int maxSem = 0;
    final normalPattern = RegExp(r'^(\d+)-(\d+)$');
    for (final s in _semesters) {
      final m = normalPattern.firstMatch(s);
      if (m != null) {
        final y = int.parse(m.group(1)!);
        final sem = int.parse(m.group(2)!);
        if (y > maxYear || (y == maxYear && sem > maxSem)) {
          maxYear = y;
          maxSem = sem;
        }
      }
    }
    if (maxYear == 0) return '1-1';
    if (maxSem >= 2) return '${maxYear + 1}-1';
    return '$maxYear-${maxSem + 1}';
  }

  String nextSummerTerm() {
    int maxNum = 0;
    final stPattern = RegExp(r'^ST (\d+)$');
    for (final s in _semesters) {
      final m = stPattern.firstMatch(s);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > maxNum) maxNum = n;
      }
    }
    return 'ST ${maxNum + 1}';
  }

  bool addSemester(String name) {
    if (name.isEmpty || _semesters.contains(name)) return false;
    _semesters.add(name);
    notifyListeners();
    return true;
  }

  double cumulativeCgpa(String upToSemester) {
    final semIndex = _semesters.indexOf(upToSemester);
    if (semIndex < 0) return 0.0;

    final subset = <String, SemesterData>{};
    for (int i = 0; i <= semIndex; i++) {
      final sem = _cgpaData.semesters[_semesters[i]];
      if (sem != null) subset[_semesters[i]] = sem;
    }
    final partial = CGPAData(semesters: subset);
    return partial.cgpa;
  }

  bool isSuperseded(String semesterName, String courseCode) {
    final currentIdx = _semesters.indexOf(semesterName);
    if (currentIdx == -1) return false;
    for (var i = currentIdx + 1; i < _semesters.length; i++) {
      final later = _cgpaData.semesters[_semesters[i]];
      if (later != null &&
          later.courses.any((c) => c.courseCode == courseCode)) {
        return true;
      }
    }
    return false;
  }

  int importCoursesFromTimetable(
    Map<String, List<AllCourse>> selectedCourses,
  ) {
    int importedCount = 0;

    for (final entry in selectedCourses.entries) {
      final semesterName = entry.key;
      final courses = entry.value;

      if (!_semesters.contains(semesterName)) {
        _semesters.add(semesterName);
      }

      for (final course in courses) {
        if (addCourseToSemester(semesterName, course)) {
          importedCount++;
        }
      }
    }

    notifyListeners();
    return importedCount;
  }

  Future<({int importedCount, bool saveSuccess})> importPerformanceSheetData(
    ParsedPerformanceSheet parsed,
  ) async {
    final importedData =
        PerformanceSheetParser.toCGPAData(parsed, _allCourses);

    for (final entry in importedData.semesters.entries) {
      final semName = entry.key;
      final semData = entry.value;

      if (!_semesters.contains(semName)) {
        _semesters.add(semName);
      }

      _cgpaData = _cgpaData.copyWith(
        semesters: {
          ..._cgpaData.semesters,
          semName: semData,
        },
      );
    }

    notifyListeners();

    final semestersToSave = <String, SemesterData>{};
    for (final semName in importedData.semesters.keys) {
      final data = _cgpaData.semesters[semName];
      if (data != null) semestersToSave[semName] = data;
    }
    final success = await _cgpa.saveAllSemesters(semestersToSave);

    return (importedCount: parsed.totalCourses, saveSuccess: success);
  }

  Future<int> loadCDCs({
    required String branch,
    required String year,
    required String targetSemester,
  }) async {
    final courseGuideService = CourseGuideService();
    final cdcData = await courseGuideService.getCDCsForBranch(
      branch,
      semester: year,
    );

    final cdcCourses = cdcData[year] ?? <CourseGuideEntry>[];
    if (cdcCourses.isEmpty) return 0;

    int importedCount = 0;
    for (final cdcCourse in cdcCourses) {
      final existingSemester = _cgpaData.semesters[targetSemester];
      final courseExists = existingSemester?.courses
              .any((c) => c.courseCode == cdcCourse.code) ??
          false;

      if (!courseExists) {
        final masterService = CoursesMasterService();
        final title = cdcCourse.name.isNotEmpty
            ? cdcCourse.name
            : masterService.getTitle(cdcCourse.code);
        final allCourse = AllCourse(
          courseCode: cdcCourse.code,
          courseTitle: title,
          creditValue: cdcCourse.credits,
          type: 'Normal',
        );
        addCourseToSemester(targetSemester, allCourse);
        importedCount++;
      }
    }

    return importedCount;
  }

  static String getGradeDescription(String grade) {
    switch (grade) {
      case 'A':
        return '10 Grade Points';
      case 'A-':
        return '9 Grade Points';
      case 'B':
        return '8 Grade Points';
      case 'B-':
        return '7 Grade Points';
      case 'C':
        return '6 Grade Points';
      case 'C-':
        return '5 Grade Points';
      case 'D':
        return '4 Grade Points';
      case 'D-':
        return '3 Grade Points';
      case 'E':
        return '2 Grade Points';
      case 'SA':
        return 'Satisfactory';
      case 'US':
        return 'Unsatisfactory';
      case 'GD':
        return 'Good';
      case 'PR':
        return 'Poor';
      case 'NC':
        return 'Not Cleared';
      default:
        return '';
    }
  }

  List<AllCourse> searchCourses(String pattern) {
    return _courses.searchCourses(_allCourses, pattern);
  }
}

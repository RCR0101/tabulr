import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import '../../models/cgpa_data.dart';
import '../../models/course_type.dart';
import '../../models/all_course.dart';
import '../data/cgpa_service.dart';
import '../data/course_guide_service.dart';
import '../data/courses_master_service.dart';
import '../parsers/performance_sheet_parser.dart';
import 'course_catalog_service.dart';

/// Outcome of [CGPACalculatorController.saveSemester]: distinguishes a real
/// save from "there was nothing to persist" so the UI can give honest feedback.
enum SemesterSaveResult { saved, nothingToSave, failed }

/// Outcome of [CGPACalculatorController.addCourseToSemester]. A bool could not
/// say WHY an add was refused, and "already added" and "wrong credit basis"
/// need different things from the student.
enum AddCourseResult { added, duplicate, basisMismatch }

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

  /// Semesters with in-memory edits that haven't been persisted yet. Tracked
  /// per semester because saving is per-semester — saving one must not clear
  /// the unsaved flag for others.
  final Set<String> _dirtySemesters = {};

  List<String> get semesters => _semesters;
  CGPAData get cgpaData => _cgpaData;
  List<AllCourse> get allCourses => _allCourses;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  /// Whether any semester has unsaved edits.
  bool get hasUnsavedChanges => _dirtySemesters.isNotEmpty;

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

    _dirtySemesters.clear();
    _isLoading = false;
    notifyListeners();
  }

  Future<SemesterSaveResult> saveSemester(String semesterName) async {
    if (_isSaving) return SemesterSaveResult.failed;

    final semesterData = _cgpaData.semesters[semesterName];
    if (semesterData == null) return SemesterSaveResult.nothingToSave;

    _isSaving = true;
    notifyListeners();

    final success = await _cgpa.saveSemesterData(semesterName, semesterData);

    if (success) _dirtySemesters.remove(semesterName);
    _isSaving = false;
    notifyListeners();
    return success ? SemesterSaveResult.saved : SemesterSaveResult.failed;
  }

  AddCourseResult addCourseToSemester(String semesterName, AllCourse course) {
    final semester = _cgpaData.semesters[semesterName] ??
        SemesterData(semesterName: semesterName);

    if (semester.courses.any((c) => c.courseCode == course.courseCode)) {
      return AddCourseResult.duplicate;
    }

    // One basis per record. A student registers as one batch, so a record
    // holding both a 4-credit course and a 12-credit-hour one is not a load
    // anyone can have — and its CGPA would be an average of two different
    // quantities, weighted 1:3 against each other by accident.
    final existing = _cgpaData.isInCreditHours;
    if (existing != null && existing != course.isInCreditHours) {
      return AddCourseResult.basisMismatch;
    }

    final courseEntry = CourseEntry(
      courseCode: course.courseCode,
      courseTitle: course.courseTitle,
      credits: course.credits,
      isInCreditHours: course.isInCreditHours,
      courseType: CourseType.fromJson(course.type),
    );

    semester.courses.add(courseEntry);
    _cgpaData.semesters[semesterName] = semester;
    _dirtySemesters.add(semesterName);
    notifyListeners();
    return AddCourseResult.added;
  }

  void removeCourseFromSemester(String semesterName, int index) {
    final semester = _cgpaData.semesters[semesterName];
    if (semester != null) {
      semester.courses.removeAt(index);
      _cgpaData.semesters[semesterName] = semester;
      _dirtySemesters.add(semesterName);
      notifyListeners();
    }
  }

  void updateGrade(String semesterName, int courseIndex, String? grade) {
    final semester = _cgpaData.semesters[semesterName];
    if (semester != null && courseIndex < semester.courses.length) {
      semester.courses[courseIndex] =
          semester.courses[courseIndex].copyWith(grade: grade);
      _cgpaData.semesters[semesterName] = semester;
      _dirtySemesters.add(semesterName);
      notifyListeners();
    }
  }

  Future<void> removeSemester(String semesterName) async {
    _semesters.remove(semesterName);
    _dirtySemesters.remove(semesterName);
    final updatedSemesters =
        Map<String, SemesterData>.from(_cgpaData.semesters);
    updatedSemesters.remove(semesterName);
    _cgpaData = _cgpaData.copyWith(semesters: updatedSemesters);
    notifyListeners();
    await _cgpa.deleteSemesterData(semesterName);
  }

  /// The regular semester to offer next: the first **gap** in the progression,
  /// not one past the highest.
  ///
  /// Semesters run a fixed sequence (1-1, 1-2, 2-1, …), so a missing one is
  /// always unambiguous. Offering max + 1 meant deleting 1-2 from a year-3
  /// record left it permanently unreachable — the dialog just kept offering
  /// 4-1. Now the deleted one is exactly what comes back.
  String nextNormalSemester() {
    for (final s in SemesterConstants.regular) {
      if (!_semesters.contains(s)) return s;
    }
    // Past the catalogue's last year (a long degree) — keep the pattern going.
    final last = SemesterConstants.regular.last.split('-');
    return '${int.parse(last[0]) + 1}-1';
  }

  /// Likewise for summer terms. ST *n* presupposes ST *n−1*, so they always
  /// form a run from 1 — the first missing number both continues the run and
  /// repairs it when a middle term was deleted.
  String nextSummerTerm() {
    var n = 1;
    while (_semesters.contains('ST $n')) {
      n++;
    }
    return 'ST $n';
  }

  bool addSemester(String name) {
    if (name.isEmpty || _semesters.contains(name)) return false;
    _insertSemester(name);
    notifyListeners();
    return true;
  }

  /// Puts [name] at its place in the progression instead of at the end.
  ///
  /// [loadData] orders the list by [SemesterConstants.all], but every later
  /// append ignored that — so a semester added after load (re-adding a deleted
  /// one, a performance-sheet import, a timetable import) landed last whatever
  /// its name. That reordered the tabs and, worse, made [cumulativeCgpa] treat
  /// it as the newest semester. Names outside the catalogue still sort last,
  /// matching the load rule.
  void _insertSemester(String name) {
    final order = SemesterConstants.all.indexOf(name);
    if (order < 0) {
      _semesters.add(name);
      return;
    }
    // An unknown name indexes to -1, which never displaces a known one.
    final at = _semesters
        .indexWhere((s) => SemesterConstants.all.indexOf(s) > order);
    if (at < 0) {
      _semesters.add(name);
    } else {
      _semesters.insert(at, name);
    }
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
        _insertSemester(semesterName);
      }

      for (final course in courses) {
        if (addCourseToSemester(semesterName, course) == AddCourseResult.added) {
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
        _insertSemester(semName);
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
    // These were just persisted; drop any prior dirty flags for them.
    if (success) _dirtySemesters.removeAll(semestersToSave.keys);

    return (importedCount: parsed.totalCourses, saveSuccess: success);
  }

  /// Imports the CDCs of [primaryBranch] (plus [secondaryBranch] for a dual
  /// degree) at [semester] into [targetSemester]. Returns how many were added.
  /// [chosen] answers the optional CDCs — slots offering a choice of course.
  /// An unanswered choice is skipped rather than imported as one of its
  /// alternatives, which would put a course the student may not be taking into
  /// their grade sheet.
  Future<int> loadCDCs({
    required String primaryBranch,
    String? secondaryBranch,
    required String semester,
    required String targetSemester,
    Set<String> chosen = const {},
  }) async {
    final courseGuideService = CourseGuideService();
    final cdcData = await courseGuideService.getCDCsForDegree(
      primaryBranch,
      secondaryBranch,
      semester: semester,
    );

    final cdcSlots = cdcData[semester] ?? <CourseGuideSlot>[];
    if (cdcSlots.isEmpty) return 0;

    final unused = {...chosen};
    final cdcCourses = <CourseGuideEntry>[];
    for (final slot in cdcSlots) {
      if (!slot.isChoice) {
        cdcCourses.add(slot.first);
        continue;
      }
      for (final option in slot.options) {
        if (unused.remove(option.code)) {
          cdcCourses.add(option);
          break;
        }
      }
    }

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
        if (addCourseToSemester(targetSemester, allCourse) !=
            AddCourseResult.added) {
          continue;
        }
        importedCount++;
      }
    }

    return importedCount;
  }

  static String getGradeDescription(String grade) =>
      GradeConstants.descriptionFor(grade);

  List<AllCourse> searchCourses(String pattern) {
    return _courses.searchCourses(_allCourses, pattern);
  }
}

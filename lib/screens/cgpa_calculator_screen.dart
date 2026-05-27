import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:file_picker/file_picker.dart';
import '../services/data/cgpa_service.dart';
import '../utils/page_transitions.dart';
import '../widgets/common/shimmer_loading.dart';
import '../services/core/course_catalog_service.dart';
import '../services/data/auth_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/core/timetable_service.dart';
import '../services/data/auto_load_cdc_service.dart';
import '../services/ui/toast_service.dart';
import '../services/data/course_guide_service.dart';
import '../widgets/error_dialog.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';
import '../services/parsers/performance_sheet_parser.dart';
import '../services/data/courses_master_service.dart';
import '../models/cgpa_data.dart';
import '../models/all_course.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../utils/page_info_helper.dart';

import 'cg_booster_screen.dart';
import 'grade_planner_screen.dart';
import '../utils/design_constants.dart';
import '../utils/grade_utils.dart' as grade_utils;

class CGPACalculatorScreen extends StatefulWidget {
  const CGPACalculatorScreen({super.key});

  @override
  State<CGPACalculatorScreen> createState() => _CGPACalculatorScreenState();
}

class _CGPACalculatorScreenState extends State<CGPACalculatorScreen>
    with TickerProviderStateMixin {
  final CGPAService _cgpaService = CGPAService();
  final CourseCatalogService _coursesService = CourseCatalogService();
  final AuthService _authService = AuthService();
  final TimetableService _timetableService = TimetableService();

  late TabController _tabController;

  void _rebuildTabController({int? initialIndex}) {
    final prevIndex = _tabController.index;
    _tabController.dispose();
    final idx = (initialIndex ?? prevIndex).clamp(0, (_semesters.length - 1).clamp(0, 999));
    _tabController = TabController(
      length: _semesters.length,
      vsync: this,
      initialIndex: idx,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }
  List<String> _semesters = [];
  CGPAData _cgpaData = CGPAData();
  List<AllCourse> _allCourses = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _semesters = List.from(CGPAService.defaultSemesters);
    _tabController = TabController(length: _semesters.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load courses and CGPA data in parallel
    final results = await Future.wait([
      _coursesService.fetchAllCourses(),
      _cgpaService.loadAllCGPAData(),
    ]);

    setState(() {
      _allCourses = results[0] as List<AllCourse>;
      _cgpaData = results[1] as CGPAData;
      _isLoading = false;
    });
  }

  Future<void> _saveSemester(String semesterName) async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    final semesterData = _cgpaData.semesters[semesterName];
    if (semesterData != null) {
      final success = await _cgpaService.saveSemesterData(
        semesterName,
        semesterData,
      );

      if (mounted && !success) {
        ToastService.showError('Failed to save semester');
      }
    }

    setState(() => _isSaving = false);
  }

  void _addCourseToSemester(String semesterName, AllCourse course) {
    final semester =
        _cgpaData.semesters[semesterName] ??
        SemesterData(semesterName: semesterName);

    if (semester.courses.any((c) => c.courseCode == course.courseCode)) {
      ToastService.showError(
        '${course.courseCode} is already in $semesterName',
      );
      return;
    }

    setState(() {
      final courseEntry = CourseEntry(
        courseCode: course.courseCode,
        courseTitle: course.courseTitle,
        credits: course.credits,
        courseType: course.type,
      );

      semester.courses.add(courseEntry);
      _cgpaData.semesters[semesterName] = semester;
    });
  }

  void _removeCourseFromSemester(String semesterName, int index) {
    setState(() {
      final semester = _cgpaData.semesters[semesterName];
      if (semester != null) {
        semester.courses.removeAt(index);
        _cgpaData.semesters[semesterName] = semester;
      }
    });
  }

  void _updateGrade(String semesterName, int courseIndex, String? grade) {
    setState(() {
      final semester = _cgpaData.semesters[semesterName];
      if (semester != null && courseIndex < semester.courses.length) {
        semester.courses[courseIndex] = semester.courses[courseIndex].copyWith(
          grade: grade,
        );
        _cgpaData.semesters[semesterName] = semester;
      }
    });
  }

  Future<void> _importCoursesFromTimetable() async {
    try {
      // Load all user's timetables
      final allTimetables = await _timetableService.getAllTimetables();

      if (allTimetables.isEmpty) {
        _showErrorDialog(
          'No timetables found. Please create a timetable first.',
        );
        return;
      }

      if (!mounted) return;

      // Show course selection dialog
      final selectedCourses = await showDialog<Map<String, List<AllCourse>>>(
        context: context,
        builder:
            (context) => _CourseSelectionDialog(
              timetables: allTimetables,
              semesters: _semesters,
            ),
      );

      if (selectedCourses == null || selectedCourses.isEmpty) {
        return; // User cancelled or selected nothing
      }

      // Import the selected courses
      int importedCount = 0;

      for (final entry in selectedCourses.entries) {
        final semesterName = entry.key;
        final courses = entry.value;

        // Ensure semester exists
        if (!_semesters.contains(semesterName)) {
          setState(() {
            _semesters.add(semesterName);
            _rebuildTabController();
          });
        }

        // Add courses to semester
        for (final course in courses) {
          // Check if course already exists in this semester
          final existingSemester = _cgpaData.semesters[semesterName];
          final courseExists =
              existingSemester?.courses.any(
                (c) => c.courseCode == course.courseCode,
              ) ??
              false;

          if (!courseExists) {
            _addCourseToSemester(semesterName, course);
            importedCount++;
          }
        }
      }

      if (mounted && importedCount > 0) {
        ToastService.showSuccess(
          'Imported $importedCount course${importedCount != 1 ? 's' : ''}!',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error importing courses: $e');
      }
    }
  }

  Future<void> _importFromPerformanceSheet() async {
    try {
      // Pick PDF file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final file = result.files.first;
      if (file.bytes == null) {
        _showErrorDialog('Could not read the selected file.');
        return;
      }

      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Parsing Performance Sheet...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Parse the PDF
      final parsed = await PerformanceSheetParser.parse(file.bytes!);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (parsed.semesters.isEmpty) {
        _showErrorDialog(
          'Could not find any courses in the PDF.\n'
          '${parsed.warnings.isNotEmpty ? 'Warnings: ${parsed.warnings.join(", ")}' : ''}',
        );
        return;
      }

      if (!mounted) return;

      // Show preview dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _PerformanceSheetPreviewDialog(
          parsed: parsed,
          allCourses: _allCourses,
        ),
      );

      if (confirmed != true) return;

      // Convert and import
      final importedData = PerformanceSheetParser.toCGPAData(parsed, _allCourses);

      // Merge with existing data (override semesters that were imported)
      setState(() {
        for (final entry in importedData.semesters.entries) {
          final semName = entry.key;
          final semData = entry.value;

          // Add semester to list if not exists
          if (!_semesters.contains(semName)) {
            _semesters.add(semName);
          }

          // Override semester data
          _cgpaData = _cgpaData.copyWith(
            semesters: {
              ..._cgpaData.semesters,
              semName: semData,
            },
          );
        }

        _rebuildTabController();
      });

      // Batch-save all imported semesters in one Firestore write
      final semestersToSave = <String, SemesterData>{};
      for (final semName in importedData.semesters.keys) {
        final data = _cgpaData.semesters[semName];
        if (data != null) semestersToSave[semName] = data;
      }
      final success = await _cgpaService.saveAllSemesters(semestersToSave);

      if (mounted) {
        if (success) {
          ToastService.showSuccess(
            'Imported ${parsed.totalCourses} courses from ${parsed.semesters.length} semesters!',
          );
        } else {
          ToastService.showError('Failed to save imported data');
        }
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        _showErrorDialog('Error importing from Performance Sheet: $e');
      }
    }
  }

  Future<void> _loadCDCs() async {
    try {
      print('Starting Load CDCs process...');
      if (kDebugMode) {
        print('Debug mode enabled');
      }
      
      // Show branch and semester selection dialog
      final autoLoadService = AutoLoadCDCService();
      final result = await autoLoadService.showBranchYearDialog(context);
      
      if (result == null) {
        print('User cancelled CDC loading');
        return; // User cancelled
      }

      print('Selected branch: ${result.branch}, semester: ${result.year}');

      if (!mounted) return;

      // Get CDC courses from branch structure
      final courseGuideService = CourseGuideService();
      final cdcData = await courseGuideService.getCDCsForBranch(
        result.branch,
        semester: result.year,
      );

      final cdcCourses = cdcData[result.year] ?? <CourseGuideEntry>[];
      print('Found ${cdcCourses.length} CDC courses total');

      if (cdcCourses.isEmpty) {
        ToastService.showInfo(
          'No CDC courses found for the selected branch and year',
        );
        return;
      }

      // Convert to AllCourse objects and add to semester
      int importedCount = 0;
      // Use the currently selected semester instead of creating a new one
      final semesterName = _semesters[_tabController.index];
      
      print('Adding courses to currently selected semester: $semesterName');
      print('CDC courses are from semester: ${result.year}');

      // Add courses to semester
      for (final cdcCourse in cdcCourses) {
        print('Processing course: ${cdcCourse.code} - ${cdcCourse.name}');
        
        // Check if course already exists in this semester
        final existingSemester = _cgpaData.semesters[semesterName];
        final courseExists = existingSemester?.courses.any(
          (c) => c.courseCode == cdcCourse.code,
        ) ?? false;

        if (!courseExists) {
          print('Adding new course: ${cdcCourse.code}');
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
          _addCourseToSemester(semesterName, allCourse);
          importedCount++;
        } else {
          print('Course ${cdcCourse.code} already exists, skipping');
        }
      }

      print('Successfully imported $importedCount courses');

      if (mounted) {
        if (importedCount > 0) {
          ToastService.showSuccess(
            'Added $importedCount CDC course${importedCount != 1 ? 's' : ''} from ${result.year} to $semesterName!',
          );
        } else {
          final totalCourses = cdcCourses.length;
          ToastService.showInfo(
            'All $totalCourses CDC course${totalCourses != 1 ? 's' : ''} from ${result.year} already exist in $semesterName',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error loading CDCs: $e');
      }
    }
  }

  void _showSemesterSGPADetails() {
    if (_cgpaData.semesters.isEmpty) return;

    final semestersWithData = _cgpaData.semesters.entries
        .where((entry) => entry.value.courses.isNotEmpty)
        .toList();

    if (semestersWithData.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: ResponsiveService.isMobile(context) ? 340 : 400,
            maxHeight: ResponsiveService.isMobile(context) ? 500 : 600,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.analytics_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Semester Breakdown',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'SGPA for each semester',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  shrinkWrap: true,
                  itemCount: semestersWithData.length,
                  itemBuilder: (context, index) {
                    final entry = semestersWithData[index];
                    final semesterName = entry.key;
                    final semesterData = entry.value;
                    final sgpa = semesterData.sgpa;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  semesterName,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.school_rounded,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${semesterData.courses.length} courses • ${semesterData.totalCredits.toStringAsFixed(0)} credits',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _getSGPAColor(sgpa).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _getSGPAColor(sgpa).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  sgpa.toStringAsFixed(2),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: _getSGPAColor(sgpa),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'SGPA',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: _getSGPAColor(sgpa),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calculate_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Overall CGPA: ${_cgpaData.cgpa.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSGPAColor(double sgpa) {
    final scheme = Theme.of(context).colorScheme;
    if (sgpa >= 9.0) return scheme.primary;
    if (sgpa >= 8.0) return scheme.secondary;
    if (sgpa >= 7.0) return Color.lerp(scheme.primary, scheme.secondary, 0.5)!;
    if (sgpa >= 6.0) return Color.lerp(scheme.secondary, scheme.error, 0.5)!;
    return scheme.error;
  }

  void _showSemesterCreditsDetails() {
    if (_cgpaData.semesters.isEmpty) return;

    final semestersWithData = _cgpaData.semesters.entries
        .where((entry) => entry.value.courses.isNotEmpty)
        .toList();

    if (semestersWithData.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: ResponsiveService.isMobile(context) ? 340 : 400,
            maxHeight: ResponsiveService.isMobile(context) ? 500 : 600,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.school_rounded,
                        color: Theme.of(context).colorScheme.secondary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Credits Breakdown',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Credits for each semester',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  shrinkWrap: true,
                  itemCount: semestersWithData.length,
                  itemBuilder: (context, index) {
                    final entry = semestersWithData[index];
                    final semesterName = entry.key;
                    final semesterData = entry.value;
                    final credits = semesterData.totalCredits;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Theme.of(context).colorScheme.secondary.withValues(alpha: 0.8),
                                  Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  semesterName,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.book_rounded,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${semesterData.courses.length} courses enrolled',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _getCreditsColor(credits).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _getCreditsColor(credits).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  credits.toStringAsFixed(0),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: _getCreditsColor(credits),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Credits',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: _getCreditsColor(credits),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.school_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Total Credits: ${_cgpaData.semesters.values.fold<double>(0.0, (sum, sem) => sum + sem.totalCredits).toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCreditsColor(double credits) {
    final scheme = Theme.of(context).colorScheme;
    if (credits >= 24) return scheme.primary;
    if (credits >= 20) return scheme.secondary;
    if (credits >= 16) return Color.lerp(scheme.primary, scheme.secondary, 0.5)!;
    if (credits >= 12) return Color.lerp(scheme.secondary, scheme.error, 0.5)!;
    return scheme.error;
  }

  void _removeSemester(String semesterName) async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Remove Semester',
      message: 'Remove "$semesterName" and all its courses?',
      confirmLabel: 'Remove',
      isDangerous: true,
    );

    if (confirmed) {
      setState(() {
        _semesters.remove(semesterName);
        final updatedSemesters = Map<String, SemesterData>.from(_cgpaData.semesters);
        updatedSemesters.remove(semesterName);
        _cgpaData = _cgpaData.copyWith(semesters: updatedSemesters);
        _rebuildTabController();
      });
      await _cgpaService.deleteSemesterData(semesterName);
    }
  }

  String _nextNormalSemester() {
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

  String _nextSummerTerm() {
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

  void _addSemester(String name) {
    if (name.isNotEmpty && !_semesters.contains(name)) {
      setState(() {
        _semesters.add(name);
        _rebuildTabController(initialIndex: _semesters.length - 1);
      });
    }
  }

  void _addCustomSemester() {
    final nextNormal = _nextNormalSemester();
    final nextSummer = _nextSummerTerm();
    AppDialog.adaptive(
      context: context,
      title: 'Add Semester',
      icon: Icons.add_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: Icon(Icons.school_rounded, color: Theme.of(context).colorScheme.primary),
            title: Text('Semester $nextNormal'),
            subtitle: const Text('Regular semester'),
            tileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
            onTap: () {
              Navigator.pop(context);
              _addSemester(nextNormal);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: Icon(Icons.wb_sunny_rounded, color: Theme.of(context).colorScheme.tertiary),
            title: Text(nextSummer),
            subtitle: const Text('Summer term'),
            tileColor: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.06),
            onTap: () {
              Navigator.pop(context);
              _addSemester(nextSummer);
            },
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authService.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('CGPA Calculator')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: AppDesign.muted(context)),
                const SizedBox(height: 16),
                Text(
                  'Please sign in to use the CGPA Calculator',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('CGPA Calculator')),
        body: const CourseListSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CGPA Calculator'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _semesters.length + 1,
              itemBuilder: (context, index) {
                if (index == _semesters.length) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ActionChip(
                      avatar: Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      label: const Text('Add'),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                      onPressed: _addCustomSemester,
                    ),
                  );
                }

                final sem = _semesters[index];
                final isSelected = _tabController.index == index;
                final semester = _cgpaData.semesters[sem];
                final sgpa = semester?.sgpa ?? 0.0;
                final hasData = semester != null && semester.courses.isNotEmpty;

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onLongPress: () => _removeSemester(sem),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(sem),
                            if (hasData) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.25)
                                      : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  sgpa.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.onPrimary
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          _tabController.animateTo(index);
                          setState(() {});
                        },
                        selectedColor: Theme.of(context).colorScheme.primary,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          PageInfoHelper.infoButton(context, PageInfoHelper.cgpaCalculator),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: 'Reload Data',
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 22),
            tooltip: 'More',
            onSelected: (value) {
              if (!_authService.isAuthenticated) return;
              switch (value) {
                case 'grade_planner':
                  Navigator.push(context, FadeSlidePageRoute(page: GradePlannerScreen(cgpaData: _cgpaData)));
                  break;
                case 'cg_booster':
                  Navigator.push(context, FadeSlidePageRoute(page: CGBoosterScreen(cgpaData: _cgpaData)));
                  break;
                case 'load_cdcs':
                  _loadCDCs();
                  break;
                case 'import_timetable':
                  _importCoursesFromTimetable();
                  break;
                case 'import_pdf':
                  _importFromPerformanceSheet();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'grade_planner', child: ListTile(leading: Icon(Icons.calculate_outlined), title: Text('Grade Planner'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'cg_booster', child: ListTile(leading: Icon(Icons.bolt_outlined), title: Text('CG Booster'), contentPadding: EdgeInsets.zero)),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'load_cdcs', child: ListTile(leading: Icon(Icons.school_outlined), title: Text('Load CDCs'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'import_timetable', child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Import from Timetable'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'import_pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Import Performance Sheet'), contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCGPASummary(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children:
                  _semesters.map((sem) => _buildSemesterView(sem)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCGPASummary() {
    final isMobile = ResponsiveService.isMobile(context);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 6),
      child:
          isMobile
              ? Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => _showSemesterSGPADetails(),
                      child: _buildSummaryCard(
                        'CGPA',
                        _cgpaData.cgpa.toStringAsFixed(2),
                        Icons.grade_rounded,
                        isPrimary: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showSemesterCreditsDetails(),
                      child: _buildSummaryCard(
                        'Credits',
                        _cgpaData.semesters.values
                            .fold<double>(
                              0.0,
                              (sum, sem) => sum + sem.totalCredits,
                            )
                            .toStringAsFixed(0),
                        Icons.school_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      'Semesters',
                      _cgpaData.semesters.length.toString(),
                      Icons.calendar_view_month_rounded,
                    ),
                  ),
                ],
              )
              : Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showSemesterSGPADetails(),
                      child: _buildSummaryCard(
                        'Overall CGPA',
                        _cgpaData.cgpa.toStringAsFixed(2),
                        Icons.grade_rounded,
                        isPrimary: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showSemesterCreditsDetails(),
                      child: _buildSummaryCard(
                        'Total Credits',
                        _cgpaData.semesters.values
                            .fold<double>(
                              0.0,
                              (sum, sem) => sum + sem.totalCredits,
                            )
                            .toStringAsFixed(0),
                        Icons.school_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      'Semesters',
                      _cgpaData.semesters.length.toString(),
                      Icons.calendar_view_month_rounded,
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildSummaryCard(
    String label,
    String value,
    IconData icon, {
    bool isPrimary = false,
  }) {
    final isMobile = ResponsiveService.isMobile(context);

    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHigh.withOpacity(isPrimary ? 0.9 : 0.7),
            Theme.of(
              context,
            ).colorScheme.surfaceContainer.withOpacity(isPrimary ? 0.6 : 0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
        border: Border.all(
          color:
              isPrimary
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
                  : Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isMobile ? 16 : 18,
            color:
                isPrimary
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: isMobile ? 18 : 22,
              fontWeight: FontWeight.bold,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: isMobile ? 10 : 11,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  double _cumulativeCgpa(String upToSemester) {
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

  Widget _buildSemesterView(String semesterName) {
    final semester = _cgpaData.semesters[semesterName];
    final courses = semester?.courses ?? [];

    return Column(
      children: [
        // Semester stats
        Container(
          margin: EdgeInsets.symmetric(
            horizontal: ResponsiveService.isMobile(context) ? 12 : 20,
            vertical: 6,
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'SGPA',
                  semester?.sgpa.toStringAsFixed(2) ?? '0.00',
                  Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem(
                  'CGPA',
                  _cumulativeCgpa(semesterName).toStringAsFixed(2),
                  Icons.grade_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem(
                  'Courses · Credits',
                  '${courses.length} · ${semester?.totalCredits.toStringAsFixed(0) ?? '0'}',
                  Icons.school_rounded,
                ),
              ),
            ],
          ),
        ),

        // Course list
        Expanded(
          child:
              courses.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.06),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.book_rounded,
                              size:
                                  ResponsiveService.isMobile(context) ? 48 : 56,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.35),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'No courses added yet',
                            style: Theme.of(
                              context,
                            ).textTheme.headlineSmall?.copyWith(
                              fontSize:
                                  ResponsiveService.isMobile(context) ? 18 : 20,
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add courses to start calculating your SGPA',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(
                              fontSize:
                                  ResponsiveService.isMobile(context) ? 14 : 15,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                  : LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = ResponsiveService.isMobile(context);
                      final crossAxisCount =
                          isMobile ? 1 : (constraints.maxWidth > 1200 ? 3 : 2);

                      return GridView.builder(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 16,
                          vertical: 8,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: isMobile ? 2.8 : 2.8,
                          crossAxisSpacing: isMobile ? 8 : 12,
                          mainAxisSpacing: isMobile ? 8 : 12,
                        ),
                        itemCount: courses.length,
                        itemBuilder: (context, index) {
                          return _buildCourseCard(
                            semesterName,
                            index,
                            courses[index],
                          );
                        },
                      );
                    },
                  ),
        ),

        // Action buttons
        Container(
          padding: EdgeInsets.fromLTRB(
            ResponsiveService.isMobile(context) ? 12 : 20,
            12,
            ResponsiveService.isMobile(context) ? 12 : 20,
            ResponsiveService.isMobile(context) ? 16 : 20,
          ),
          child:
              ResponsiveService.isMobile(context)
                  ? Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 44,
                          child: Semantics(
                            label: 'Add Course',
                            button: true,
                            child: FilledButton.tonalIcon(
                            onPressed: () => _showAddCourseDialog(semesterName),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text(
                              'Add Course',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed:
                                _isSaving
                                    ? null
                                    : () => _saveSemester(semesterName),
                            icon:
                                _isSaving
                                    ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                      ),
                                    )
                                    : const Icon(Icons.save_rounded, size: 16),
                            label: const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.primary,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                  : Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _showAddCourseDialog(semesterName),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text(
                              'Add Course',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 140,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed:
                              _isSaving
                                  ? null
                                  : () => _saveSemester(semesterName),
                          icon:
                              _isSaving
                                  ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  )
                                  : const Icon(Icons.save_rounded, size: 18),
                          label: const Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    final isMobile = ResponsiveService.isMobile(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
        border: Border.all(
          color: scheme.outline.withValues(alpha: AppDesign.opacityDivider),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isMobile ? 14 : 16,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
          SizedBox(height: isMobile ? 3 : 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: isMobile ? 9 : 10,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  bool _isSuperseded(String semesterName, String courseCode) {
    final semesterKeys = _semesters;
    final currentIdx = semesterKeys.indexOf(semesterName);
    if (currentIdx == -1) return false;
    for (var i = currentIdx + 1; i < semesterKeys.length; i++) {
      final later = _cgpaData.semesters[semesterKeys[i]];
      if (later != null && later.courses.any((c) => c.courseCode == courseCode)) {
        return true;
      }
    }
    return false;
  }

  Widget _buildCourseCard(String semesterName, int index, CourseEntry course) {
    final gradeOptions =
        course.courseType == 'ATC'
            ? CGPAService.atcGrades
            : CGPAService.normalGrades;
    final isMobile = ResponsiveService.isMobile(context);
    final superseded = course.courseType == 'Normal' &&
        _isSuperseded(semesterName, course.courseCode);

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: AppDesign.opacityDivider),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.courseCode,
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 15,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          course.courseTitle,
                          style: TextStyle(
                            fontSize: isMobile ? 11 : 12,
                            color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: scheme.onSurface.withValues(alpha: AppDesign.opacityLow),
                    onPressed:
                        () => _removeCourseFromSemester(semesterName, index),
                    tooltip: 'Remove course',
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${course.credits} cr',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (superseded)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Superseded',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: scheme.error.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildGradeSelector(
                      course.grade,
                      gradeOptions,
                      (value) => _updateGrade(semesterName, index, value),
                    ),
                  ),
                ],
              ),
              if (course.grade != null && course.courseType == 'Normal')
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calculate_outlined,
                        size: 13,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${course.gradePoints.toStringAsFixed(1)} × ${course.credits} = ${course.totalGradePoints.toStringAsFixed(2)} pts',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.45),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradeSelector(
    String? selectedGrade,
    List<String> gradeOptions,
    Function(String?) onChanged,
  ) {
    final isMobile = ResponsiveService.isMobile(context);
    final colorScheme = Theme.of(context).colorScheme;
    final gradeColor = selectedGrade != null ? _getGradeColor(selectedGrade) : null;

    return Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: isMobile ? 44 : 48,
        decoration: BoxDecoration(
          color: selectedGrade != null
              ? gradeColor!.withValues(alpha: 0.08)
              : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectedGrade != null
                ? gradeColor!.withValues(alpha: 0.4)
                : colorScheme.outline.withValues(alpha: 0.2),
            width: selectedGrade != null ? 2 : 1,
          ),
          boxShadow: selectedGrade != null
              ? [
                  BoxShadow(
                    color: gradeColor!.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedGrade,
            isExpanded: true,
            isDense: false,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            focusColor: Colors.transparent,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
            ),
            hint: Row(
              children: [
                Icon(
                  Icons.grade_outlined,
                  size: isMobile ? 18 : 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 12),
                Text(
                  'Select Grade',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: isMobile ? 14 : 16,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            selectedItemBuilder: (context) {
              return gradeOptions.map((grade) {
                final color = _getGradeColor(grade);
                return Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          grade,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 12 : 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        grade,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList();
            },
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
            ),
            borderRadius: BorderRadius.circular(12),
            elevation: 2,
            dropdownColor: colorScheme.surfaceContainer,
            menuMaxHeight: 320,
            items: gradeOptions.map((grade) {
              final gradeColor = _getGradeColor(grade);
              final description = _getGradeDescription(grade);

              return DropdownMenuItem<String>(
                value: grade,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 28,
                        decoration: BoxDecoration(
                          color: gradeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            grade,
                            style: TextStyle(
                              color: gradeColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: isMobile ? 13 : 14,
                            color: colorScheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Color _getGradeColor(String grade) => grade_utils.getGradeColor(grade, scheme: Theme.of(context).colorScheme);

  String _getGradeDescription(String grade) {
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

  void _showErrorDialog(String message) {
    ErrorDialog.show(context, message);
  }

  void _showAddCourseDialog(String semesterName) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveService.isMobile(context) ? 320 : 500,
                maxHeight: ResponsiveService.isMobile(context) ? 400 : 500,
              ),
              child: Padding(
                padding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.all(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.add_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Add Course',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'For $semesterName',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TypeAheadField<AllCourse>(
                      builder: (context, controller, focusNode) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'Search Course',
                            hintText: 'Enter course code or title',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(
                              Icons.search_outlined,
                              size: 20,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        );
                      },
                      suggestionsCallback: (pattern) {
                        return _coursesService.searchCourses(
                          _allCourses,
                          pattern,
                        );
                      },
                      itemBuilder: (context, course) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          title: Text(
                            course.courseCode,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            course.courseTitle,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  course.type == 'ATC'
                                      ? Theme.of(
                                        context,
                                      ).colorScheme.tertiaryContainer
                                      : Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              course.type,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color:
                                    course.type == 'ATC'
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.onTertiaryContainer
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        );
                      },
                      onSelected: (course) {
                        _addCourseToSemester(semesterName, course);
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Start typing to search for courses',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

// Dialog for selecting courses from timetables
class _CourseSelectionDialog extends StatefulWidget {
  final List<Timetable> timetables;
  final List<String> semesters;

  const _CourseSelectionDialog({
    required this.timetables,
    required this.semesters,
  });

  @override
  State<_CourseSelectionDialog> createState() => _CourseSelectionDialogState();
}

class _CourseSelectionDialogState extends State<_CourseSelectionDialog> {
  Timetable? _selectedTimetable;
  String? _selectedSemester;
  final Set<String> _selectedCourses = {}; // selected course codes

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          ResponsiveService.getAdaptiveBorderRadius(context, 16),
        ),
      ),
      child: Container(
        width: isMobile ? double.infinity : 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: ResponsiveService.getAdaptivePadding(
                context,
                const EdgeInsets.all(20),
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(
                    ResponsiveService.getAdaptiveBorderRadius(context, 16),
                  ),
                  topRight: Radius.circular(
                    ResponsiveService.getAdaptiveBorderRadius(context, 16),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Import Courses from Timetable',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: ResponsiveService.getAdaptivePadding(
                    context,
                    const EdgeInsets.all(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Timetable selector
                      Text(
                        'Select Timetable',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(
                            ResponsiveService.getAdaptiveBorderRadius(
                              context,
                              8,
                            ),
                          ),
                        ),
                        child: DropdownButton<Timetable>(
                          value: _selectedTimetable,
                          isExpanded: true,
                          underline: Container(),
                          hint: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('Choose a timetable'),
                          ),
                          onChanged: (timetable) {
                            setState(() {
                              _selectedTimetable = timetable;
                              _selectedCourses.clear();
                              _selectedSemester = null;
                            });
                          },
                          items:
                              widget.timetables.asMap().entries.map((entry) {
                                final index = entry.key;
                                final timetable = entry.value;

                                String displayName =
                                    timetable.name.isNotEmpty &&
                                            timetable.name !=
                                                'Untitled Timetable'
                                        ? timetable.name
                                        : 'Timetable ${index + 1}';

                                final courseCount =
                                    timetable.selectedSections.length;

                                return DropdownMenuItem<Timetable>(
                                  value: timetable,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(displayName)),
                                        Text(
                                          '$courseCount course${courseCount != 1 ? 's' : ''}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),

                      if (_selectedTimetable != null) ...[
                        const SizedBox(height: 24),
                        
                        // Semester selector
                        Text(
                          'Select Semester',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(
                              ResponsiveService.getAdaptiveBorderRadius(
                                context,
                                8,
                              ),
                            ),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedSemester,
                            isExpanded: true,
                            underline: Container(),
                            hint: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Choose a semester for all courses'),
                            ),
                            onChanged: (semester) {
                              setState(() {
                                _selectedSemester = semester;
                              });
                            },
                            items: widget.semesters.map((semester) {
                              return DropdownMenuItem<String>(
                                value: semester,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(semester),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        if (_selectedSemester != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Select Courses',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All selected courses will be added to $_selectedSemester',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // List of courses from selected timetable
                          ..._buildCourseList(),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Footer with action buttons
            Container(
              padding: ResponsiveService.getAdaptivePadding(
                context,
                const EdgeInsets.all(16),
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedCourses.length} selected',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed:
                            _selectedCourses.isEmpty ? null : _importCourses,
                        child: const Text('Import'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCourseList() {
    if (_selectedTimetable == null) return [];

    // Get unique courses from the timetable
    final uniqueCourses = <String, Course>{};
    for (final selectedSection in _selectedTimetable!.selectedSections) {
      if (!uniqueCourses.containsKey(selectedSection.courseCode)) {
        final course = _selectedTimetable!.availableCourses.firstWhere(
          (c) => c.courseCode == selectedSection.courseCode,
          orElse:
              () => Course(
                courseCode: selectedSection.courseCode,
                courseTitle: 'Unknown Course',
                lectureCredits: 0,
                practicalCredits: 0,
                totalCredits: 3,
                sections: [],
              ),
        );
        uniqueCourses[selectedSection.courseCode] = course;
      }
    }

    if (uniqueCourses.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No courses found in this timetable',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ];
    }

    return uniqueCourses.entries.map((entry) {
      final courseCode = entry.key;
      final course = entry.value;
      final isSelected = _selectedCourses.contains(courseCode);

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: isSelected ? 2 : 0,
        color:
            isSelected
                ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            ResponsiveService.getAdaptiveBorderRadius(context, 8),
          ),
          side: BorderSide(
            color:
                isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Checkbox
              Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedCourses.add(courseCode);
                    } else {
                      _selectedCourses.remove(courseCode);
                    }
                  });
                },
              ),
              const SizedBox(width: 12),

              // Course info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courseCode,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.courseTitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Credits badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${course.totalCredits}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }


  void _importCourses() {
    if (_selectedTimetable == null || _selectedCourses.isEmpty || _selectedSemester == null) return;

    // Convert selected courses to AllCourse objects for the selected semester
    final coursesToImport = <String, List<AllCourse>>{};
    coursesToImport[_selectedSemester!] = [];

    for (final courseCode in _selectedCourses) {
      final course = _selectedTimetable!.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse:
            () => Course(
              courseCode: courseCode,
              courseTitle: 'Unknown Course',
              lectureCredits: 0,
              practicalCredits: 0,
              totalCredits: 3,
              sections: [],
            ),
      );

      coursesToImport[_selectedSemester!]!.add(
        AllCourse(
          courseCode: course.courseCode,
          courseTitle: course.courseTitle,
          creditValue: course.totalCredits,
          type: 'Normal',
        ),
      );
    }

    Navigator.pop(context, coursesToImport);
  }
}

/// Dialog to preview parsed performance sheet data before importing
class _PerformanceSheetPreviewDialog extends StatelessWidget {
  final ParsedPerformanceSheet parsed;
  final List<AllCourse> allCourses;

  const _PerformanceSheetPreviewDialog({
    required this.parsed,
    required this.allCourses,
  });

  @override
  Widget build(BuildContext context) {
    // Build lookup for course info
    final courseMap = <String, AllCourse>{};
    for (final course in allCourses) {
      courseMap[course.courseCode.toUpperCase()] = course;
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Import Preview'),
                if (parsed.studentName != null)
                  Text(
                    parsed.studentName!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: ResponsiveService.isMobile(context) ? MediaQuery.of(context).size.width * 0.85 : 400,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(
                    label: 'Semesters',
                    value: '${parsed.semesters.length}',
                  ),
                  _SummaryItem(
                    label: 'Courses',
                    value: '${parsed.totalCourses}',
                  ),
                  if (parsed.cgpa != null)
                    _SummaryItem(
                      label: 'CGPA',
                      value: parsed.cgpa!.toStringAsFixed(2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Warning
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will override existing data for the imported semesters.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Semester list
            Expanded(
              child: ListView.builder(
                itemCount: parsed.semesters.length,
                itemBuilder: (context, index) {
                  final semester = parsed.semesters[index];
                  return ExpansionTile(
                    title: Text(semester.normalizedName),
                    subtitle: Text(
                      '${semester.courses.length} courses',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    children: semester.courses.map((course) {
                      final lookup =
                          courseMap[course.courseCode.toUpperCase()];
                      final notFound = lookup == null;

                      return ListTile(
                        dense: true,
                        leading: notFound
                            ? Icon(
                                Icons.warning_amber,
                                color: Theme.of(context).colorScheme.error,
                                size: 18,
                              )
                            : null,
                        title: Text(
                          course.courseCode,
                          style: TextStyle(
                            color: notFound
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          lookup?.courseTitle ?? 'Course not found in database',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getGradeColor(course.grade, context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            course.grade,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Import'),
        ),
      ],
    );
  }

  Color _getGradeColor(String grade, BuildContext context) => grade_utils.getGradeColor(grade, scheme: Theme.of(context).colorScheme);
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer
                    .withValues(alpha: 0.7),
              ),
        ),
      ],
    );
  }
}

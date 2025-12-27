import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/cgpa_service.dart';
import '../services/all_courses_service.dart';
import '../services/auth_service.dart';
import '../services/responsive_service.dart';
import '../services/timetable_service.dart';
import '../services/auto_load_cdc_service.dart';
import '../services/toast_service.dart';
import '../services/course_guide_service.dart';
import '../services/secure_logger.dart';
import '../widgets/app_drawer_widget.dart';
import '../models/cgpa_data.dart';
import '../models/all_course.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import 'timetables_screen.dart';
import 'acad_drives_screen.dart';

class CGPACalculatorScreen extends StatefulWidget {
  const CGPACalculatorScreen({super.key});

  @override
  State<CGPACalculatorScreen> createState() => _CGPACalculatorScreenState();
}

class _CGPACalculatorScreenState extends State<CGPACalculatorScreen>
    with SingleTickerProviderStateMixin {
  final CGPAService _cgpaService = CGPAService();
  final AllCoursesService _coursesService = AllCoursesService();
  final AuthService _authService = AuthService();
  final TimetableService _timetableService = TimetableService();

  late TabController _tabController;
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Semester saved successfully!'
                  : 'Failed to save semester',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }

    setState(() => _isSaving = false);
  }

  void _addCourseToSemester(String semesterName, AllCourse course) {
    setState(() {
      final semester =
          _cgpaData.semesters[semesterName] ??
          SemesterData(semesterName: semesterName);
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
            _tabController.dispose();
            _tabController = TabController(
              length: _semesters.length,
              vsync: this,
            );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully imported $importedCount course${importedCount != 1 ? 's' : ''}!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error importing courses: $e');
      }
    }
  }

  Future<void> _loadCDCs() async {
    try {
      SecureLogger.info('DATA', 'Starting Load CDCs process', {'operation': 'load_cdcs'});
      if (kDebugMode) {
        SecureLogger.debug('DATA', 'Debug mode enabled', {'mode': 'debug'});
      }
      
      // Show branch and semester selection dialog
      final autoLoadService = AutoLoadCDCService();
      final result = await autoLoadService.showBranchYearDialog(context);
      
      if (result == null) {
        SecureLogger.info('UI', 'User cancelled CDC loading', {'user_action': 'cancel'});
        return; // User cancelled
      }

      SecureLogger.info('DATA', 'Selected branch and semester for CDC loading', {
        'branch': result.branch,
        'semester': result.year,
        'operation': 'load_cdcs'
      });

      if (!mounted) return;

      // Get CDC courses directly from course guide data
      final courseGuideService = CourseGuideService();
      final semesters = await courseGuideService.getAllSemesters();
      
      SecureLogger.dataOperation('load', 'semesters_course_guide', true, {
        'semester_count': semesters.length,
        'source': 'course_guide'
      });
      
      // Convert semester format (e.g., "3-1" to "semester_3_1")
      final semesterId = 'semester_${result.year.replaceAll('-', '_')}';
      SecureLogger.info('DATA', 'Looking for semester ID', {
        'semester_id': semesterId,
        'operation': 'find_semester'
      });
      
      final cdcCourses = <CourseGuideEntry>[];
      
      // Find the specific semester
      final targetSemester = semesters.where((s) => s.semesterId == semesterId).firstOrNull;
      if (targetSemester != null) {
        SecureLogger.info('DATA', 'Found target semester', {
          'semester_name': targetSemester.name,
          'operation': 'find_semester'
        });
        // Get the full branch name for searching
        final branchCodeToName = {
          'A1': 'Chemical',
          'A2': 'Civil',
          'A3': 'Electrical and Electronics',
          'A4': 'Mechanical',
          'A5': 'Pharma',
          'A7': 'Computer Science',
          'A8': 'Electronics and Instrumentation',
          'AA': 'Electronics and Communication',
          'AB': 'Manufacturing',
          'AD': 'Math and Computing',
          'AJ': 'Biotechnology',
          'B1': 'MSc Biology',
          'B2': 'MSc Chemistry',
          'B3': 'MSc Economics',
          'B4': 'MSc Mathematics',
          'B5': 'MSc Physics',
        };
        
        final branchFullName = branchCodeToName[result.branch];
        
        for (final group in targetSemester.groups) {
          SecureLogger.debug('DATA', 'Checking course group', {
            'group_id': group.groupId,
            'branches': group.branches.toString(),
            'operation': 'filter_groups'
          });
          // Check if group contains either the branch code or the full branch name
          bool containsBranch = group.branches.contains(result.branch) || 
                               (branchFullName != null && group.branches.contains(branchFullName));
          
          if (containsBranch) {
            SecureLogger.info('DATA', 'Group matches, adding courses', {
              'course_count': group.courses.length,
              'group_id': group.groupId,
              'operation': 'add_group_courses'
            });
            cdcCourses.addAll(group.courses);
          }
        }
      } else {
        SecureLogger.warning('DATA', 'Target semester not found', {
          'semester_id': semesterId,
          'operation': 'find_semester'
        });
      }

      SecureLogger.dataOperation('load', 'cdc_courses', true, {
        'course_count': cdcCourses.length,
        'operation': 'load_cdcs'
      });

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
      
      SecureLogger.info('DATA', 'Adding courses to currently selected semester', {
        'semester_name': semesterName,
        'operation': 'add_to_semester'
      });
      SecureLogger.info('DATA', 'CDC courses source semester', {
        'source_semester': result.year,
        'operation': 'load_cdcs'
      });

      // Add courses to semester
      for (final cdcCourse in cdcCourses) {
        SecureLogger.debug('DATA', 'Processing CDC course', {
          'course_code': cdcCourse.code,
          'course_name': cdcCourse.name,
          'operation': 'add_course'
        });
        
        // Check if course already exists in this semester
        final existingSemester = _cgpaData.semesters[semesterName];
        final courseExists = existingSemester?.courses.any(
          (c) => c.courseCode == cdcCourse.code,
        ) ?? false;

        if (!courseExists) {
          SecureLogger.info('DATA', 'Adding new CDC course', {
            'course_code': cdcCourse.code,
            'operation': 'add_course'
          });
          final allCourse = AllCourse(
            courseCode: cdcCourse.code,
            courseTitle: cdcCourse.name,
            u: cdcCourse.credits.toString(),
            type: 'Normal',
          );
          _addCourseToSemester(semesterName, allCourse);
          importedCount++;
        } else {
          SecureLogger.info('DATA', 'Course already exists, skipping', {
            'course_code': cdcCourse.code,
            'operation': 'skip_duplicate'
          });
        }
      }

      SecureLogger.dataOperation('import', 'cdc_courses', true, {
        'imported_count': importedCount,
        'operation': 'load_cdcs'
      });

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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                    ],
                  ),
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
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.analytics_rounded,
                        color: Colors.white,
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'SGPA for each semester',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
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
                                  color: Colors.white,
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
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Overall CGPA: ${_cgpaData.cgpa.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
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
    if (sgpa >= 9.0) return const Color(0xFF0D9488); // Excellent - Teal
    if (sgpa >= 8.0) return const Color(0xFF3B82F6); // Very Good - Blue
    if (sgpa >= 7.0) return const Color(0xFF059669); // Good - Green
    if (sgpa >= 6.0) return const Color(0xFFF59E0B); // Average - Amber
    if (sgpa >= 5.0) return const Color(0xFFEF4444); // Below Average - Red
    return const Color(0xFFDC2626); // Poor - Deep Red
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.secondary,
                      Theme.of(context).colorScheme.secondary.withValues(alpha: 0.8),
                    ],
                  ),
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
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.school_rounded,
                        color: Colors.white,
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Credits for each semester',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
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
                                  color: Colors.white,
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
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Total Credits: ${_cgpaData.semesters.values.fold<double>(0.0, (sum, sem) => sum + sem.totalCredits).toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
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
    if (credits >= 24) return const Color(0xFF0D9488); // High load - Teal
    if (credits >= 20) return const Color(0xFF059669); // Good load - Green
    if (credits >= 16) return const Color(0xFF3B82F6); // Normal load - Blue
    if (credits >= 12) return const Color(0xFFF59E0B); // Light load - Amber
    if (credits >= 8) return const Color(0xFFEF4444); // Very light - Red
    return const Color(0xFFDC2626); // Minimal - Deep Red
  }

  void _addCustomSemester() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                ResponsiveService.getAdaptiveBorderRadius(context, 12),
              ),
            ),
            contentPadding: ResponsiveService.getAdaptivePadding(
              context,
              const EdgeInsets.fromLTRB(24, 20, 24, 24),
            ),
            titlePadding: ResponsiveService.getAdaptivePadding(
              context,
              const EdgeInsets.fromLTRB(24, 24, 24, 0),
            ),
            actionsPadding: ResponsiveService.getAdaptivePadding(
              context,
              const EdgeInsets.fromLTRB(24, 0, 24, 24),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.add_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text('Add Custom Semester'),
              ],
            ),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Semester Name',
                labelStyle: TextStyle(
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 14),
                ),
                hintText: 'e.g., 5-2, ST 4',
                hintStyle: TextStyle(
                  fontSize: ResponsiveService.getAdaptiveFontSize(context, 13),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveService.getAdaptiveBorderRadius(context, 8),
                  ),
                ),
                contentPadding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.isNotEmpty &&
                      !_semesters.contains(controller.text)) {
                    setState(() {
                      _semesters.add(controller.text);
                      _tabController.dispose();
                      _tabController = TabController(
                        length: _semesters.length,
                        vsync: this,
                      );
                    });
                  }
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (!_authService.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('CGPA Calculator'), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
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
        appBar: AppBar(title: const Text('CGPA Calculator'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      drawer: const AppDrawerWidget(
        currentScreen: DrawerScreen.cgpaCalculator,
      ),
      appBar: AppBar(
        title: const Text('CGPA Calculator'),
        centerTitle: true,
        bottom:
            ResponsiveService.isMobile(context)
                ? TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelStyle: TextStyle(
                    fontSize: ResponsiveService.getAdaptiveFontSize(
                      context,
                      12,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: ResponsiveService.getAdaptiveFontSize(
                      context,
                      12,
                    ),
                  ),
                  tabAlignment: TabAlignment.center,
                  tabs:
                      _semesters
                          .map(
                            (sem) => Tab(
                              child: Padding(
                                padding: ResponsiveService.getAdaptivePadding(
                                  context,
                                  const EdgeInsets.symmetric(horizontal: 4),
                                ),
                                child: Text(sem),
                              ),
                            ),
                          )
                          .toList(),
                )
                : TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  tabs: _semesters.map((sem) => Tab(text: sem)).toList(),
                ),
        actions: [
          IconButton(
            icon: const Icon(Icons.school_outlined),
            tooltip: 'Load CDCs',
            onPressed: _authService.isAuthenticated ? _loadCDCs : null,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Import Courses from Timetable',
            onPressed:
                _authService.isAuthenticated
                    ? _importCoursesFromTimetable
                    : null,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Custom Semester',
            onPressed: _addCustomSemester,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Data',
            onPressed: _loadData,
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
        gradient:
            isPrimary
                ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  ],
                )
                : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
                    Theme.of(
                      context,
                    ).colorScheme.surfaceContainer.withValues(alpha: 0.4),
                  ],
                ),
        borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
        border: Border.all(
          color:
              isPrimary
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color:
                isPrimary
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
                    : Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: isPrimary ? 8 : 6,
            offset: Offset(0, isPrimary ? 2 : 1),
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
                    ? Colors.white.withValues(alpha: 0.9)
                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: isMobile ? 18 : 22,
              fontWeight: FontWeight.bold,
              color:
                  isPrimary
                      ? Colors.white
                      : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.85),
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
                  isPrimary
                      ? Colors.white.withValues(alpha: 0.85)
                      : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
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
                  'Credits',
                  semester?.totalCredits.toStringAsFixed(0) ?? '0',
                  Icons.school_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem(
                  'Courses',
                  courses.length.toString(),
                  Icons.book_rounded,
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
                              ).colorScheme.primary.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.book_rounded,
                              size:
                                  ResponsiveService.isMobile(context) ? 48 : 56,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.7),
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
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
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
                          childAspectRatio: isMobile ? 3.0 : 3.4,
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
                          child: FilledButton.icon(
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
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
                          child: FilledButton.icon(
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
                                              ).colorScheme.onSecondary,
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
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.secondary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onSecondary,
                              elevation: 0,
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
                          child: FilledButton.icon(
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
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
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
                        child: FilledButton.icon(
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
                                        ).colorScheme.onSecondary,
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
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.secondary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onSecondary,
                            elevation: 0,
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

    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            Theme.of(
              context,
            ).colorScheme.surfaceContainer.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isMobile ? 14 : 16,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          ),
          SizedBox(height: isMobile ? 3 : 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.8),
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

  Widget _buildCourseCard(String semesterName, int index, CourseEntry course) {
    final gradeOptions =
        course.courseType == 'ATC'
            ? CGPAService.atcGrades
            : CGPAService.normalGrades;
    final isMobile = ResponsiveService.isMobile(context);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.book_rounded,
                      size: isMobile ? 20 : 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.courseCode,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            fontSize: isMobile ? 14 : 15,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          course.courseTitle,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            fontSize: isMobile ? 11 : 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
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
                    icon: Icon(Icons.close_rounded, size: 18),
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                    onPressed:
                        () => _removeCourseFromSemester(semesterName, index),
                    tooltip: 'Remove course',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.1),
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.8),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.stars_rounded,
                          size: 14,
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${course.credits}',
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            fontSize: 12,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
                    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.15),
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
                        ).colorScheme.onSurface.withValues(alpha: 0.4),
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
                            ).colorScheme.onSurface.withValues(alpha: 0.45),
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
                            color: Colors.white,
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
            borderRadius: BorderRadius.circular(16),
            elevation: 12,
            dropdownColor: colorScheme.surfaceContainer,
            menuMaxHeight: 320,
            items: gradeOptions.map((grade) {
              final gradeColor = _getGradeColor(grade);
              final description = _getGradeDescription(grade);
              
              return DropdownMenuItem<String>(
                value: grade,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        gradeColor.withValues(alpha: 0.05),
                        gradeColor.withValues(alpha: 0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: gradeColor.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 32,
                        decoration: BoxDecoration(
                          color: gradeColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: gradeColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            grade,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          description,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: isMobile ? 13 : 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
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

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return const Color(0xFF0D9488); // Vibrant teal-green (excellence)
      case 'A-':
        return const Color(0xFF14B8A6); // Bright teal (very good)
      case 'B':
        return const Color(0xFF3B82F6); // Vivid blue (good)
      case 'B-':
        return const Color(0xFF60A5FA); // Sky blue (good)
      case 'C':
        return const Color(0xFFF59E0B); // Bright amber (average)
      case 'C-':
        return const Color(0xFFFBBF24); // Golden yellow (average)
      case 'D':
        return const Color(0xFFEF4444); // Vibrant red (below average)
      case 'D-':
        return const Color(0xFFF87171); // Bright red (poor)
      case 'E':
        return const Color(0xFFDC2626); // Deep red (fail)
      case 'GD':
        return const Color(0xFF06B6D4); // Cyan (deferred)
      case 'PR':
        return const Color(0xFFA855F7); // Vivid purple (progress)
      case 'NC':
        return const Color(0xFF6B7280); // Neutral grey (no credit)
      default:
        return Theme.of(context).colorScheme.onSurface;
    }
  }

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
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                ResponsiveService.getAdaptiveBorderRadius(context, 12),
              ),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text('Error'),
              ],
            ),
            content: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
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
          u: course.totalCredits.toString(),
          type: 'Normal',
        ),
      );
    }

    Navigator.pop(context, coursesToImport);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:file_picker/file_picker.dart';
import '../services/data/cgpa_service.dart';
import '../utils/page_transitions.dart';
import '../widgets/common/shimmer_loading.dart';
import '../services/core/cgpa_calculator_controller.dart';
import '../services/data/auth_service.dart';
import '../services/ui/responsive_service.dart';
import '../widgets/auto_load_cdc_dialog.dart';
import '../services/ui/toast_service.dart';
import '../widgets/error_dialog.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';
import '../services/parsers/performance_sheet_parser.dart';
import '../models/cgpa_data.dart';
import '../models/course_type.dart';
import '../models/all_course.dart';
import '../utils/page_info_helper.dart';

import 'cg_booster_screen.dart';
import 'grade_planner_screen.dart';
import '../utils/design_constants.dart';
import '../utils/grade_utils.dart' as grade_utils;
import '../widgets/command_palette.dart';
import '../widgets/app_drawer.dart';
import '../services/ui/tutorial_service.dart';
import '../services/core/timetable_service.dart';
import '../widgets/cgpa/course_selection_dialog.dart';
import '../widgets/cgpa/performance_sheet_preview_dialog.dart';

class CGPACalculatorScreen extends StatefulWidget {
  const CGPACalculatorScreen({super.key});

  @override
  State<CGPACalculatorScreen> createState() => _CGPACalculatorScreenState();
}

class _CGPACalculatorScreenState extends State<CGPACalculatorScreen>
    with TickerProviderStateMixin {
  final CGPACalculatorController _controller = CGPACalculatorController();
  final AuthService _authService = AuthService();
  final TimetableService _timetableService = TimetableService();

  late TabController _tabController;

  void _rebuildTabController({int? initialIndex}) {
    final prevIndex = _tabController.index;
    _tabController.dispose();
    final idx = (initialIndex ?? prevIndex)
        .clamp(0, (_controller.semesters.length - 1).clamp(0, 999));
    _tabController = TabController(
      length: _controller.semesters.length,
      vsync: this,
      initialIndex: idx,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);
    _controller.addListener(_onControllerChanged);
    _loadData();
    _registerPaletteActions();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _registerPaletteActions() {
    CommandPaletteActions.register(DrawerScreen.cgpaCalculator, () => [
      CommandPaletteEntry(
        label: 'Grade Planner',
        subtitle: 'Plan future semester grades',
        icon: Icons.calculate_outlined,
        category: CommandCategory.context,
        onSelect: () => Navigator.push(context,
            FadeSlidePageRoute(page: GradePlannerScreen(cgpaData: _controller.cgpaData))),
      ),
      CommandPaletteEntry(
        label: 'CG Booster',
        subtitle: 'Find courses to boost your CG',
        icon: Icons.bolt_outlined,
        category: CommandCategory.context,
        onSelect: () => Navigator.push(context,
            FadeSlidePageRoute(page: CGBoosterScreen(cgpaData: _controller.cgpaData))),
      ),
      CommandPaletteEntry(
        label: 'Load CDCs',
        subtitle: 'Auto-load compulsory courses',
        icon: Icons.school_outlined,
        category: CommandCategory.context,
        onSelect: _loadCDCs,
      ),
      CommandPaletteEntry(
        label: 'Import from Timetable',
        subtitle: 'Import courses from a timetable',
        icon: Icons.file_download_outlined,
        category: CommandCategory.context,
        onSelect: _importCoursesFromTimetable,
      ),
      CommandPaletteEntry(
        label: 'Import Performance Sheet',
        subtitle: 'Import grades from PDF',
        icon: Icons.picture_as_pdf_outlined,
        category: CommandCategory.context,
        onSelect: _importFromPerformanceSheet,
      ),
    ]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    CommandPaletteActions.unregister(DrawerScreen.cgpaCalculator);
    super.dispose();
  }

  Future<void> _loadData() async {
    await _controller.loadData();
    if (_controller.semesters.isNotEmpty) {
      _rebuildTabController();
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) TutorialService().showCGPATutorial(context);
        });
      });
    }
  }

  Future<void> _saveSemester(String semesterName) async {
    final result = await _controller.saveSemester(semesterName);
    if (!mounted) return;
    switch (result) {
      case SemesterSaveResult.saved:
        ToastService.showSuccess('Semester saved');
      case SemesterSaveResult.nothingToSave:
        ToastService.showInfo('Nothing to save');
      case SemesterSaveResult.failed:
        ToastService.showError('Failed to save semester');
    }
  }

  Future<void> _importCoursesFromTimetable() async {
    try {
      final allTimetables = await _timetableService.getAllTimetables();

      if (allTimetables.isEmpty) {
        _showErrorDialog('No timetables found. Please create a timetable first.');
        return;
      }

      if (!mounted) return;

      final selectedCourses = await showDialog<Map<String, List<AllCourse>>>(
        context: context,
        builder: (context) => CourseSelectionDialog(
          timetables: allTimetables,
          semesters: _controller.semesters,
        ),
      );

      if (selectedCourses == null || selectedCourses.isEmpty) return;

      final importedCount = _controller.importCoursesFromTimetable(selectedCourses);
      _rebuildTabController();

      if (mounted && importedCount > 0) {
        ToastService.showSuccess(
          'Imported $importedCount course${importedCount != 1 ? 's' : ''}!',
        );
      }
    } catch (e) {
      if (mounted) _showErrorDialog('Error importing courses: $e');
    }
  }

  Future<void> _importFromPerformanceSheet() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        _showErrorDialog('Could not read the selected file.');
        return;
      }

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

      final parsed = await PerformanceSheetParser.parse(file.bytes!);

      if (mounted) Navigator.of(context).pop();

      if (parsed.semesters.isEmpty) {
        _showErrorDialog(
          'Could not find any courses in the PDF.\n'
          '${parsed.warnings.isNotEmpty ? 'Warnings: ${parsed.warnings.join(", ")}' : ''}',
        );
        return;
      }

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => PerformanceSheetPreviewDialog(
          parsed: parsed,
          allCourses: _controller.allCourses,
        ),
      );

      if (confirmed != true) return;

      final importResult = await _controller.importPerformanceSheetData(parsed);
      _rebuildTabController();

      if (mounted) {
        if (importResult.saveSuccess) {
          ToastService.showSuccess(
            'Imported ${importResult.importedCount} courses from ${parsed.semesters.length} semesters!',
          );
        } else {
          ToastService.showError('Failed to save imported data');
        }
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) _showErrorDialog('Error importing from Performance Sheet: $e');
    }
  }

  Future<void> _loadCDCs() async {
    try {
      final result = await showDialog<AutoLoadCDCResult>(
        context: context,
        builder: (context) => const AutoLoadCDCDialog(),
      );

      if (result == null || !mounted) return;

      final semesterName = _controller.semesters[_tabController.index];
      final importedCount = await _controller.loadCDCs(
        branch: result.branch,
        year: result.year,
        targetSemester: semesterName,
      );

      if (mounted) {
        if (importedCount > 0) {
          ToastService.showSuccess(
            'Added $importedCount CDC course${importedCount != 1 ? 's' : ''} from ${result.year} to $semesterName!',
          );
        } else {
          ToastService.showInfo(
            'All CDC courses from ${result.year} already exist in $semesterName',
          );
        }
      }
    } catch (e) {
      if (mounted) _showErrorDialog('Error loading CDCs: $e');
    }
  }

  void _showSemesterSGPADetails() {
    if (_controller.cgpaData.semesters.isEmpty) return;

    final semestersWithData = _controller.cgpaData.semesters.entries
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
                    ).motionListItem(index);
                  },
                ),
              ),
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
                      'Overall CGPA: ${_controller.cgpaData.cgpa.toStringAsFixed(2)}',
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
    if (_controller.cgpaData.semesters.isEmpty) return;

    final semestersWithData = _controller.cgpaData.semesters.entries
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
                      'Total Credits: ${_controller.cgpaData.semesters.values.fold<double>(0.0, (sum, sem) => sum + sem.totalCredits).toStringAsFixed(0)}',
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
      await _controller.removeSemester(semesterName);
      _rebuildTabController();
    }
  }

  void _addCustomSemester() {
    final nextNormal = _controller.nextNormalSemester();
    final nextSummer = _controller.nextSummerTerm();
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
              if (_controller.addSemester(nextNormal)) {
                _rebuildTabController(initialIndex: _controller.semesters.length - 1);
              }
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
              if (_controller.addSemester(nextSummer)) {
                _rebuildTabController(initialIndex: _controller.semesters.length - 1);
              }
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

    if (_controller.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('CGPA Calculator')),
        body: const CourseListSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CGPA Calculator'),
        bottom: PreferredSize(
          key: TutorialKeys.semesterTabs,
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _controller.semesters.length + 1,
              itemBuilder: (context, index) {
                if (index == _controller.semesters.length) {
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

                final sem = _controller.semesters[index];
                final isSelected = _tabController.index == index;
                final semester = _controller.cgpaData.semesters[sem];
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
          PageInfoHelper.infoButton(context, PageInfoHelper.cgpaCalculator, key: TutorialKeys.infoCGPA),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: 'Reload Data',
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            key: TutorialKeys.cgpaActions,
            icon: const Icon(Icons.more_vert, size: 22),
            tooltip: 'More',
            onSelected: (value) {
              if (!_authService.isAuthenticated) return;
              switch (value) {
                case 'grade_planner':
                  Navigator.push(context, FadeSlidePageRoute(page: GradePlannerScreen(cgpaData: _controller.cgpaData)));
                  break;
                case 'cg_booster':
                  Navigator.push(context, FadeSlidePageRoute(page: CGBoosterScreen(cgpaData: _controller.cgpaData)));
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
              children: _controller.semesters.map((sem) => _buildSemesterView(sem)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCGPASummary() {
    final isMobile = ResponsiveService.isMobile(context);

    return Container(
      key: TutorialKeys.cgpaSummary,
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 6),
      child: isMobile
          ? Row(
              children: [
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => _showSemesterSGPADetails(),
                    child: _buildSummaryCard(
                      'CGPA',
                      _controller.cgpaData.cgpa.toStringAsFixed(2),
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
                      _controller.cgpaData.effectiveTotalCredits.toStringAsFixed(0),
                      Icons.school_rounded,
                      subtitle: '${_controller.cgpaData.uniqueCourseCount} courses',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'Semesters',
                    _controller.cgpaData.semesters.length.toString(),
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
                      _controller.cgpaData.cgpa.toStringAsFixed(2),
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
                      _controller.cgpaData.effectiveTotalCredits.toStringAsFixed(0),
                      Icons.school_rounded,
                      subtitle: '${_controller.cgpaData.uniqueCourseCount} courses',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Semesters',
                    _controller.cgpaData.semesters.length.toString(),
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
    String? subtitle,
  }) {
    final isMobile = ResponsiveService.isMobile(context);

    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: isPrimary ? 0.9 : 0.7),
            Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: isPrimary ? 0.6 : 0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
        border: Border.all(
          color: isPrimary
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
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
            color: isPrimary
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: isMobile ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: isMobile ? 9 : 10,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSemesterView(String semesterName) {
    final semester = _controller.cgpaData.semesters[semesterName];
    final courses = semester?.courses ?? [];

    return Column(
      children: [
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
                  _controller.cumulativeCgpa(semesterName).toStringAsFixed(2),
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
        Expanded(
          child: courses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.book_rounded,
                            size: ResponsiveService.isMobile(context) ? 48 : 56,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No courses added yet',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: ResponsiveService.isMobile(context) ? 18 : 20,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add courses to start calculating your SGPA',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: ResponsiveService.isMobile(context) ? 14 : 15,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
                    final crossAxisCount = isMobile ? 1 : (constraints.maxWidth > 1200 ? 3 : 2);

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
                        return _buildCourseCard(semesterName, index, courses[index]);
                      },
                    );
                  },
                ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            ResponsiveService.isMobile(context) ? 12 : 20,
            12,
            ResponsiveService.isMobile(context) ? 12 : 20,
            ResponsiveService.isMobile(context) ? 16 : 20,
          ),
          child: ResponsiveService.isMobile(context)
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
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                          onPressed: _controller.isSaving ? null : () => _saveSemester(semesterName),
                          icon: _controller.isSaving
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 16),
                          label: const Text('Save', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.primary,
                            side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          style: FilledButton.styleFrom(
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 140,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _controller.isSaving ? null : () => _saveSemester(semesterName),
                        icon: _controller.isSaving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Icon(icon, size: isMobile ? 14 : 16, color: scheme.onSurface.withValues(alpha: 0.45)),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
    final gradeOptions = course.courseType == CourseType.atc ? CGPAService.atcGrades : CGPAService.normalGrades;
    final isMobile = ResponsiveService.isMobile(context);
    final superseded = course.courseType == CourseType.normal &&
        _controller.isSuperseded(semesterName, course.courseCode);

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withValues(alpha: AppDesign.opacityDivider)),
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
                    onPressed: () => _controller.removeCourseFromSemester(semesterName, index),
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
                      (value) => _controller.updateGrade(semesterName, index, value),
                    ),
                  ),
                ],
              ),
              if (course.grade != null && course.courseType == CourseType.normal)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calculate_outlined,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${course.gradePoints.toStringAsFixed(1)} × ${course.credits} = ${course.totalGradePoints.toStringAsFixed(2)} pts',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
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
              final description = CGPACalculatorController.getGradeDescription(grade);

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

  void _showErrorDialog(String message) {
    ErrorDialog.show(context, message);
  }

  void _showAddCourseDialog(String semesterName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveService.isMobile(context) ? 320 : 500,
            maxHeight: ResponsiveService.isMobile(context) ? 400 : 500,
          ),
          child: Padding(
            padding: ResponsiveService.getAdaptivePadding(context, const EdgeInsets.all(20)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.add_outlined, color: Theme.of(context).colorScheme.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add Course',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'For $semesterName',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.search_outlined, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    );
                  },
                  suggestionsCallback: (pattern) {
                    return _controller.searchCourses(pattern);
                  },
                  itemBuilder: (context, course) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text(
                        course.courseCode,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        course.courseTitle,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: course.type == 'ATC'
                              ? Theme.of(context).colorScheme.tertiaryContainer
                              : Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          course.type,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: course.type == 'ATC'
                                ? Theme.of(context).colorScheme.onTertiaryContainer
                                : Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    );
                  },
                  onSelected: (course) {
                    final added = _controller.addCourseToSemester(semesterName, course);
                    if (!added) {
                      ToastService.showError('${course.courseCode} is already in $semesterName');
                    }
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Start typing to search for courses',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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


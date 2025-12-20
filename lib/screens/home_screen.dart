import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/timetable_service.dart';
import '../services/course_utils.dart';
import '../services/export_service.dart';
import '../services/clash_detector.dart';
import '../services/auth_service.dart';
import '../widgets/courses_tab_widget.dart';
import '../widgets/timetable_widget.dart';
import '../widgets/export_timetable_widget.dart';
import '../widgets/clash_warnings_widget.dart';
import '../widgets/search_filter_widget.dart';
import '../widgets/theme_selector_widget.dart';
import '../services/page_leave_warning_service.dart';
import '../services/toast_service.dart';
import '../services/campus_service.dart';
import '../services/course_data_service.dart';
import '../services/user_settings_service.dart';
import '../services/responsive_service.dart';
import '../services/auto_load_cdc_service.dart';
import '../models/export_options.dart';
import '../widgets/export_options_dialog.dart';
import '../widgets/campus_selector_widget.dart';
import 'generator_screen.dart';
import 'timetables_screen.dart';
import 'course_guide_screen.dart';
import 'discipline_electives_screen.dart';
import 'humanities_electives_screen.dart';
import 'professors_screen.dart';
import 'prerequisites_screen.dart';
import 'add_swap_screen.dart';
import '../models/timetable.dart' as timetable;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class HomeScreenWithTimetable extends StatefulWidget {
  final Timetable timetable;
  final Function(bool)? onUnsavedChangesChanged;

  const HomeScreenWithTimetable({
    super.key,
    required this.timetable,
    this.onUnsavedChangesChanged,
  });

  @override
  State<HomeScreenWithTimetable> createState() =>
      _HomeScreenWithTimetableState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TimetableService _timetableService = TimetableService();
  final AuthService _authService = AuthService();
  final PageLeaveWarningService _pageLeaveWarning = PageLeaveWarningService();
  final UserSettingsService _userSettingsService = UserSettingsService();
  final GlobalKey _timetableKey = GlobalKey();
  Timetable? _timetable;
  List<Course> _filteredCourses = [];
  bool _isLoading = true;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  StreamSubscription<Campus>? _campusSubscription;

  @override
  void initState() {
    super.initState();
    _loadTimetable();
    _initializeUserSettings();

    // Listen for campus changes
    _campusSubscription = CampusService.campusChangeStream.listen((_) {
      print('Campus changed, reloading timetable...');
      _loadTimetable();
    });
  }

  Future<void> _initializeUserSettings() async {
    await _userSettingsService.initializeSettings();
  }

  @override
  void dispose() {
    _campusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTimetable() async {
    try {
      final timetable = await _timetableService.loadTimetable();

      setState(() {
        _timetable = timetable;
        _filteredCourses = timetable.availableCourses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      // Show more helpful error message for missing course data
      String errorMessage = 'Error loading timetable: $e';
      if (e.toString().contains('No course data available')) {
        errorMessage =
            'Course data is not available. Please contact the administrator to upload the latest timetable data.';
      }

      _showErrorDialog(errorMessage);
    }
  }

  void _onSearchChanged(String query, Map<String, dynamic> filters) {
    if (_timetable == null) return;

    setState(() {
      var courses = _timetable!.availableCourses;

      // Apply text search
      courses = CourseUtils.searchCourses(courses, query);

      // Apply course code filter
      if (filters['courseCode'] != null &&
          filters['courseCode'].toString().isNotEmpty) {
        courses = CourseUtils.filterByCourseCode(
          courses,
          filters['courseCode'],
        );
      }

      // Apply instructor filter
      if (filters['instructor'] != null &&
          filters['instructor'].toString().isNotEmpty) {
        courses = CourseUtils.filterByInstructor(
          courses,
          filters['instructor'],
        );
      }

      // Apply credits filter
      courses = CourseUtils.filterByCredits(
        courses,
        filters['minCredits'],
        filters['maxCredits'],
      );

      // Apply days filter
      if (filters['days'] != null &&
          (filters['days'] as List<DayOfWeek>).isNotEmpty) {
        courses = CourseUtils.filterByDays(courses, filters['days']);
      }

      // Apply exam date filters
      if (filters['midSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(
          courses,
          filters['midSemDate'],
          true,
        );
      }

      if (filters['endSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(
          courses,
          filters['endSemDate'],
          false,
        );
      }

      _filteredCourses = courses;
    });
  }

  void _addSection(String courseCode, String sectionId) {
    if (_timetable == null) return;

    try {
      final success = _timetableService.addSectionWithoutSaving(
        courseCode,
        sectionId,
        _timetable!,
      );
      if (success) {
        setState(() {
          _hasUnsavedChanges = true;
        });
        _pageLeaveWarning.enableWarning(true);
      } else {
        final course = _timetable!.availableCourses.firstWhere(
          (c) => c.courseCode == courseCode,
        );
        final section = course.sections.firstWhere(
          (s) => s.sectionId == sectionId,
        );

        // Check specific reason for failure
        final existingSameType = _timetable!.selectedSections.where(
          (s) => s.courseCode == courseCode && s.section.type == section.type,
        );

        if (existingSameType.isNotEmpty) {
          _showErrorDialog(
            'You can only select one ${section.type.name} section per course.\nAlready selected: ${existingSameType.first.sectionId}',
          );
        } else {
          _showErrorDialog(
            'Cannot add section due to time conflicts or exam clashes',
          );
        }
      }
    } catch (e) {
      _showErrorDialog('Error adding section: $e');
    }
  }

  void _removeSection(String courseCode, String sectionId) {
    if (_timetable == null) return;

    try {
      _timetableService.removeSectionWithoutSaving(
        courseCode,
        sectionId,
        _timetable!,
      );
      setState(() {
        _hasUnsavedChanges = true;
      });
    } catch (e) {
      _showErrorDialog('Error removing section: $e');
    }
  }

  Future<void> _autoLoadCDCs() async {
    if (_timetable == null) return;

    try {
      final autoLoadService = AutoLoadCDCService();
      final result = await autoLoadService.showBranchYearDialog(context);

      if (result != null) {
        final selectedSections = await autoLoadService
            .loadCDCsForBranchAndSemester(
              branch: result.branch,
              semester: result.year,
              availableCourses: _timetable!.availableCourses,
            );

        if (selectedSections.isNotEmpty) {
          for (final selectedSection in selectedSections) {
            _timetableService.addSectionWithoutSaving(
              selectedSection.courseCode,
              selectedSection.sectionId,
              _timetable!,
            );
          }

          setState(() {
            _hasUnsavedChanges = true;
          });
          _pageLeaveWarning.enableWarning(true);

          ToastService.showSuccess(
            'Auto-loaded ${selectedSections.length} CDC courses',
          );
        } else {
          ToastService.showInfo(
            'No CDC courses found for the selected branch and year',
          );
        }
      }
    } catch (e) {
      _showErrorDialog('Error auto-loading CDCs: $e');
    }
  }

  Future<void> _clearTimetable() async {
    if (_timetable == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Timetable'),
            content: const Text(
              'Are you sure you want to remove all selected courses from your timetable?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Clear All'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        _timetable!.selectedSections.clear();
        _timetable!.clashWarnings.clear();
        setState(() {
          _hasUnsavedChanges = true;
        });
        _pageLeaveWarning.enableWarning(true);

        ToastService.showSuccess('Timetable cleared successfully');
      } catch (e) {
        _showErrorDialog('Error clearing timetable: $e');
      }
    }
  }

  Future<void> _saveTimetable() async {
    if (_timetable == null || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _timetableService.saveTimetable(_timetable!);
      setState(() {
        _hasUnsavedChanges = false;
        _isSaving = false;
      });
      _pageLeaveWarning.enableWarning(false);

      ToastService.showSuccess('Timetable saved successfully!');
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      _showErrorDialog('Error saving timetable: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<bool> _showIncompleteWarningDialog() async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Incomplete Course Selections'),
                content: const Text(
                  'Some courses have incomplete selections (missing lab/tutorial/lecture sections). Do you want to continue exporting anyway?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _exportToICS() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToICS(
        _timetable!.selectedSections,
        _timetable!.availableCourses,
      );

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Timetable exported to: $filePath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _exportToPNG() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    // Check for incomplete course selections
    final warnings = _timetableService.getIncompleteSelectionWarnings(
      _timetable!.selectedSections,
      _timetable!.availableCourses,
    );
    if (warnings.isNotEmpty) {
      final shouldContinue = await _showIncompleteWarningDialog();
      if (!shouldContinue) {
        return;
      }
    }

    // Show export options dialog
    final ExportOptions? exportOptions = await showDialog<ExportOptions>(
      context: context,
      builder: (context) => const ExportOptionsDialog(),
    );

    if (exportOptions == null) return; // User cancelled

    try {
      GlobalKey tableExportKey = GlobalKey();

      final overlay = Overlay.of(context);
      late OverlayEntry overlayEntry;

      overlayEntry = OverlayEntry(
        builder:
            (context) => Positioned(
              left: -10000,
              top: -10000,
              child: Material(
                child: SizedBox(
                  width: 2000, // Provide enough width for full table
                  height: 2000, // Provide enough height for full table
                  child: TimetableWidget(
                    timetableSlots: _timetableService.generateTimetableSlots(
                      _timetable!.selectedSections,
                      _timetable!.availableCourses,
                    ),
                    incompleteSelectionWarnings: _timetableService
                        .getIncompleteSelectionWarnings(
                          _timetable!.selectedSections,
                          _timetable!.availableCourses,
                        ),
                    size:
                        TimetableSize
                            .extraLarge, // Use largest size for best quality
                    isForExport: true,
                    tableKey: tableExportKey,
                    exportOptions: exportOptions,
                  ),
                ),
              ),
            ),
      );

      overlay.insert(overlayEntry);

      // Wait for the widget to render
      await Future.delayed(const Duration(milliseconds: 500));

      final filePath = await ExportService.exportToPNG(tableExportKey);

      overlayEntry.remove();

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Timetable downloaded as: $filePath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _openGenerator() async {
    final result = await Navigator.push<List<timetable.SelectedSection>>(
      context,
      MaterialPageRoute(builder: (context) => const GeneratorScreen()),
    );

    if (result != null && _timetable != null) {
      try {
        // Clear current selections
        _timetable!.selectedSections.clear();

        // Add new selections from generator
        for (final section in result) {
          await _timetableService.addSection(
            section.courseCode,
            section.sectionId,
            _timetable!,
          );
        }

        setState(() {});

        ToastService.showSuccess('Generated timetable applied successfully!');
      } catch (e) {
        _showErrorDialog('Error applying generated timetable: $e');
      }
    }
  }

  void _openAddSwap() {
    if (_timetable == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddSwapScreen(
              currentSelectedSections: _timetable!.selectedSections,
              availableCourses: _timetable!.availableCourses,
              currentCampus: CampusService.currentCampusCode,
            ),
      ),
    );
  }

  Future<void> _openGitHub() async {
    // Replace with your GitHub repository URL
    const String githubUrl = 'https://github.com/RCR0101/timetable_maker';

    try {
      // For web, open in new tab
      if (kIsWeb) {
        html.window.open(githubUrl, '_blank');
      } else {
        // For mobile, you'd need url_launcher package
        print('Open GitHub: $githubUrl');
      }
    } catch (e) {
      print('Error opening GitHub: $e');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sign Out'),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sign Out'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await _authService.signOut();
        // Force navigation back to root since we're deep in navigation stack
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        _showErrorDialog('Error signing out: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _userSettingsService,
      builder: (context, child) {
        if (_isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_timetable == null) {
          return Scaffold(
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'images/full_logo_bg.png',
                        height: 50,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
              centerTitle: true,
            ),
            body: const Center(child: Text('Failed to load timetable')),
          );
        }

        final isWideScreen = ResponsiveService.isDesktop(context);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'images/full_logo_bg.png',
                  height: 32,
                  fit: BoxFit.contain,
                ),
              ],
            ),
            centerTitle: true,
            actions: [
              CampusSelectorWidget(
                onCampusChanged: (campus) {
                  // Clear course cache and reload timetable when campus changes
                  CourseDataService().clearCache();
                  _loadTimetable();
                  ToastService.showInfo(
                    'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
                  );
                },
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.apps),
                tooltip: 'More Options',
                onSelected: (value) {
                  switch (value) {
                    case 'course_guide':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CourseGuideScreen(),
                        ),
                      );
                      break;
                    case 'prerequisites':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PrerequisitesScreen(),
                        ),
                      );
                      break;
                    case 'professors':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfessorsScreen(),
                        ),
                      );
                      break;
                    case 'discipline_electives':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => const DisciplineElectivesScreen(),
                        ),
                      );
                      break;
                    case 'humanities_electives':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => const HumanitiesElectivesScreen(),
                        ),
                      );
                      break;
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: 'course_guide',
                        child: ListTile(
                          leading: Icon(Icons.menu_book),
                          title: Text('Course Guide'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'prerequisites',
                        child: ListTile(
                          leading: Icon(Icons.account_tree),
                          title: Text('Prerequisites'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'professors',
                        child: ListTile(
                          leading: Icon(Icons.person),
                          title: Text('Professors'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'discipline_electives',
                        child: ListTile(
                          leading: Icon(Icons.school),
                          title: Text('Discipline Electives'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'humanities_electives',
                        child: ListTile(
                          leading: Icon(Icons.library_books),
                          title: Text('Humanities Electives'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
              ),
              const ThemeToggleButton(),
              if (isWideScreen) ...[
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _exportToICS,
                  tooltip: 'Export to ICS',
                ),
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: _exportToPNG,
                  tooltip: 'Export to PNG',
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload),
                  onPressed: _exportToTTWithFilePicker,
                  tooltip: 'Export Timetable (.tt)',
                ),
                IconButton(
                  icon: const Icon(Icons.file_download),
                  onPressed: _importFromTT,
                  tooltip: 'Import Timetable (.tt)',
                ),
              ] else
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'export_ics') {
                      _exportToICS();
                    } else if (value == 'export_png') {
                      _exportToPNG();
                    } else if (value == 'export_tt') {
                      _exportToTTWithFilePicker();
                    } else if (value == 'import_tt') {
                      _importFromTT();
                    }
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'import_tt',
                          child: ListTile(
                            leading: Icon(Icons.file_upload),
                            title: Text('Import Timetable (.tt)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export_tt',
                          child: ListTile(
                            leading: Icon(Icons.file_download),
                            title: Text('Export Timetable (.tt)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export_ics',
                          child: ListTile(
                            leading: Icon(Icons.calendar_today),
                            title: Text('Export to Calendar (.ics)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export_png',
                          child: ListTile(
                            leading: Icon(Icons.image),
                            title: Text('Export as Image (.png)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                  icon: const Icon(Icons.more_vert),
                ),
              IconButton(
                icon: const Icon(Icons.star_border),
                onPressed: () => _openGitHub(),
                tooltip: 'Star on GitHub',
              ),
              // User info and logout
              if (_authService.isAuthenticated)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'logout') {
                      _logout();
                    }
                  },
                  itemBuilder:
                      (context) => [
                        PopupMenuItem(
                          enabled: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _authService.userName ?? 'User',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _authService.userEmail ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                ),
                              ),
                              const Divider(),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: ListTile(
                            leading: Icon(Icons.logout),
                            title: Text('Sign Out'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage:
                              _authService.userPhotoUrl != null
                                  ? NetworkImage(_authService.userPhotoUrl!)
                                  : null,
                          child:
                              _authService.userPhotoUrl == null
                                  ? const Icon(Icons.person, size: 16)
                                  : null,
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Guest',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body:
              isWideScreen
                  ? Row(
                    children: [
                      Expanded(flex: 1, child: _buildCoursesPanel()),
                      Expanded(flex: 2, child: _buildTimetablePanel()),
                    ],
                  )
                  : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: TabBar(
                            labelColor: Theme.of(context).colorScheme.primary,
                            unselectedLabelColor: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                            indicatorColor:
                                Theme.of(context).colorScheme.primary,
                            tabs: const [
                              Tab(icon: Icon(Icons.search), text: 'Courses'),
                              Tab(
                                icon: Icon(Icons.calendar_view_week),
                                text: 'Timetable',
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildCoursesPanel(),
                              _buildTimetablePanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          floatingActionButton:
              isWideScreen
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.extended(
                        onPressed: _openAddSwap,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Add/Swap'),
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondary,
                        heroTag: 'add_swap',
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.extended(
                        onPressed: _openGenerator,
                        icon: const Icon(Icons.auto_awesome_mosaic),
                        label: const Text('TT Generator'),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        heroTag: 'generator',
                      ),
                    ],
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        onPressed: _openAddSwap,
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondary,
                        tooltip: 'Add/Swap Courses',
                        heroTag: 'add_swap',
                        child: const Icon(Icons.swap_horiz),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton(
                        onPressed: _openGenerator,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        tooltip: 'TT Generator',
                        heroTag: 'generator',
                        child: const Icon(Icons.auto_awesome_mosaic),
                      ),
                    ],
                  ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Disclaimer: This software may make mistakes or suggest classes you might not be eligible for. Please double-check all course selections with your academic advisor.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: ResponsiveService.isMobile(context) ? 9 : 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoursesPanel() {
    return Column(
      children: [
        SearchFilterWidget(onSearchChanged: _onSearchChanged),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: CoursesTabWidget(
              courses: _filteredCourses,
              selectedSections: _timetable!.selectedSections,
              onSectionToggle: (courseCode, sectionId, isSelected) {
                if (isSelected) {
                  _removeSection(courseCode, sectionId);
                } else {
                  _addSection(courseCode, sectionId);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimetablePanel() {
    final isMobile =
        ResponsiveService.isMobile(context) ||
        ResponsiveService.isTablet(context);

    return Column(
      children: [
        if (_timetable!.clashWarnings.isNotEmpty)
          Card(
            margin: EdgeInsets.all(isMobile ? 4 : 8),
            child: ClashWarningsWidget(warnings: _timetable!.clashWarnings),
          ),
        Expanded(
          child: Card(
            margin: EdgeInsets.all(isMobile ? 4 : 8),
            child: Container(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  constraints: BoxConstraints(
                    minWidth:
                        isMobile
                            ? MediaQuery.of(context).size.width - 32
                            : ResponsiveService.getValue(
                              context,
                              mobile: 480,
                              tablet: 768,
                              desktop: 1000,
                            ),
                  ),
                  child: RepaintBoundary(
                    key: _timetableKey,
                    child: TimetableWidget(
                      timetableSlots: _timetableService.generateTimetableSlots(
                        _timetable!.selectedSections,
                        _timetable!.availableCourses,
                      ),
                      incompleteSelectionWarnings: _timetableService
                          .getIncompleteSelectionWarnings(
                            _timetable!.selectedSections,
                            _timetable!.availableCourses,
                          ),
                      onClear: _clearTimetable,
                      onRemoveSection: _removeSection,
                      size: _userSettingsService.getTimetableSize(
                        _timetable!.id,
                      ),
                      hasUnsavedChanges: _hasUnsavedChanges,
                      isSaving: _isSaving,
                      onSave: _authService.isGuest ? null : _saveTimetable,
                      onAutoLoadCDCs: _autoLoadCDCs,
                      onSizeChanged: (newSize) {
                        _userSettingsService.updateTimetableSettings(
                          _timetable!.id,
                          newSize,
                          null,
                        );
                      },
                      layout: _userSettingsService.getTimetableLayout(
                        _timetable!.id,
                      ),
                      onLayoutChanged: (newLayout) {
                        _userSettingsService.updateTimetableSettings(
                          _timetable!.id,
                          null,
                          newLayout,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _importFromTT() async {
    try {
      final importedTimetable =
          await ExportService.importFromTTWithFilePicker();
      if (importedTimetable == null) {
        return; // User cancelled
      }

      // Show confirmation dialog
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Import Timetable'),
              content: Text(
                'Are you sure you want to import "${importedTimetable.name}"?\n\n'
                'This will replace your current timetable with the imported one.\n\n'
                'Campus: ${importedTimetable.campus.toString().split('.').last}\n'
                'Courses: ${importedTimetable.selectedSections.length} sections',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Import'),
                ),
              ],
            ),
      );

      if (shouldReplace == true) {
        // Switch campus to match the imported timetable
        if (CampusService.currentCampus != importedTimetable.campus) {
          await CampusService.setCampus(importedTimetable.campus);
        }
        final reloadedTimetable = await _timetableService.loadTimetable();
        final clashWarnings = ClashDetector.detectClashes(
          importedTimetable.selectedSections,
          reloadedTimetable.availableCourses,
        );

        final updatedImportedTimetable = Timetable(
          id: importedTimetable.id,
          name: importedTimetable.name,
          createdAt: importedTimetable.createdAt,
          updatedAt: importedTimetable.updatedAt,
          campus: importedTimetable.campus,
          availableCourses: reloadedTimetable.availableCourses, // Use full course list
          selectedSections: importedTimetable.selectedSections,
          clashWarnings: clashWarnings,
        );

        // Save the imported timetable immediately
        await _timetableService.saveTimetable(updatedImportedTimetable);

        setState(() {
          _timetable = updatedImportedTimetable;
          _filteredCourses = updatedImportedTimetable.availableCourses;
          _hasUnsavedChanges = false;
        });

        // Update page leave warning
        _pageLeaveWarning.enableWarning(false);

        if (!mounted) return;
        ToastService.showSuccess(
          'Timetable "${importedTimetable.name}" imported successfully!',
        );
      }
    } catch (e) {
      _showErrorDialog('Import failed: $e');
    }
  }

  Future<void> _exportToTTWithFilePicker() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToTTWithFilePicker(
        _timetable!,
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Timetable exported to: $filePath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }
}

class _HomeScreenWithTimetableState extends State<HomeScreenWithTimetable> {
  final TimetableService _timetableService = TimetableService();
  final AuthService _authService = AuthService();
  final PageLeaveWarningService _pageLeaveWarning = PageLeaveWarningService();
  final UserSettingsService _userSettingsService = UserSettingsService();
  final GlobalKey _timetableKey = GlobalKey();
  late Timetable _timetable;
  List<Course> _filteredCourses = [];
  final bool _isLoading = false;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _timetable = widget.timetable;
    _filteredCourses = _timetable.availableCourses;
    _initializeUserSettings();
  }

  Future<void> _initializeUserSettings() async {
    await _userSettingsService.initializeSettings();
  }

  void _onSearchChanged(String query, Map<String, dynamic> filters) {
    setState(() {
      var courses = _timetable.availableCourses;

      // Apply text search
      courses = CourseUtils.searchCourses(courses, query);

      // Apply course code filter
      if (filters['courseCode'] != null &&
          filters['courseCode'].toString().isNotEmpty) {
        courses = CourseUtils.filterByCourseCode(
          courses,
          filters['courseCode'],
        );
      }

      // Apply instructor filter
      if (filters['instructor'] != null &&
          filters['instructor'].toString().isNotEmpty) {
        courses = CourseUtils.filterByInstructor(
          courses,
          filters['instructor'],
        );
      }

      // Apply credits filter
      courses = CourseUtils.filterByCredits(
        courses,
        filters['minCredits'],
        filters['maxCredits'],
      );

      // Apply days filter
      if (filters['days'] != null &&
          (filters['days'] as List<DayOfWeek>).isNotEmpty) {
        courses = CourseUtils.filterByDays(courses, filters['days']);
      }

      // Apply exam date filters
      if (filters['midSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(
          courses,
          filters['midSemDate'],
          true,
        );
      }

      if (filters['endSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(
          courses,
          filters['endSemDate'],
          false,
        );
      }

      _filteredCourses = courses;
    });
  }

  void _addSection(String courseCode, String sectionId) {
    try {
      final success = _timetableService.addSectionWithoutSaving(
        courseCode,
        sectionId,
        _timetable,
      );
      if (success) {
        setState(() {
          _hasUnsavedChanges = true;
        });
        widget.onUnsavedChangesChanged?.call(true);
        _pageLeaveWarning.enableWarning(true);
      } else {
        final course = _timetable.availableCourses.firstWhere(
          (c) => c.courseCode == courseCode,
        );
        final section = course.sections.firstWhere(
          (s) => s.sectionId == sectionId,
        );

        // Check specific reason for failure
        final existingSameType = _timetable.selectedSections.where(
          (s) => s.courseCode == courseCode && s.section.type == section.type,
        );

        if (existingSameType.isNotEmpty) {
          _showErrorDialog(
            'You can only select one ${section.type.name} section per course.\nAlready selected: ${existingSameType.first.sectionId}',
          );
        } else {
          _showErrorDialog(
            'Cannot add section due to time conflicts or exam clashes',
          );
        }
      }
    } catch (e) {
      _showErrorDialog('Error adding section: $e');
    }
  }

  void _removeSection(String courseCode, String sectionId) {
    try {
      _timetableService.removeSectionWithoutSaving(
        courseCode,
        sectionId,
        _timetable,
      );
      setState(() {
        _hasUnsavedChanges = true;
      });
      widget.onUnsavedChangesChanged?.call(true);
    } catch (e) {
      _showErrorDialog('Error removing section: $e');
    }
  }

  Future<void> _autoLoadCDCs() async {
    try {
      final autoLoadService = AutoLoadCDCService();
      final result = await autoLoadService.showBranchYearDialog(context);

      if (result != null) {
        final selectedSections = await autoLoadService
            .loadCDCsForBranchAndSemester(
              branch: result.branch,
              semester: result.year,
              availableCourses: _timetable.availableCourses,
            );

        if (selectedSections.isNotEmpty) {
          for (final selectedSection in selectedSections) {
            _timetableService.addSectionWithoutSaving(
              selectedSection.courseCode,
              selectedSection.sectionId,
              _timetable,
            );
          }

          setState(() {
            _hasUnsavedChanges = true;
          });
          widget.onUnsavedChangesChanged?.call(true);
          _pageLeaveWarning.enableWarning(true);

          ToastService.showSuccess(
            'Auto-loaded ${selectedSections.length} CDC courses',
          );
        } else {
          ToastService.showInfo(
            'No CDC courses found for the selected branch and year',
          );
        }
      }
    } catch (e) {
      _showErrorDialog('Error auto-loading CDCs: $e');
    }
  }

  Future<void> _clearTimetable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Timetable'),
            content: const Text(
              'Are you sure you want to remove all selected courses from your timetable?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Clear All'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        _timetable.selectedSections.clear();
        _timetable.clashWarnings.clear();
        setState(() {
          _hasUnsavedChanges = true;
        });
        widget.onUnsavedChangesChanged?.call(true);
        _pageLeaveWarning.enableWarning(true);

        ToastService.showSuccess('Timetable cleared successfully');
      } catch (e) {
        _showErrorDialog('Error clearing timetable: $e');
      }
    }
  }

  Future<void> _saveTimetable() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _timetableService.saveTimetable(_timetable);
      setState(() {
        _hasUnsavedChanges = false;
        _isSaving = false;
      });
      widget.onUnsavedChangesChanged?.call(false);
      _pageLeaveWarning.enableWarning(false);

      ToastService.showSuccess('Timetable saved successfully!');
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      _showErrorDialog('Error saving timetable: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<bool> _showIncompleteWarningDialog() async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Incomplete Course Selections'),
                content: const Text(
                  'Some courses have incomplete selections (missing lab/tutorial/lecture sections). Do you want to continue exporting anyway?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _exportToICS() async {
    if (_timetable.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToICS(
        _timetable.selectedSections,
        _timetable.availableCourses,
      );

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Timetable exported to: $filePath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _exportToPNG() async {
    if (_timetable.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    // Check for incomplete course selections
    final warnings = _timetableService.getIncompleteSelectionWarnings(
      _timetable.selectedSections,
      _timetable.availableCourses,
    );
    if (warnings.isNotEmpty) {
      final shouldContinue = await _showIncompleteWarningDialog();
      if (!shouldContinue) {
        return;
      }
    }

    // Show export options dialog
    final ExportOptions? exportOptions = await showDialog<ExportOptions>(
      context: context,
      builder: (context) => const ExportOptionsDialog(),
    );

    if (exportOptions == null) return; // User cancelled

    try {
      GlobalKey tableExportKey = GlobalKey();

      final overlay = Overlay.of(context);
      late OverlayEntry overlayEntry;

      overlayEntry = OverlayEntry(
        builder:
            (context) => Positioned(
              left: -10000,
              top: -10000,
              child: Material(
                child: SizedBox(
                  width: 2000, // Provide enough width for full table
                  height: 2000, // Provide enough height for full table
                  child: TimetableWidget(
                    timetableSlots: _timetableService.generateTimetableSlots(
                      _timetable.selectedSections,
                      _timetable.availableCourses,
                    ),
                    incompleteSelectionWarnings: _timetableService
                        .getIncompleteSelectionWarnings(
                          _timetable.selectedSections,
                          _timetable.availableCourses,
                        ),
                    size:
                        TimetableSize
                            .extraLarge, // Use largest size for best quality
                    isForExport: true,
                    tableKey: tableExportKey,
                    exportOptions: exportOptions,
                  ),
                ),
              ),
            ),
      );

      overlay.insert(overlayEntry);

      // Wait for the widget to render
      await Future.delayed(const Duration(milliseconds: 500));

      final filePath = await ExportService.exportToPNG(tableExportKey);

      overlayEntry.remove();

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Timetable downloaded as: $filePath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _openGenerator() async {
    final result = await Navigator.push<List<timetable.SelectedSection>>(
      context,
      MaterialPageRoute(builder: (context) => const GeneratorScreen()),
    );

    if (result != null) {
      try {
        // Clear current selections
        _timetable.selectedSections.clear();

        // Add new selections from generator
        for (final section in result) {
          await _timetableService.addSection(
            section.courseCode,
            section.sectionId,
            _timetable,
          );
        }

        setState(() {});
        await _timetableService.saveTimetable(_timetable);

        ToastService.showSuccess('Generated timetable applied successfully!');
      } catch (e) {
        _showErrorDialog('Error applying generated timetable: $e');
      }
    }
  }

  void _openAddSwap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddSwapScreen(
              currentSelectedSections: _timetable.selectedSections,
              availableCourses: _timetable.availableCourses,
              currentCampus: CampusService.currentCampusCode,
            ),
      ),
    );
  }

  Future<void> _openGitHub() async {
    // Replace with your GitHub repository URL
    const String githubUrl = 'https://github.com/RCR0101/timetable_maker';

    try {
      // For web, open in new tab
      if (kIsWeb) {
        html.window.open(githubUrl, '_blank');
      } else {
        // For mobile, you'd need url_launcher package
        print('Open GitHub: $githubUrl');
      }
    } catch (e) {
      print('Error opening GitHub: $e');
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sign Out'),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sign Out'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await _authService.signOut();
        // Force navigation back to root since we're deep in navigation stack
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        _showErrorDialog('Error signing out: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _userSettingsService,
      builder: (context, child) {
        if (_isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isWideScreen = ResponsiveService.isDesktop(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(_timetable.name),
            centerTitle: true,
            leading:
                ResponsiveService.isMobile(context)
                    ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                    )
                    : null,
            actions: [
              CampusSelectorWidget(
                onCampusChanged: (campus) async {
                  // Clear course cache when campus changes
                  CourseDataService().clearCache();
                  // Reload courses and clear timetable for the new campus
                  try {
                    final courseDataService = CourseDataService();
                    final newCourses = await courseDataService.fetchCourses();
                    setState(() {
                      // Create a new timetable with updated courses and cleared selections
                      _timetable = Timetable(
                        id: _timetable.id,
                        name: _timetable.name,
                        createdAt: _timetable.createdAt,
                        updatedAt: DateTime.now(),
                        campus: campus,
                        availableCourses: newCourses,
                        selectedSections: [], // Clear selected sections
                        clashWarnings: [], // Clear clash warnings
                      );
                      _filteredCourses = newCourses;
                      _hasUnsavedChanges =
                          true; // Mark as unsaved since we cleared selections
                    });
                    widget.onUnsavedChangesChanged?.call(true);
                    _pageLeaveWarning.enableWarning(true);
                    ToastService.showInfo(
                      'Switched to ${CampusService.getCampusDisplayName(campus)} campus. Timetable cleared.',
                    );
                  } catch (e) {
                    ToastService.showError('Error switching campus: $e');
                  }
                },
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.apps),
                tooltip: 'More Options',
                onSelected: (value) {
                  switch (value) {
                    case 'course_guide':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CourseGuideScreen(),
                        ),
                      );
                      break;
                    case 'prerequisites':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PrerequisitesScreen(),
                        ),
                      );
                      break;
                    case 'professors':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfessorsScreen(),
                        ),
                      );
                      break;
                    case 'discipline_electives':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => const DisciplineElectivesScreen(),
                        ),
                      );
                      break;
                    case 'humanities_electives':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => const HumanitiesElectivesScreen(),
                        ),
                      );
                      break;
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: 'course_guide',
                        child: ListTile(
                          leading: Icon(Icons.menu_book),
                          title: Text('Course Guide'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'prerequisites',
                        child: ListTile(
                          leading: Icon(Icons.account_tree),
                          title: Text('Prerequisites'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'professors',
                        child: ListTile(
                          leading: Icon(Icons.person),
                          title: Text('Professors'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'discipline_electives',
                        child: ListTile(
                          leading: Icon(Icons.school),
                          title: Text('Discipline Electives'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'humanities_electives',
                        child: ListTile(
                          leading: Icon(Icons.library_books),
                          title: Text('Humanities Electives'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
              ),
              const ThemeToggleButton(),
              if (isWideScreen) ...[
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _exportToICS,
                  tooltip: 'Export to ICS',
                ),
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: _exportToPNG,
                  tooltip: 'Export to PNG',
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload),
                  onPressed: _exportToTTWithFilePicker,
                  tooltip: 'Export Timetable (.tt)',
                ),
                IconButton(
                  icon: const Icon(Icons.file_download),
                  onPressed: _importFromTT,
                  tooltip: 'Import Timetable (.tt)',
                ),
              ] else
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'export_ics') {
                      _exportToICS();
                    } else if (value == 'export_png') {
                      _exportToPNG();
                    } else if (value == 'export_tt') {
                      _exportToTTWithFilePicker();
                    } else if (value == 'import_tt') {
                      _importFromTT();
                    }
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'import_tt',
                          child: ListTile(
                            leading: Icon(Icons.file_upload),
                            title: Text('Import Timetable (.tt)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export_tt',
                          child: ListTile(
                            leading: Icon(Icons.file_download),
                            title: Text('Export Timetable (.tt)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export_ics',
                          child: ListTile(
                            leading: Icon(Icons.calendar_today),
                            title: Text('Export to Calendar (.ics)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export_png',
                          child: ListTile(
                            leading: Icon(Icons.image),
                            title: Text('Export as Image (.png)'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                  icon: const Icon(Icons.more_vert),
                ),
              IconButton(
                icon: const Icon(Icons.star_border),
                onPressed: () => _openGitHub(),
                tooltip: 'Star on GitHub',
              ),
              // User info and logout
              if (_authService.isAuthenticated)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'logout') {
                      _logout();
                    }
                  },
                  itemBuilder:
                      (context) => [
                        PopupMenuItem(
                          enabled: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _authService.userName ?? 'User',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _authService.userEmail ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                ),
                              ),
                              const Divider(),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: ListTile(
                            leading: Icon(Icons.logout),
                            title: Text('Sign Out'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage:
                              _authService.userPhotoUrl != null
                                  ? NetworkImage(_authService.userPhotoUrl!)
                                  : null,
                          child:
                              _authService.userPhotoUrl == null
                                  ? const Icon(Icons.person, size: 16)
                                  : null,
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Guest',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body:
              isWideScreen
                  ? Row(
                    children: [
                      Expanded(flex: 1, child: _buildCoursesPanel()),
                      Expanded(flex: 2, child: _buildTimetablePanel()),
                    ],
                  )
                  : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: TabBar(
                            labelColor: Theme.of(context).colorScheme.primary,
                            unselectedLabelColor: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                            indicatorColor:
                                Theme.of(context).colorScheme.primary,
                            tabs: const [
                              Tab(icon: Icon(Icons.search), text: 'Courses'),
                              Tab(
                                icon: Icon(Icons.calendar_view_week),
                                text: 'Timetable',
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildCoursesPanel(),
                              _buildTimetablePanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          floatingActionButton:
              isWideScreen
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.extended(
                        onPressed: _openAddSwap,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Add/Swap'),
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondary,
                        heroTag: 'add_swap',
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.extended(
                        onPressed: _openGenerator,
                        icon: const Icon(Icons.auto_awesome_mosaic),
                        label: const Text('TT Generator'),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        heroTag: 'generator',
                      ),
                    ],
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        onPressed: _openAddSwap,
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondary,
                        tooltip: 'Add/Swap Courses',
                        heroTag: 'add_swap',
                        child: const Icon(Icons.swap_horiz),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton(
                        onPressed: _openGenerator,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        tooltip: 'TT Generator',
                        heroTag: 'generator',
                        child: const Icon(Icons.auto_awesome_mosaic),
                      ),
                    ],
                  ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Disclaimer: This software may make mistakes or suggest classes you might not be eligible for. Please double-check all course selections with your academic advisor.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: ResponsiveService.isMobile(context) ? 9 : 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoursesPanel() {
    return Column(
      children: [
        SearchFilterWidget(onSearchChanged: _onSearchChanged),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: CoursesTabWidget(
              courses: _filteredCourses,
              selectedSections: _timetable.selectedSections,
              onSectionToggle: (courseCode, sectionId, isSelected) {
                if (isSelected) {
                  _removeSection(courseCode, sectionId);
                } else {
                  _addSection(courseCode, sectionId);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimetablePanel() {
    return Column(
      children: [
        if (_timetable.clashWarnings.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(8),
            child: ClashWarningsWidget(warnings: _timetable.clashWarnings),
          ),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: RepaintBoundary(
                key: _timetableKey,
                child: TimetableWidget(
                  timetableSlots: _timetableService.generateTimetableSlots(
                    _timetable.selectedSections,
                    _timetable.availableCourses,
                  ),
                  incompleteSelectionWarnings: _timetableService
                      .getIncompleteSelectionWarnings(
                        _timetable.selectedSections,
                        _timetable.availableCourses,
                      ),
                  onClear: _clearTimetable,
                  onRemoveSection: _removeSection,
                  size: _userSettingsService.getTimetableSize(_timetable.id),
                  hasUnsavedChanges: _hasUnsavedChanges,
                  isSaving: _isSaving,
                  onSave: _authService.isGuest ? null : _saveTimetable,
                  onAutoLoadCDCs: _autoLoadCDCs,
                  onSizeChanged: (newSize) {
                    _userSettingsService.updateTimetableSettings(
                      _timetable.id,
                      newSize,
                      null,
                    );
                  },
                  layout: _userSettingsService.getTimetableLayout(
                    _timetable.id,
                  ),
                  onLayoutChanged: (newLayout) {
                    _userSettingsService.updateTimetableSettings(
                      _timetable.id,
                      null,
                      newLayout,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _importFromTT() async {
    try {
      final importedTimetable =
          await ExportService.importFromTTWithFilePicker();
      if (importedTimetable == null) {
        return; // User cancelled
      }

      // Show confirmation dialog
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Import Timetable'),
              content: Text(
                'Are you sure you want to import "${importedTimetable.name}"?\n\n'
                'This will replace your current timetable with the imported one.\n\n'
                'Campus: ${importedTimetable.campus.toString().split('.').last}\n'
                'Courses: ${importedTimetable.selectedSections.length} sections',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Import'),
                ),
              ],
            ),
      );

      if (shouldReplace == true) {
        // Switch campus to match the imported timetable
        if (CampusService.currentCampus != importedTimetable.campus) {
          await CampusService.setCampus(importedTimetable.campus);
        }

        // Load the full course list for the new campus by reloading the timetable
        // This ensures we have all available courses, not just the ones in the import file
        final reloadedTimetable = await _timetableService.loadTimetable();
        
        // Create updated timetable with the reloaded course list and imported selections
        final clashWarnings = ClashDetector.detectClashes(
          importedTimetable.selectedSections,
          reloadedTimetable.availableCourses,
        );

        final updatedImportedTimetable = Timetable(
          id: importedTimetable.id,
          name: importedTimetable.name,
          createdAt: importedTimetable.createdAt,
          updatedAt: importedTimetable.updatedAt,
          campus: importedTimetable.campus,
          availableCourses: reloadedTimetable.availableCourses, // Use full course list
          selectedSections: importedTimetable.selectedSections,
          clashWarnings: clashWarnings,
        );

        // Save the imported timetable immediately
        await _timetableService.saveTimetable(updatedImportedTimetable);

        setState(() {
          _timetable = updatedImportedTimetable;
          _filteredCourses = updatedImportedTimetable.availableCourses;
          _hasUnsavedChanges = false;
        });

        // Update page leave warning and callback
        _pageLeaveWarning.enableWarning(false);
        widget.onUnsavedChangesChanged?.call(false);

        ToastService.showSuccess(
          'Timetable "${importedTimetable.name}" imported successfully!',
        );
      }
    } catch (e) {
      _showErrorDialog('Import failed: $e');
    }
  }

  Future<void> _exportToTTWithFilePicker() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToTTWithFilePicker(
        _timetable!,
      );
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Timetable exported to: $filePath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _exportToTT() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToTT(_timetable!);
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Timetable exported to: $filePath'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }
}

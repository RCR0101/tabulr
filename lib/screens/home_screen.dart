import 'dart:async';
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/timetable_service.dart';
import '../services/export_service.dart';
import '../services/clash_detector.dart';
import '../services/auth_service.dart';
import '../widgets/courses_tab_widget.dart';
import '../widgets/timetable_widget.dart';
import '../widgets/clash_warnings_widget.dart';
import '../widgets/search_filter_widget.dart';
import '../widgets/theme_selector_widget.dart';
import '../services/page_leave_warning_service.dart';
import '../services/toast_service.dart';
import '../services/campus_service.dart';
import '../services/course_data_service.dart';
import '../services/user_settings_service.dart';
import '../services/responsive_service.dart';
import '../utils/design_constants.dart';
import '../widgets/campus_selector_widget.dart';

import 'course_guide_screen.dart';
import 'discipline_electives_screen.dart';
import 'humanities_electives_screen.dart';
import 'prerequisites_screen.dart';
import '../mixins/timetable_editor_mixin.dart';
import '../utils/page_transitions.dart';

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

class _HomeScreenState extends State<HomeScreen> with TimetableEditorMixin<HomeScreen> {
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
  bool _showSavedIndicator = false;
  Timer? _savedIndicatorTimer;
  StreamSubscription<Campus>? _campusSubscription;

  @override Timetable? get currentTimetable => _timetable;
  @override bool get isSaving => _isSaving;
  @override set isSaving(bool v) => _isSaving = v;
  @override bool get hasUnsavedChanges => _hasUnsavedChanges;
  @override set hasUnsavedChanges(bool v) => _hasUnsavedChanges = v;
  @override GlobalKey get timetableKey => _timetableKey;
  @override TimetableService get timetableService => _timetableService;
  @override AuthService get authService => _authService;
  @override PageLeaveWarningService get pageLeaveWarning => _pageLeaveWarning;
  @override void onUnsavedChangesChanged(bool value) {}
  @override List<Course> get filteredCourses => _filteredCourses;
  @override set filteredCourses(List<Course> v) => _filteredCourses = v;
  @override void setCurrentTimetable(Timetable tt) => _timetable = tt;

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
    _savedIndicatorTimer?.cancel();
    _campusSubscription?.cancel();
    super.dispose();
  }

  @override
  void triggerSavedIndicator() {
    _savedIndicatorTimer?.cancel();
    setState(() => _showSavedIndicator = true);
    _savedIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSavedIndicator = false);
    });
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

      showErrorDialog(errorMessage);
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
            ),
            body: const Center(child: Text('Failed to load timetable')),
          );
        }

        final isWideScreen = ResponsiveService.isDesktop(context);

        return wrapWithKeyboardShortcuts(Scaffold(
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
            actions: [
              if (_showSavedIndicator)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: AppDesign.success(context), size: 18),
                      const SizedBox(width: 4),
                      Text('Saved', style: TextStyle(color: AppDesign.success(context), fontSize: 13)),
                    ],
                  ),
                ),
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
                        FadeSlidePageRoute(page: const CourseGuideScreen()),
                      );
                      break;
                    case 'prerequisites':
                      Navigator.push(
                        context,
                        FadeSlidePageRoute(page: const PrerequisitesScreen()),
                      );
                      break;
                    case 'discipline_electives':
                      Navigator.push(
                        context,
                        FadeSlidePageRoute(page: const DisciplineElectivesScreen()),
                      );
                      break;
                    case 'humanities_electives':
                      Navigator.push(
                        context,
                        FadeSlidePageRoute(page: const HumanitiesElectivesScreen()),
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
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: shareTimetable,
                tooltip: 'Share Timetable',
              ),
              const ThemeToggleButton(),
              if (isWideScreen) ...[
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: exportToICS,
                  tooltip: 'Export to ICS',
                ),
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: exportToPNG,
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
                      exportToICS();
                    } else if (value == 'export_png') {
                      exportToPNG();
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
                onPressed: () => openGitHub(),
                tooltip: 'Star on GitHub',
              ),
              // User info and logout
              if (_authService.isAuthenticated)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'logout') {
                      logout();
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
                                  ? _authService.userPhotoImage
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
                        onPressed: openAddSwap,
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
                        onPressed: openGenerator,
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
                        onPressed: openAddSwap,
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
                        onPressed: openGenerator,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        tooltip: 'TT Generator',
                        heroTag: 'generator',
                        child: const Icon(Icons.auto_awesome_mosaic),
                      ),
                    ],
                  ),
        ));
      },
    );
  }

  Widget _buildCoursesPanel() {
    return Column(
      children: [
        SearchFilterWidget(onSearchChanged: onSearchChanged),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: CoursesTabWidget(
              courses: _filteredCourses,
              selectedSections: _timetable!.selectedSections,
              onSectionToggle: (courseCode, sectionId, isSelected) {
                if (isSelected) {
                  removeSection(courseCode, sectionId);
                } else {
                  addSection(courseCode, sectionId);
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
                onClear: clearTimetable,
                onRemoveSection: removeSection,
                size: _userSettingsService.getTimetableSize(
                  _timetable!.id,
                ),
                hasUnsavedChanges: _hasUnsavedChanges,
                isSaving: _isSaving,
                onSave: _authService.isGuest ? null : saveTimetable,
                onAutoLoadCDCs: autoLoadCDCs,
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
                availableCourses: _timetable!.availableCourses,
                selectedSections: _timetable!.selectedSections,
                onQuickReplace: quickReplaceCourse,
                onSectionShuffle: sectionShuffle,
                onUndo: undo,
                onRedo: redo,
                canUndo: undoRedoService.canUndo,
                canRedo: undoRedoService.canRedo,
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
      showErrorDialog('Import failed: $e');
    }
  }

  Future<void> _exportToTTWithFilePicker() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      showErrorDialog('No sections selected to export');
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
      showErrorDialog('Export failed: $e');
    }
  }
}

class _HomeScreenWithTimetableState extends State<HomeScreenWithTimetable> with TimetableEditorMixin<HomeScreenWithTimetable> {
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
  bool _showSavedIndicator = false;
  Timer? _savedIndicatorTimer;

  @override Timetable? get currentTimetable => _timetable;
  @override bool get isSaving => _isSaving;
  @override set isSaving(bool v) => _isSaving = v;
  @override bool get hasUnsavedChanges => _hasUnsavedChanges;
  @override set hasUnsavedChanges(bool v) => _hasUnsavedChanges = v;
  @override GlobalKey get timetableKey => _timetableKey;
  @override TimetableService get timetableService => _timetableService;
  @override AuthService get authService => _authService;
  @override PageLeaveWarningService get pageLeaveWarning => _pageLeaveWarning;
  @override void onUnsavedChangesChanged(bool value) => widget.onUnsavedChangesChanged?.call(value);
  @override List<Course> get filteredCourses => _filteredCourses;
  @override set filteredCourses(List<Course> v) => _filteredCourses = v;
  @override void setCurrentTimetable(Timetable tt) => _timetable = tt;

  @override
  void initState() {
    super.initState();
    _timetable = widget.timetable;
    _filteredCourses = _timetable.availableCourses;
    _initializeUserSettings();
  }

  @override
  void dispose() {
    _savedIndicatorTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeUserSettings() async {
    await _userSettingsService.initializeSettings();
  }

  @override
  void triggerSavedIndicator() {
    _savedIndicatorTimer?.cancel();
    setState(() => _showSavedIndicator = true);
    _savedIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSavedIndicator = false);
    });
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

        return GestureDetector(
          onHorizontalDragUpdate: (_) {
            // Consume horizontal drag gestures to prevent iOS back swipe
          },
          child: wrapWithKeyboardShortcuts(Scaffold(
            appBar: AppBar(
              title: Text(_timetable.name),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
              ),
            actions: [
              if (_showSavedIndicator)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: AppDesign.success(context), size: 18),
                      const SizedBox(width: 4),
                      Text('Saved', style: TextStyle(color: AppDesign.success(context), fontSize: 13)),
                    ],
                  ),
                ),
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
                        FadeSlidePageRoute(page: const CourseGuideScreen()),
                      );
                      break;
                    case 'prerequisites':
                      Navigator.push(
                        context,
                        FadeSlidePageRoute(page: const PrerequisitesScreen()),
                      );
                      break;
                    case 'discipline_electives':
                      Navigator.push(
                        context,
                        FadeSlidePageRoute(page: const DisciplineElectivesScreen()),
                      );
                      break;
                    case 'humanities_electives':
                      Navigator.push(
                        context,
                        FadeSlidePageRoute(page: const HumanitiesElectivesScreen()),
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
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: shareTimetable,
                tooltip: 'Share Timetable',
              ),
              const ThemeToggleButton(),
              if (isWideScreen) ...[
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: exportToICS,
                  tooltip: 'Export to ICS',
                ),
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: exportToPNG,
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
                      exportToICS();
                    } else if (value == 'export_png') {
                      exportToPNG();
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
                onPressed: () => openGitHub(),
                tooltip: 'Star on GitHub',
              ),
              // User info and logout
              if (_authService.isAuthenticated)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'logout') {
                      logout();
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
                                  ? _authService.userPhotoImage
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
                        onPressed: openAddSwap,
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
                        onPressed: openGenerator,
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
                        onPressed: openAddSwap,
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
                        onPressed: openGenerator,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        tooltip: 'TT Generator',
                        heroTag: 'generator',
                        child: const Icon(Icons.auto_awesome_mosaic),
                      ),
                    ],
                  ),
        )),
      );
      },
    );
  }

  Widget _buildCoursesPanel() {
    return Column(
      children: [
        SearchFilterWidget(onSearchChanged: onSearchChanged),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: CoursesTabWidget(
              courses: _filteredCourses,
              selectedSections: _timetable.selectedSections,
              onSectionToggle: (courseCode, sectionId, isSelected) {
                if (isSelected) {
                  removeSection(courseCode, sectionId);
                } else {
                  addSection(courseCode, sectionId);
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
                onClear: clearTimetable,
                onRemoveSection: removeSection,
                size: _userSettingsService.getTimetableSize(_timetable.id),
                hasUnsavedChanges: _hasUnsavedChanges,
                isSaving: _isSaving,
                onSave: _authService.isGuest ? null : saveTimetable,
                onAutoLoadCDCs: autoLoadCDCs,
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
                availableCourses: _timetable.availableCourses,
                selectedSections: _timetable.selectedSections,
                onQuickReplace: quickReplaceCourse,
                onSectionShuffle: sectionShuffle,
                onUndo: undo,
                onRedo: redo,
                canUndo: undoRedoService.canUndo,
                canRedo: undoRedoService.canRedo,
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
      showErrorDialog('Import failed: $e');
    }
  }

  Future<void> _exportToTTWithFilePicker() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      showErrorDialog('No sections selected to export');
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
      showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _exportToTT() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      showErrorDialog('No sections selected to export');
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
      showErrorDialog('Export failed: $e');
    }
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/timetable_service.dart';
import '../services/auth_service.dart';
import '../services/page_leave_warning_service.dart';
import '../services/toast_service.dart';
import '../services/campus_service.dart';
import '../services/course_data_service.dart';
import '../services/user_settings_service.dart';
import '../services/responsive_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/shimmer_loading.dart';
import '../mixins/timetable_editor_mixin.dart';

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
  @override UserSettingsService get userSettingsService => _userSettingsService;
  @override void onUnsavedChangesChanged(bool value) {}
  @override List<Course> get filteredCourses => _filteredCourses;
  @override set filteredCourses(List<Course> v) => _filteredCourses = v;
  @override void setCurrentTimetable(Timetable tt) => _timetable = tt;

  @override
  void initState() {
    super.initState();
    _loadTimetable();
    initializeUserSettings();
    _campusSubscription = CampusService.campusChangeStream.listen((_) {
      _loadTimetable();
    });
  }

  @override
  void dispose() {
    disposeSavedIndicator();
    _campusSubscription?.cancel();
    super.dispose();
  }

  @override
  void onCampusChanged(Campus campus) {
    CourseDataService().clearCache();
    _loadTimetable();
    ToastService.showInfo(
      'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
    );
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
      setState(() => _isLoading = false);
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
          return const Scaffold(body: TimetableListSkeleton());
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
                      borderRadius: AppDesign.borderRadiusSm,
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

        return GestureDetector(
          onHorizontalDragUpdate: (_) {},
          child: wrapWithKeyboardShortcuts(Scaffold(
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('images/full_logo_bg.png', height: 32, fit: BoxFit.contain),
                ],
              ),
              actions: buildCommonActions(),
            ),
            body: buildBodyLayout(isWideScreen),
            floatingActionButton: buildFABs(isWideScreen),
          )),
        );
      },
    );
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
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;

  @override Timetable? get currentTimetable => _timetable;
  @override bool get isSaving => _isSaving;
  @override set isSaving(bool v) => _isSaving = v;
  @override bool get hasUnsavedChanges => _hasUnsavedChanges;
  @override set hasUnsavedChanges(bool v) => _hasUnsavedChanges = v;
  @override GlobalKey get timetableKey => _timetableKey;
  @override TimetableService get timetableService => _timetableService;
  @override AuthService get authService => _authService;
  @override PageLeaveWarningService get pageLeaveWarning => _pageLeaveWarning;
  @override UserSettingsService get userSettingsService => _userSettingsService;
  @override void onUnsavedChangesChanged(bool value) => widget.onUnsavedChangesChanged?.call(value);
  @override List<Course> get filteredCourses => _filteredCourses;
  @override set filteredCourses(List<Course> v) => _filteredCourses = v;
  @override void setCurrentTimetable(Timetable tt) => _timetable = tt;

  @override
  void initState() {
    super.initState();
    _timetable = widget.timetable;
    _filteredCourses = _timetable.availableCourses;
    initializeUserSettings();
  }

  @override
  void dispose() {
    disposeSavedIndicator();
    super.dispose();
  }

  @override
  void onCampusChanged(Campus campus) async {
    CourseDataService().clearCache();
    try {
      final courseDataService = CourseDataService();
      final newCourses = await courseDataService.fetchCourses();
      setState(() {
        _timetable = Timetable(
          id: _timetable.id,
          name: _timetable.name,
          createdAt: _timetable.createdAt,
          updatedAt: DateTime.now(),
          campus: campus,
          availableCourses: newCourses,
          selectedSections: [],
          clashWarnings: [],
        );
        _filteredCourses = newCourses;
        _hasUnsavedChanges = true;
      });
      widget.onUnsavedChangesChanged?.call(true);
      _pageLeaveWarning.enableWarning(true);
      ToastService.showInfo(
        'Switched to ${CampusService.getCampusDisplayName(campus)} campus. Timetable cleared.',
      );
    } catch (e) {
      ToastService.showError('Error switching campus: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _userSettingsService,
      builder: (context, child) {
        final isWideScreen = ResponsiveService.isDesktop(context);

        return GestureDetector(
          onHorizontalDragUpdate: (_) {},
          child: wrapWithKeyboardShortcuts(Scaffold(
            appBar: AppBar(
              title: Text(_timetable.name),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
              ),
              actions: buildCommonActions(),
            ),
            body: buildBodyLayout(isWideScreen),
            floatingActionButton: buildFABs(isWideScreen),
          )),
        );
      },
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/core/timetable_service.dart';
import '../services/data/auth_service.dart';
import '../services/ui/page_leave_warning_service.dart';
import '../services/ui/toast_service.dart';
import '../services/data/campus_service.dart';
import '../services/data/course_data_service.dart';
import '../services/data/courses_master_service.dart';
import '../services/data/user_settings_service.dart';
import '../services/ui/responsive_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/shimmer_loading.dart';
import '../mixins/timetable_editor_mixin.dart';
import '../services/ui/tutorial_service.dart';

class HomeScreen extends StatefulWidget {
  final Timetable? timetable;
  final Function(bool)? onUnsavedChangesChanged;

  const HomeScreen({
    super.key,
    this.timetable,
    this.onUnsavedChangesChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Kept for backward compatibility — redirects to [HomeScreen].
class HomeScreenWithTimetable extends StatelessWidget {
  final Timetable timetable;
  final Function(bool)? onUnsavedChangesChanged;

  const HomeScreenWithTimetable({
    super.key,
    required this.timetable,
    this.onUnsavedChangesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      timetable: timetable,
      onUnsavedChangesChanged: onUnsavedChangesChanged,
    );
  }
}

class _HomeScreenState extends State<HomeScreen>
    with TimetableEditorMixin<HomeScreen> {
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

  bool get _isStandalone => widget.timetable == null;

  @override
  Timetable? get currentTimetable => _timetable;
  @override
  bool get isSaving => _isSaving;
  @override
  set isSaving(bool v) => _isSaving = v;
  @override
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  @override
  set hasUnsavedChanges(bool v) => _hasUnsavedChanges = v;
  @override
  GlobalKey get timetableKey => _timetableKey;
  @override
  TimetableService get timetableService => _timetableService;
  @override
  AuthService get authService => _authService;
  @override
  PageLeaveWarningService get pageLeaveWarning => _pageLeaveWarning;
  @override
  UserSettingsService get userSettingsService => _userSettingsService;
  @override
  void onUnsavedChangesChanged(bool value) =>
      widget.onUnsavedChangesChanged?.call(value);
  @override
  List<Course> get filteredCourses => _filteredCourses;
  @override
  set filteredCourses(List<Course> v) => _filteredCourses = v;
  @override
  void setCurrentTimetable(Timetable tt) => _timetable = tt;

  @override
  void initState() {
    super.initState();
    if (_isStandalone) {
      _loadTimetable();
      _campusSubscription = CampusService.campusChangeStream.listen((_) {
        _loadTimetable();
      });
    } else {
      _timetable = widget.timetable;
      _filteredCourses = _timetable!.availableCourses;
      _isLoading = false;
    }
    initializeUserSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        TutorialService().showEditorTutorial(context);
        // Recovers the Tools menu for users who skipped the full tour.
        TutorialService().showToolsSpotlight(context);
      });
    });
  }

  @override
  void dispose() {
    disposeSavedIndicator();
    _campusSubscription?.cancel();
    // Leaving the editor (incl. discarding unsaved changes) must drop the web
    // beforeunload prompt so it doesn't linger on other screens.
    _pageLeaveWarning.clear('timetable');
    super.dispose();
  }

  @override
  void onCampusChanged(Campus campus) async {
    CourseDataService().clearCache();
    CoursesMasterService().clear();
    CoursesMasterService().loadForCampus(forceRefresh: true);

    if (_isStandalone) {
      _loadTimetable();
      ToastService.showInfo(
        'Switched to ${CampusService.getCampusDisplayName(campus)} campus',
      );
    } else {
      try {
        final courseDataService = CourseDataService();
        final newCourses = await courseDataService.fetchCourses();
        setState(() {
          _timetable = Timetable(
            id: _timetable!.id,
            name: _timetable!.name,
            createdAt: _timetable!.createdAt,
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
            appBar: AppDesign.appBar(
              context,
              titleWidget: AppDesign.appLogo(context),
            ),
            body: const EmptyStateWidget(
              icon: Icons.error_outline,
              title: 'Failed to load timetable',
              subtitle: 'Please try again or check your connection',
            ),
          );
        }

        final isWideScreen = ResponsiveService.isDesktop(context);

        return GestureDetector(
          onHorizontalDragUpdate: (_) {},
          child: wrapWithKeyboardShortcuts(Scaffold(
            appBar: AppDesign.appBar(
              context,
              titleWidget: _isStandalone
                  ? AppDesign.appLogo(context, height: 32)
                  : Text(_timetable!.name),
              leading: _isStandalone
                  ? null
                  : IconButton(
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

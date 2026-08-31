import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable_maker/mixins/timetable_editor_mixin.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/core/timetable_service.dart';
import 'package:timetable_maker/services/data/auth_service.dart';
import 'package:timetable_maker/services/data/user_settings_service.dart';
import 'package:timetable_maker/services/ui/page_leave_warning_service.dart';

import '../helpers/mock_services.dart';
import '../helpers/test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('collapsing the course browser preserves unsaved selections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final course = makeCourse();
    final timetableService = MockTimetableService();
    when(
      () => timetableService.generateTimetableSlots(any(), any()),
    ).thenReturn([]);
    when(
      () => timetableService.getIncompleteSelectionWarnings(any(), any()),
    ).thenReturn([]);
    final timetable = makeTimetable(
      courses: [course],
      selectedSections: [
        makeSelectedSection(
          courseCode: course.courseCode,
          sectionId: course.sections.first.sectionId,
          section: course.sections.first,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: _EditorLayoutHarness(
          timetable: timetable,
          timetableService: timetableService,
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Collapse course browser'), findsOneWidget);
    expect(timetable.selectedSections, hasLength(1));

    await tester.tap(find.byTooltip('Collapse course browser'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Expand courses panel'), findsOneWidget);
    expect(timetable.selectedSections, hasLength(1));
  });
}

class _EditorLayoutHarness extends StatefulWidget {
  const _EditorLayoutHarness({
    required this.timetable,
    required this.timetableService,
  });

  final Timetable timetable;
  final TimetableService timetableService;

  @override
  State<_EditorLayoutHarness> createState() => _EditorLayoutHarnessState();
}

class _EditorLayoutHarnessState extends State<_EditorLayoutHarness>
    with TimetableEditorMixin<_EditorLayoutHarness> {
  final _timetableKey = GlobalKey();
  final _authService = AuthService();
  final _pageLeaveWarning = PageLeaveWarningService();
  final _userSettingsService = UserSettingsService();
  var _isSaving = false;
  var _hasUnsavedChanges = true;
  late List<Course> _filteredCourses = widget.timetable.availableCourses;

  @override
  Timetable get currentTimetable => widget.timetable;

  @override
  bool get isSaving => _isSaving;

  @override
  set isSaving(bool value) => _isSaving = value;

  @override
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  @override
  set hasUnsavedChanges(bool value) => _hasUnsavedChanges = value;

  @override
  GlobalKey get timetableKey => _timetableKey;

  @override
  TimetableService get timetableService => widget.timetableService;

  @override
  AuthService get authService => _authService;

  @override
  PageLeaveWarningService get pageLeaveWarning => _pageLeaveWarning;

  @override
  UserSettingsService get userSettingsService => _userSettingsService;

  @override
  List<Course> get filteredCourses => _filteredCourses;

  @override
  set filteredCourses(List<Course> value) => _filteredCourses = value;

  @override
  void onUnsavedChangesChanged(bool value) {}

  @override
  void setCurrentTimetable(Timetable timetable) {}

  @override
  void onCampusChanged(Campus campus) {}

  @override
  bool get hasBranchForPools => false;

  @override
  Future<void> loadElectivePools() async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: buildBodyLayout(true));
  }
}

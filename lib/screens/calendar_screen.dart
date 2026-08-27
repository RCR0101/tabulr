import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../services/ui/responsive_service.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../widgets/common/shimmer_loading.dart';
import '../models/course_announcement.dart';
import '../services/core/timetable_service.dart';
import '../services/data/exam_seating_service.dart';
import '../services/data/course_announcement_service.dart';
import '../services/data/professor_service.dart';
import '../services/data/auth_service.dart';
import '../services/data/calendar_prefs_service.dart';
import '../services/data/config_service.dart';
import '../services/data/course_data_service.dart';
import '../services/ui/toast_service.dart';
import '../models/calendar_event.dart';
import '../models/academic_calendar_event.dart';
import '../services/data/academic_calendar_service.dart';
import '../widgets/academic_calendar_list.dart';
import '../utils/datetime_utils.dart';
import '../utils/calendar_period.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_tappable.dart';
import '../widgets/common/app_button.dart';
import '../utils/page_info_helper.dart';
import '../services/ui/tutorial_service.dart';
import '../widgets/command_palette.dart';
import '../widgets/app_destinations.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final TimetableService _timetableService = TimetableService();
  final ExamSeatingService _examSeatingService = ExamSeatingService();
  final CourseAnnouncementService _announcementService =
      CourseAnnouncementService();
  final ProfessorService _professorService = ProfessorService();
  final AuthService _authService = AuthService();
  final CalendarPrefsService _calendarPrefsService = CalendarPrefsService();

  List<Timetable> _timetables = [];
  Timetable? _selectedTimetable;
  bool _isLoading = true;

  String? _studentId;
  List<ExamSeating> _examSeatingData = [];
  Map<String, ExamRoom?> _examRooms = {};

  List<CourseAnnouncement> _announcements = [];
  StreamSubscription? _announcementSub;

  List<CalendarEvent> _customEvents = [];
  Map<String, Course> _courseMap = {};
  final ConfigService _config = ConfigService();
  List<AcademicCalendarEvent> _academicEvents = [];

  // Scrapped (dismissed) slots: keys are "day-hour" for timetable, event IDs for custom
  Set<String> _scrappedForWeek = {};
  // Time indicator timer removed — each _TimeIndicatorLine owns its own.

  DateTime _weekStart = _mondayOf(DateTime.now());
  int _mobileDayIndex = calendarDayIndex(DateTime.now()); // 0=Mon, 5=Sat

  static DateTime _mondayOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String get _weekKey {
    final d = _weekStart;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    unawaited(_professorService.loadProfessors());
    CommandPaletteActions.register(
      DrawerScreen.calendar,
      () => [
        CommandPaletteEntry(
          label: 'Add Event',
          subtitle: 'Add a custom calendar event',
          icon: Icons.add,
          category: CommandCategory.context,
          onSelect: _addEvent,
        ),
        CommandPaletteEntry(
          label: 'Academic Calendar',
          subtitle: 'Holidays, deadlines and exam windows',
          icon: Icons.event_note,
          category: CommandCategory.context,
          onSelect: _showAcademicCalendar,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _announcementSub?.cancel();
    CommandPaletteActions.unregister(DrawerScreen.calendar);
    super.dispose();
  }

  String? get _calendarPrefsUid => _authService.userDocId;

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final (timetables, userData, allExams, courses, prefsDoc) =
          await (
            _timetableService.getAllTimetables(),
            _examSeatingService.loadUserData(),
            _examSeatingService.fetchAllExamSeating(),
            CourseDataService().fetchCourses().catchError((_) => <Course>[]),
            _calendarPrefsUid != null
                ? _calendarPrefsService.getPrefs(_calendarPrefsUid!)
                : Future.value(null),
          ).wait;

      final courseMap = {for (final c in courses) c.courseCode: c};
      String? savedTimetableId;
      var customEvents = <CalendarEvent>[];
      if (prefsDoc != null && prefsDoc.exists) {
        final data = prefsDoc.data();
        if (data != null) {
          savedTimetableId = data['selectedTimetableId'] as String?;
          final eventsRaw = data['customEvents'] as List<dynamic>? ?? [];
          customEvents =
              eventsRaw
                  .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
                  .toList();
        }
      }

      Timetable? selected;
      if (savedTimetableId != null) {
        selected =
            timetables.where((t) => t.id == savedTimetableId).firstOrNull;
      }
      selected ??= timetables.isNotEmpty ? timetables.first : null;

      if (!mounted) return;

      final studentId = userData?.studentId;
      setState(() {
        _timetables = timetables;
        _selectedTimetable = selected;
        _studentId = studentId;
        _examSeatingData = allExams;
        _courseMap = courseMap;
        _customEvents = customEvents;
        _examRooms = _resolvedExamRooms(selected, studentId, allExams);
        _academicEvents = [];
        _isLoading = false;
      });
      _watchAnnouncements();
      _loadAcademicCalendar(selected);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastService.showError('Failed to load calendar data');
    }
  }

  Map<String, ExamRoom?> _resolvedExamRooms(
    Timetable? timetable,
    String? studentId,
    List<ExamSeating> exams,
  ) {
    if (timetable == null || studentId == null || studentId.isEmpty) {
      return {};
    }

    final examsByCourse = <String, ExamSeating>{};
    for (final exam in exams) {
      examsByCourse.putIfAbsent(exam.courseCode, () => exam);
    }
    final rooms = <String, ExamRoom?>{};
    for (final code in timetable.selectedSections.map((s) => s.courseCode)) {
      final exam = examsByCourse[code];
      if (exam != null) rooms[code] = exam.findRoomForStudent(studentId);
    }
    return rooms;
  }

  void _watchAnnouncements() {
    _announcementSub?.cancel();
    if (_selectedTimetable == null) return;

    final codes =
        _selectedTimetable!.selectedSections
            .map((s) => s.courseCode)
            .toSet()
            .toList();

    if (codes.isEmpty) return;

    _announcementSub = _announcementService
        .watchAnnouncements(codes, _selectedTimetable!.campus.code)
        .listen((announcements) {
          if (mounted) {
            setState(() => _announcements = announcements);
          }
        });
  }

  Future<void> _savePrefs() async {
    final uid = _calendarPrefsUid;
    if (uid == null) return;

    await _calendarPrefsService.savePrefs(uid, {
      'selectedTimetableId': _selectedTimetable?.id,
      'customEvents': _customEvents.map((e) => e.toJson()).toList(),
    });
  }

  // Check if a timetable clashes with existing custom events
  List<String> _findClashes(Timetable timetable) {
    final clashes = <String>[];

    for (final sel in timetable.selectedSections) {
      for (final entry in sel.section.schedule) {
        for (final day in entry.days) {
          for (final hour in entry.hours) {
            for (final event in _customEvents) {
              if (event.day == day && event.occupiedHours.contains(hour)) {
                clashes.add(
                  '${sel.courseCode} (${_dayLabel(day)} H$hour) clashes with "${event.title}"',
                );
              }
            }
          }
        }
      }
    }
    return clashes;
  }

  Future<void> _onTimetableChanged(Timetable? timetable) async {
    if (timetable == null) return;

    final clashes = _findClashes(timetable);
    if (clashes.isNotEmpty) {
      final proceed = await AppDialog.adaptive<bool>(
        context: context,
        title: 'Schedule Clash',
        icon: Icons.warning_amber,
        iconColor: AppDesign.warning(context),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This timetable clashes with your custom events:'),
            const SizedBox(height: 12),
            ...clashes
                .take(5)
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: AppDesign.warning(context),
                        ),
                        const SizedBox(width: AppDesign.spacingSm),
                        Expanded(
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
            if (clashes.length > 5)
              Text(
                '...and ${clashes.length - 5} more',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: AppDesign.opacityMedium,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onTap: () => Navigator.pop(context, false),
          ),
          AppButton(
            label: 'Switch Anyway',
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      );

      if (proceed != true) return;
    }

    setState(() {
      _selectedTimetable = timetable;
      _scrappedForWeek = {};
      _announcements = [];
      _academicEvents = [];
      _examRooms = _resolvedExamRooms(timetable, _studentId, _examSeatingData);
    });
    _watchAnnouncements();
    _loadAcademicCalendar(timetable);
    _savePrefs();
  }

  void _previousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
      _scrappedForWeek = {};
    });
  }

  void _nextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
      _scrappedForWeek = {};
    });
  }

  void _goToToday() {
    final today = DateTime.now();
    setState(() {
      _weekStart = _mondayOf(today);
      _mobileDayIndex = calendarDayIndex(today);
      _scrappedForWeek = {};
    });
  }

  Future<void> _editStudentId() async {
    final result = await AppDialog.input(
      context: context,
      title: 'Student ID',
      initialValue: _studentId,
      hint: 'e.g. 2021A7PS0001H',
      confirmLabel: 'Save',
    );

    if (result != null && result.isNotEmpty) {
      final studentId = result.toUpperCase();
      setState(() {
        _studentId = studentId;
        _examRooms = _resolvedExamRooms(
          _selectedTimetable,
          studentId,
          _examSeatingData,
        );
      });

      final codes =
          _selectedTimetable?.selectedSections
              .map((s) => s.courseCode)
              .toList() ??
          [];
      await _examSeatingService.saveUserData(
        selectedCourseCodes: codes,
        studentId: studentId,
      );
    }
  }

  // --- Custom event management ---

  Future<void> _addEvent() async {
    final eventWidget = _AddEventDialog(
      professorService: _professorService,
      initialDay: _bitsDayFor(_mobileDayIndex) ?? DayOfWeek.M,
      selectedTimetable: _selectedTimetable,
      existingEvents: _customEvents,
    );
    final CalendarEvent? result;
    if (ResponsiveService.isMobile(context)) {
      result = await showModalBottomSheet<CalendarEvent>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder:
            (ctx) => DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollController) => eventWidget,
            ),
      );
    } else {
      result = await showDialog<CalendarEvent>(
        context: context,
        builder: (ctx) => eventWidget,
      );
    }

    if (result != null) {
      setState(() => _customEvents.add(result!));
      _savePrefs();
    }
  }

  void _deleteEvent(CalendarEvent event) {
    setState(() {
      _customEvents.removeWhere((e) => e.id == event.id);
    });
    _savePrefs();
    ToastService.showSuccess('Event removed');
  }

  void _scrapSlot(String slotKey) {
    setState(() {
      _scrappedForWeek.add('$_weekKey:$slotKey');
    });
  }

  void _scrapCourseForWeek(_CalendarItem item) {
    setState(() {
      if (item.type == _ItemType.classSlot && _selectedTimetable != null) {
        for (final sel in _selectedTimetable!.selectedSections) {
          if (sel.courseCode != item.title) continue;
          for (final entry in sel.section.schedule) {
            for (final day in entry.days) {
              for (final hour in entry.hours) {
                _scrappedForWeek.add('$_weekKey:class-${day.name}-$hour');
              }
            }
          }
        }
      } else if (item.type == _ItemType.customEvent && item.event != null) {
        for (final h in item.event!.occupiedHours) {
          _scrappedForWeek.add('$_weekKey:event-${item.event!.id}-$h');
        }
      } else {
        _scrappedForWeek.add('$_weekKey:${item.slotKey}');
      }
    });
  }

  void _unscrapSlot(String slotKey) {
    setState(() {
      _scrappedForWeek.remove('$_weekKey:$slotKey');
    });
  }

  void _scrapAllForDay(DayOfWeek day) {
    setState(() {
      // Scrap all timetable slots for this day
      if (_selectedTimetable != null) {
        for (final sel in _selectedTimetable!.selectedSections) {
          for (final entry in sel.section.schedule) {
            if (entry.days.contains(day)) {
              for (final hour in entry.hours) {
                _scrappedForWeek.add('$_weekKey:class-${day.name}-$hour');
              }
            }
          }
        }
      }
      // Scrap all custom events for this day
      for (final event in _customEvents) {
        if (event.day == day) {
          for (final h in event.occupiedHours) {
            _scrappedForWeek.add('$_weekKey:event-${event.id}-$h');
          }
        }
      }
    });
  }

  void _scrapAllForWeek() {
    setState(() {
      if (_selectedTimetable != null) {
        for (final sel in _selectedTimetable!.selectedSections) {
          for (final entry in sel.section.schedule) {
            for (final day in entry.days) {
              for (final hour in entry.hours) {
                _scrappedForWeek.add('$_weekKey:class-${day.name}-$hour');
              }
            }
          }
        }
      }
      for (final event in _customEvents) {
        for (final h in event.occupiedHours) {
          _scrappedForWeek.add('$_weekKey:event-${event.id}-$h');
        }
      }
    });
  }

  static String _dedupeInstructor(String raw) {
    final parts = raw
        .split(RegExp(r'[,/]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final seen = <String>{};
    final unique = <String>[];
    for (final p in parts) {
      if (seen.add(p.toLowerCase())) unique.add(p);
    }
    return unique.join(', ');
  }

  bool _isScrapped(String slotKey) =>
      _scrappedForWeek.contains('$_weekKey:$slotKey');

  CalendarPeriod _periodForDate(DateTime date) => calendarPeriodForDate(
    date,
    midsemStart: _config.midsemStart,
    midsemEnd: _config.midsemEnd,
    endsemStart: _config.endsemStart,
    endsemEnd: _config.endsemEnd,
  );

  // Build calendar items for a given day, merging consecutive identical slots
  /// The [DayOfWeek] for a 0-based week-column index, or null for Sunday
  /// (index 6), which the enum has no value for. The week runs Mon(0)…Sun(6).
  static DayOfWeek? _bitsDayFor(int index) => calendarDayForIndex(index);

  /// Day-column items for [day]. [day] is null for Sunday, which has no
  /// [DayOfWeek] and therefore no classes or custom events — only the
  /// date-based exam items during exam weeks.
  List<_CalendarItem> _itemsForDay(DayOfWeek? day, {DateTime? date}) {
    final items = <_CalendarItem>[];
    if (_selectedTimetable == null) {
      _addCustomEvents(items, day);
      return items;
    }

    final period = date != null ? _periodForDate(date) : CalendarPeriod.classes;

    // During exam periods, show exams instead of recurring classes
    if (period == CalendarPeriod.midsem || period == CalendarPeriod.endsem) {
      if (date != null) {
        items.addAll(_examItemsForDate(date, period));
      }
      // Still show custom events during exam weeks
      _addCustomEvents(items, day);
      return items;
    }

    // No classes on Sunday.
    if (day == null) return items;

    // Collect raw per-hour entries grouped by section identity
    final sectionSlots = <String, _RawSlotGroup>{};

    for (final sel in _selectedTimetable!.selectedSections) {
      for (final entry in sel.section.schedule) {
        if (entry.days.contains(day)) {
          final groupKey = '${sel.courseCode}|${sel.sectionId}';
          sectionSlots.putIfAbsent(
            groupKey,
            () => _RawSlotGroup(
              courseCode: sel.courseCode,
              sectionId: sel.sectionId,
              room: sel.section.room,
              instructor: _dedupeInstructor(sel.section.instructor),
              color: _courseColor(sel.courseCode),
              hours: [],
            ),
          );
          sectionSlots[groupKey]!.hours.addAll(entry.hours);
        }
      }
    }

    // Merge consecutive hours into spans
    for (final group in sectionSlots.values) {
      final sorted = group.hours.toList()..sort();
      int spanStart = sorted.first;
      int spanEnd = spanStart;

      for (int i = 1; i < sorted.length; i++) {
        if (sorted[i] == spanEnd + 1) {
          spanEnd = sorted[i];
        } else {
          items.add(_makeClassItem(group, day, spanStart, spanEnd));
          spanStart = sorted[i];
          spanEnd = spanStart;
        }
      }
      items.add(_makeClassItem(group, day, spanStart, spanEnd));
    }

    _addCustomEvents(items, day);

    return items;
  }

  void _addCustomEvents(List<_CalendarItem> items, DayOfWeek? day) {
    if (day == null) return; // Custom events are Mon–Sat only.
    for (final event in _customEvents) {
      if (event.day == day) {
        final key = 'event-${event.id}-${event.hour}';
        final anyScrapped = event.occupiedHours.any(
          (h) => _isScrapped('event-${event.id}-$h'),
        );
        items.add(
          _CalendarItem(
            type: _ItemType.customEvent,
            title: event.title,
            subtitle: event.professorName ?? event.description ?? '',
            hour: event.hour,
            spanHours: event.durationHours,
            color:
                event.type == 'prof_meeting'
                    ? _courseColor('_prof_meeting')
                    : _courseColor('_custom_event'),
            slotKey: key,
            scrapped: anyScrapped,
            event: event,
          ),
        );
      }
    }
  }

  List<_CalendarItem> _examItemsForDate(DateTime date, CalendarPeriod period) {
    final items = <_CalendarItem>[];
    if (_selectedTimetable == null) return items;

    final isMidsem = period == CalendarPeriod.midsem;
    final examLabel = isMidsem ? 'MidSem' : 'Compre';

    final processedCourses = <String>{};
    for (final sel in _selectedTimetable!.selectedSections) {
      if (processedCourses.contains(sel.courseCode)) continue;
      processedCourses.add(sel.courseCode);

      final course = _courseMap[sel.courseCode];
      if (course == null) continue;

      final exam = isMidsem ? course.midSemExam : course.endSemExam;
      if (exam == null) continue;

      // Check if exam falls on this date
      if (exam.date.year != date.year ||
          exam.date.month != date.month ||
          exam.date.day != date.day) {
        continue;
      }

      // Map TimeSlot to grid hours using campus-specific times
      final campusCode = _selectedTimetable!.campus.code;
      final examTimes =
          ExamSlotConstants.campusExamStartTimes[campusCode] ??
          ExamSlotConstants.campusExamStartTimes['hyderabad']!;
      final examLabels =
          ExamSlotConstants.campusTimeSlotNames[campusCode] ??
          ExamSlotConstants.defaultTimeSlotNames;

      final examStartTime = examTimes[exam.timeSlot]!;
      final examStartHour = examStartTime[0];
      final examStartMin = examStartTime[1];

      // Fractional grid position: hour 1.0 = 8:00 AM, 2.5 = 9:30 AM, etc.
      final fractionalStart = (examStartHour - 8) + 1 + examStartMin / 60.0;
      // Integer hour for mobile list view (floor to nearest hour row)
      final gridHour = (examStartHour - 8) + 1;

      final durationMin =
          isMidsem
              ? ScheduleConstants.midsemExamDuration.inMinutes
              : ScheduleConstants.endsemExamDuration.inMinutes;
      final fractionalDuration = durationMin / 60.0;
      final intSpan = (durationMin / 60).ceil();

      final timeLabel = examLabels[exam.timeSlot] ?? '';

      // Look up exam room if we have student ID
      final roomInfo = _examRooms[sel.courseCode];

      items.add(
        _CalendarItem(
          type: _ItemType.exam,
          title: '$examLabel: ${sel.courseCode}',
          subtitle: timeLabel,
          examRoom: roomInfo?.roomNo,
          hour: gridHour,
          spanHours: intSpan,
          fractionalHour: fractionalStart,
          fractionalSpan: fractionalDuration,
          color:
              isMidsem
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.error,
          slotKey: 'exam-${sel.courseCode}-${date.day}',
          scrapped: false,
          examDate: '${date.day}/${date.month}/${date.year}',
        ),
      );
    }
    return items;
  }

  _CalendarItem _makeClassItem(
    _RawSlotGroup group,
    DayOfWeek day,
    int startHour,
    int endHour,
  ) {
    final span = endHour - startHour + 1;
    final key = 'class-${day.name}-$startHour';
    final anyScrapped = List.generate(
      span,
      (i) => startHour + i,
    ).any((h) => _isScrapped('class-${day.name}-$h'));

    return _CalendarItem(
      type: _ItemType.classSlot,
      title: group.courseCode,
      subtitle: '${group.sectionId} • ${group.room}',
      hour: startHour,
      spanHours: span,
      color: group.color,
      instructor: group.instructor,
      slotKey: key,
      scrapped: anyScrapped,
    );
  }

  /// Best-effort load of the selected timetable's campus academic calendar
  /// (holidays, deadlines, exam windows). A failure just leaves the overlay
  /// empty rather than disturbing the rest of the calendar.
  Future<void> _loadAcademicCalendar(Timetable? timetable) async {
    if (timetable == null) return;
    final campusId = timetable.campus.code;
    try {
      final events = await AcademicCalendarService().load(campusId: campusId);
      if (!mounted || _selectedTimetable?.campus.code != campusId) return;
      setState(() => _academicEvents = events);
    } catch (_) {
      // Overlay stays empty.
    }
  }

  /// The whole semester's holidays, deadlines and exam windows in one list.
  /// The week grid only shows the week in view, so this is the only way to see
  /// what is coming without paging through it.
  void _showAcademicCalendar() {
    showAcademicCalendarSheet(
      context,
      campusId: _selectedTimetable?.campus.code,
    );
  }

  List<_CalendarItem> _bannersForDay(DateTime date) {
    final items = <_CalendarItem>[];

    // Academic calendar (holidays, add/drop deadlines, exam windows).
    for (final ev in _academicEvents) {
      if (!ev.coversDay(date)) continue;
      items.add(
        _CalendarItem(
          type: _ItemType.academic,
          title: ev.label,
          subtitle:
              ev.isRange
                  ? 'Academic calendar · multi-day'
                  : 'Academic calendar',
          hour: 0,
          color: academicCategoryColor(context, ev.category),
          slotKey: 'acad-${ev.category.name}-${ev.label}-${date.day}',
        ),
      );
    }

    // Exam seating
    for (final entry in _examSeatingData) {
      if (_selectedTimetable == null) break;
      final codes =
          _selectedTimetable!.selectedSections.map((s) => s.courseCode).toSet();
      if (!codes.contains(entry.courseCode)) continue;

      final examDate = _parseExamDate(entry.examDate);
      if (examDate != null && _sameDay(examDate, date)) {
        final room = _examRooms[entry.courseCode];
        items.add(
          _CalendarItem(
            type: _ItemType.exam,
            title: '${entry.courseCode} Exam',
            subtitle: room != null ? 'Room ${room.roomNo}' : 'No room found',
            hour: 0,
            color: Colors.red.shade700,
            examDate: entry.examDate,
            slotKey: 'exam-${entry.courseCode}',
          ),
        );
      }
    }

    // Announcements
    for (final ann in _announcements) {
      if (_sameDay(ann.eventDate, date)) {
        items.add(
          _CalendarItem(
            type: _ItemType.announcement,
            title: ann.title,
            subtitle: ann.courseCode,
            hour: ann.startTime?.hour ?? 0,
            color: const Color(0xFFEF6C00),
            announcement: ann,
            slotKey: 'ann-${ann.id}',
          ),
        );
      }
    }

    return items;
  }

  DateTime? _parseExamDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        try {
          return DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        } catch (_) {}
      }
      return null;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Color _courseColor(String code) {
    final colors = AppDesign.timetableColors(context);
    final hash = code.hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _dayLabel(DayOfWeek d) => getDayName(d, abbreviated: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Calendar',
        actions: [
          PageInfoHelper.infoButton(
            context,
            PageInfoHelper.calendar,
            key: TutorialKeys.infoCalendar,
          ),
          const SizedBox(width: AppDesign.spacingSm),
        ],
      ),
      body:
          _isLoading
              ? const CalendarSkeleton()
              : LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 900;
                  return _buildCalendarBody(theme, compact: compact);
                },
              ),
    );
  }

  Widget _buildCalendarBody(ThemeData theme, {required bool compact}) {
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final viewKey = ValueKey(
      compact ? '$_weekKey-day-$_mobileDayIndex' : '$_weekKey-week',
    );
    final view = KeyedSubtree(
      key: viewKey,
      child: RepaintBoundary(
        child: compact ? _buildSingleDayView(theme) : _buildWeekView(theme),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerLowest,
            Color.alphaBlend(
              scheme.primary.withValues(alpha: .025),
              scheme.surfaceContainerLowest,
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          compact ? _buildMobileHeader(theme) : _buildDesktopHeader(theme),
          if (compact) _buildMobileDaySelector(theme),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 20,
                compact ? 8 : 0,
                compact ? 10 : 20,
                compact ? 10 : 20,
              ),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: AppDesign.borderRadiusLg,
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .65),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder:
                      (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                  child: view,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get isToday => _sameDay(_weekStart, _mondayOf(DateTime.now()));

  String _weekLabel({bool compact = false}) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    const months = DayConstants.monthNames;
    if (_weekStart.month == weekEnd.month) {
      return compact
          ? '${_weekStart.day}-${weekEnd.day} ${months[_weekStart.month]}'
          : '${_weekStart.day} - ${weekEnd.day} ${months[_weekStart.month]} ${_weekStart.year}';
    }
    return compact
        ? '${_weekStart.day} ${months[_weekStart.month]} - ${weekEnd.day} ${months[weekEnd.month]}'
        : '${_weekStart.day} ${months[_weekStart.month]} - ${weekEnd.day} ${months[weekEnd.month]} ${weekEnd.year}';
  }

  Widget _buildTimetableSelector(ThemeData theme) {
    if (_timetables.isEmpty) {
      return Text(
        'No timetable selected',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedTimetable?.id,
      isExpanded: true,
      decoration: AppDesign.inputDecoration(
        context,
        dense: true,
        label: 'Timetable',
      ),
      items:
          _timetables
              .map(
                (timetable) => DropdownMenuItem(
                  value: timetable.id,
                  child: Text(
                    timetable.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
      onChanged: (id) {
        if (id == null) return;
        _onTimetableChanged(
          _timetables.firstWhere((timetable) => timetable.id == id),
        );
      },
    );
  }

  Widget _buildWeekMenu({
    bool iconOnly = false,
    bool includeUtilities = false,
  }) {
    return PopupMenuButton<String>(
      tooltip: includeUtilities ? 'Calendar options' : 'Week options',
      icon: iconOnly ? const Icon(Icons.more_horiz_rounded) : null,
      onSelected: (value) {
        if (value == 'academic_dates') _showAcademicCalendar();
        if (value == 'student_id') _editStudentId();
        if (value == 'scrap_week') _scrapAllForWeek();
        if (value == 'restore_week') {
          setState(() {
            _scrappedForWeek.removeWhere((key) => key.startsWith(_weekKey));
          });
        }
      },
      itemBuilder:
          (context) => [
            if (includeUtilities) ...[
              const PopupMenuItem(
                value: 'academic_dates',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.event_note_outlined),
                  title: Text('Academic dates'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'student_id',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Student ID'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
            ],
            const PopupMenuItem(
              value: 'scrap_week',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.event_busy_outlined),
                title: Text('Scrap entire week'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'restore_week',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.restore_rounded),
                title: Text('Restore week'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
      child:
          iconOnly
              ? null
              : const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.more_horiz_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('Week options'),
                  ],
                ),
              ),
    );
  }

  Widget _buildDesktopHeader(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppDesign.borderRadiusLg,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppDesign.borderRadiusMd,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _previousWeek,
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: 'Previous week',
                    ),
                    SizedBox(
                      width: 270,
                      child: Text(
                        _weekLabel(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.4,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _nextWeek,
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: 'Next week',
                    ),
                  ],
                ),
              ),
              if (!isToday) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: _goToToday, child: const Text('Today')),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _showAcademicCalendar,
                icon: const Icon(Icons.event_note_outlined, size: 18),
                label: const Text('Academic dates'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _addEvent,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add event'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(width: 300, child: _buildTimetableSelector(theme)),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _editStudentId,
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: Text(
                  _studentId != null && _studentId!.isNotEmpty
                      ? _studentId!
                      : 'Set student ID',
                ),
              ),
              const Spacer(),
              _buildWeekMenu(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeader(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppDesign.borderRadiusLg,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: AppDesign.borderRadiusMd,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _previousWeek,
                        icon: const Icon(Icons.chevron_left_rounded),
                        tooltip: 'Previous week',
                      ),
                      Expanded(
                        child: Text(
                          _weekLabel(compact: true),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _nextWeek,
                        icon: const Icon(Icons.chevron_right_rounded),
                        tooltip: 'Next week',
                      ),
                    ],
                  ),
                ),
              ),
              if (!isToday)
                IconButton(
                  onPressed: _goToToday,
                  icon: const Icon(Icons.today_outlined, size: 20),
                  tooltip: 'Today',
                ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _addEvent,
                icon: const Icon(Icons.add_rounded, size: 20),
                tooltip: 'Add event',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTimetableSelector(theme)),
              const SizedBox(width: 4),
              _buildWeekMenu(iconOnly: true, includeUtilities: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDaySelector(ThemeData theme) {
    final days = List.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    final labels = DayConstants.weekDays;
    final today = DateTime.now();
    final selected = _mobileDayIndex.clamp(0, 6);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      height: 66,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppDesign.borderRadiusLg,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Row(
        children: List.generate(7, (index) {
          final current = _sameDay(days[index], today);
          final active = index == selected;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AppTappable(
                onTap: () => setState(() => _mobileDayIndex = index),
                child: AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : AppDesign.motionFast,
                  curve: AppDesign.curveStandard,
                  decoration: BoxDecoration(
                    color:
                        active ? scheme.primaryContainer : Colors.transparent,
                    borderRadius: AppDesign.borderRadiusSm,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        labels[index],
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              active
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${days[index].day}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color:
                              active
                                  ? scheme.onPrimaryContainer
                                  : current
                                  ? scheme.primary
                                  : scheme.onSurface,
                          fontWeight:
                              active || current
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSingleDayView(ThemeData theme) {
    final dayIndex = _mobileDayIndex.clamp(0, 6);
    final day = _bitsDayFor(dayIndex);
    final fullDayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final date = _weekStart.add(Duration(days: dayIndex));
    final items = _itemsForDay(day, date: date);
    final banners = _bannersForDay(date);

    const startHour = 1;
    const endHour = 12;

    final allBanners = <int, List<_CalendarItem>>{};
    for (final b in banners) {
      for (int h = b.hour; h < b.hour + b.spanHours; h++) {
        allBanners.putIfAbsent(h, () => []).add(b);
      }
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200 && dayIndex < 6) {
          setState(() => _mobileDayIndex = dayIndex + 1);
        } else if (details.primaryVelocity! > 200 && dayIndex > 0) {
          setState(() => _mobileDayIndex = dayIndex - 1);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: endHour - startHour + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            final monthDay = formatDayMonth(date);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Row(
                children: [
                  Text(
                    fullDayNames[dayIndex],
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: AppDesign.spacingSm),
                  Text(
                    monthDay,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            );
          }
          final hour = startHour + index - 1;
          final hourItems = items.where((it) => it.hour == hour).toList();
          final hourBanners = allBanners[hour] ?? [];

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: [
                        Text(
                          'H$hour',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          TimeSlotInfo.getHourSlotName(hour),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: ResponsiveService.clampedFontSize(
                              context,
                              9,
                            ),
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child:
                      hourItems.isEmpty && hourBanners.isEmpty
                          ? Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLowest,
                              borderRadius: AppDesign.borderRadiusSm,
                              border: Border(
                                bottom: BorderSide(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.06,
                                  ),
                                ),
                              ),
                            ),
                          )
                          : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...hourBanners.map(
                                (b) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: AppTappable(
                                    onTap: () => _showItemDetail(context, b),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: b.color.withValues(alpha: 0.15),
                                        borderRadius: AppDesign.borderRadiusSm,
                                      ),
                                      child: Text(
                                        b.title,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: b.color,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ...hourItems.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: _SlotBlock(
                                    item: item,
                                    onTap: () => _showItemDetail(context, item),
                                    onLongPress:
                                        () => _showItemDetail(context, item),
                                  ),
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
    );
  }

  Widget _buildWeekView(ThemeData theme) {
    final scheme = theme.colorScheme;
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final dayLabels = DayConstants.weekDays;
    final today = DateTime.now();
    final bitsDays = [for (var i = 0; i < 7; i++) _bitsDayFor(i)];
    final bannersByDay = [for (final day in days) _bannersForDay(day)];

    const startHour = 1;
    const endHour = 12;
    const hourHeight = 64.0;
    const headerHeight = 58.0;
    const timeColWidth = 60.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = (constraints.maxWidth - timeColWidth) / 7;

        return Column(
          children: [
            // Day headings stay visually quiet so events remain the focus.
            Container(
              height: headerHeight,
              color: scheme.surface,
              child: Row(
                children: [
                  SizedBox(width: timeColWidth),
                  ...List.generate(7, (index) {
                    final isDayToday = _sameDay(days[index], today);
                    final banners = bannersByDay[index];
                    final hasExam = banners.any(
                      (banner) => banner.type == _ItemType.exam,
                    );
                    final hasAnnouncement = banners.any(
                      (banner) => banner.type == _ItemType.announcement,
                    );
                    final bitsDay = bitsDays[index];

                    return GestureDetector(
                      onLongPress:
                          bitsDay == null ? null : () => _showDayMenu(bitsDay),
                      child: Container(
                        width: dayWidth.clamp(44.0, double.infinity),
                        decoration: BoxDecoration(
                          color:
                              isDayToday
                                  ? scheme.primary.withValues(alpha: .025)
                                  : null,
                          border: Border(
                            left: BorderSide(
                              color: scheme.outlineVariant.withValues(
                                alpha: .55,
                              ),
                            ),
                            bottom: BorderSide(
                              color:
                                  isDayToday
                                      ? scheme.primary
                                      : scheme.outlineVariant.withValues(
                                        alpha: .7,
                                      ),
                              width: isDayToday ? 2 : 1,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayLabels[index],
                              style: theme.textTheme.labelSmall?.copyWith(
                                color:
                                    isDayToday
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${days[index].day}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color:
                                    isDayToday
                                        ? scheme.primary
                                        : scheme.onSurface,
                                fontWeight:
                                    isDayToday
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasExam)
                                  Container(
                                    width: 4,
                                    height: 4,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: scheme.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (hasAnnouncement)
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEF6C00),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Banner row
            _buildBannerRow(bannersByDay, dayWidth, timeColWidth, theme),

            const Divider(height: 1),

            // Scrollable time grid
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: (endHour - startHour + 1) * hourHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Time labels
                      SizedBox(
                        width: timeColWidth,
                        child: Column(
                          children: List.generate(endHour - startHour + 1, (i) {
                            final hour = startHour + i;
                            final label =
                                TimeSlotInfo.hourSlotNames[hour]
                                    ?.split('-')[0]
                                    .trim() ??
                                '$hour';
                            return SizedBox(
                              height: hourHeight,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 2,
                                  ),
                                  child: Text(
                                    label,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                                      fontSize:
                                          ResponsiveService.clampedFontSize(
                                            context,
                                            10,
                                          ),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // Day columns
                      ...List.generate(7, (dayIdx) {
                        final dayItems = _itemsForDay(
                          bitsDays[dayIdx],
                          date: days[dayIdx],
                        );
                        final isToday = _sameDay(days[dayIdx], today);

                        return SizedBox(
                          width: dayWidth,
                          child: Stack(
                            children: [
                              // Today column tint
                              if (isToday)
                                Positioned.fill(
                                  child: Container(
                                    color: scheme.primary.withValues(
                                      alpha: 0.03,
                                    ),
                                  ),
                                ),
                              // Grid lines
                              ...List.generate(endHour - startHour + 1, (i) {
                                return Positioned(
                                  top: i * hourHeight,
                                  left: 0,
                                  right: 0,
                                  height: hourHeight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: scheme.outline.withValues(
                                            alpha: 0.1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              // Column separator
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: 0,
                                child: Container(
                                  width: 1,
                                  color: scheme.outline.withValues(alpha: 0.1),
                                ),
                              ),
                              // Items
                              ...dayItems.map((item) {
                                final top =
                                    (item.effectiveHour - startHour) *
                                    hourHeight;
                                final height =
                                    item.effectiveSpan * hourHeight - 2;
                                return Positioned(
                                  top: top + 1,
                                  left: 2,
                                  right: 2,
                                  height: height,
                                  child: _SlotBlock(
                                    item: item,
                                    onTap: () => _showItemDetail(context, item),
                                    onLongPress: () => _showSlotMenu(item),
                                  ),
                                );
                              }),
                              if (isToday)
                                _TimeIndicatorLine(
                                  startHour: startHour,
                                  endHour: endHour,
                                  hourHeight: hourHeight,
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBannerRow(
    List<List<_CalendarItem>> bannersByDay,
    double dayWidth,
    double timeColWidth,
    ThemeData theme,
  ) {
    if (bannersByDay.every((banners) => banners.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: timeColWidth),
          ...List.generate(7, (i) {
            final banners = bannersByDay[i];
            if (banners.isEmpty) return SizedBox(width: dayWidth);
            return SizedBox(
              width: dayWidth,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Column(
                  children:
                      banners.map((item) {
                        return AppTappable(
                          onTap: () => _showItemDetail(context, item),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: item.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border(
                                left: BorderSide(color: item.color, width: 3),
                              ),
                            ),
                            child: Text(
                              item.title,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: item.color,
                                fontWeight: FontWeight.w600,
                                fontSize: ResponsiveService.clampedFontSize(
                                  context,
                                  9,
                                ),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showDayMenu(DayOfWeek day) {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.event_busy),
                  title: Text('Scrap all for ${_dayLabel(day)}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _scrapAllForDay(day);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text('Restore all for ${_dayLabel(day)}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _scrappedForWeek.removeWhere(
                        (k) =>
                            k.startsWith('$_weekKey:') &&
                            k.contains('-${day.name}-'),
                      );
                    });
                  },
                ),
              ],
            ),
          ),
    );
  }

  void _showSlotMenu(_CalendarItem item) {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!item.scrapped)
                  ListTile(
                    leading: const Icon(Icons.event_busy),
                    title: const Text('Scrap for this week'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _scrapSlot(item.slotKey);
                    },
                  ),
                if (item.scrapped)
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _unscrapSlot(item.slotKey);
                    },
                  ),
                if (item.type == _ItemType.customEvent && item.event != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Delete event permanently'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteEvent(item.event!);
                    },
                  ),
              ],
            ),
          ),
    );
  }

  void _showItemDetail(BuildContext context, _CalendarItem item) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: item.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (item.scrapped)
                      Chip(
                        label: const Text(
                          'Scrapped',
                          style: TextStyle(fontSize: 11),
                        ),
                        backgroundColor: theme.colorScheme.error.withValues(
                          alpha: 0.1,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (item.subtitle.isNotEmpty)
                  _detailRow(Icons.info_outline, item.subtitle, theme),
                if (item.examRoom != null)
                  _detailRow(
                    Icons.meeting_room,
                    'Room ${item.examRoom}',
                    theme,
                  ),
                if (item.instructor != null)
                  _detailRow(Icons.person, item.instructor!, theme),
                if (item.type == _ItemType.classSlot)
                  _detailRow(
                    Icons.access_time,
                    TimeSlotInfo.getHourRangeName(
                      List.generate(item.spanHours, (i) => item.hour + i),
                    ),
                    theme,
                  ),
                if (item.type == _ItemType.customEvent && item.event != null)
                  _detailRow(
                    Icons.access_time,
                    item.event!.timeRangeLabel,
                    theme,
                  ),
                if (item.type == _ItemType.exam && item.examDate != null)
                  _detailRow(Icons.event, item.examDate!, theme),
                if (item.announcement != null &&
                    item.announcement!.description.isNotEmpty)
                  _detailRow(
                    Icons.description,
                    item.announcement!.description,
                    theme,
                  ),
                const SizedBox(height: AppDesign.spacingMd),
                Divider(color: theme.colorScheme.outlineVariant),
                const SizedBox(height: AppDesign.spacingSm),
                if (item.scrapped)
                  _actionTile(
                    ctx,
                    icon: Icons.restore,
                    label: 'Restore',
                    color: theme.colorScheme.primary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _unscrapSlot(item.slotKey);
                    },
                  )
                else ...[
                  _actionTile(
                    ctx,
                    icon: Icons.event_busy_outlined,
                    label: 'Scrap for today',
                    color: theme.colorScheme.onSurface,
                    onTap: () {
                      Navigator.pop(ctx);
                      _scrapSlot(item.slotKey);
                    },
                  ),
                  const SizedBox(height: AppDesign.spacingXs),
                  _actionTile(
                    ctx,
                    icon: Icons.event_busy,
                    label: 'Scrap for entire week',
                    color: theme.colorScheme.onSurface,
                    onTap: () {
                      Navigator.pop(ctx);
                      _scrapCourseForWeek(item);
                    },
                  ),
                ],
                if (item.type == _ItemType.customEvent &&
                    item.event != null) ...[
                  const SizedBox(height: AppDesign.spacingXs),
                  _actionTile(
                    ctx,
                    icon: Icons.delete_forever,
                    label: 'Delete event permanently',
                    color: theme.colorScheme.error,
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteEvent(item.event!);
                    },
                  ),
                ],
                const SizedBox(height: AppDesign.spacingSm),
              ],
            ),
          ),
    );
  }

  Widget _actionTile(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppDesign.borderRadiusSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppDesign.opacityMedium,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// --- Slot block widget ---

class _SlotBlock extends StatelessWidget {
  final _CalendarItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SlotBlock({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isScrapped = item.scrapped;
    final tall = item.spanHours > 1;

    return AppTappable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedOpacity(
        duration: AppDesign.motionFast,
        opacity: isScrapped ? .38 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: isScrapped ? .04 : .11),
            borderRadius: AppDesign.borderRadiusSm,
            border: Border.all(
              color: item.color.withValues(alpha: isScrapped ? .12 : .22),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                color:
                    isScrapped ? item.color.withValues(alpha: .35) : item.color,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    7,
                    tall ? 7 : 4,
                    6,
                    tall ? 7 : 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                          decoration:
                              isScrapped ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.examRoom != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.examRoom!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: item.color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (item.subtitle.isNotEmpty) ...[
                        SizedBox(height: tall ? 2 : 0),
                        Text(
                          item.subtitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: tall ? 10 : 9,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: tall ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (item.instructor != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.instructor!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: ResponsiveService.clampedFontSize(
                              context,
                              9,
                            ),
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: .72,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Add Event Dialog ---

class _AddEventDialog extends StatefulWidget {
  final ProfessorService professorService;
  final Timetable? selectedTimetable;
  final List<CalendarEvent> existingEvents;
  final DayOfWeek initialDay;

  const _AddEventDialog({
    required this.professorService,
    required this.initialDay,
    this.selectedTimetable,
    required this.existingEvents,
  });

  @override
  State<_AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<_AddEventDialog> {
  String _eventType = 'custom'; // 'custom' or 'prof_meeting'
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _profSearchController = TextEditingController();

  late DayOfWeek _selectedDay;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);

  Professor? _selectedProfessor;
  List<Professor> _profResults = [];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _profSearchController.dispose();
    super.dispose();
  }

  void _searchProfs(String query) {
    if (query.length < 2) {
      setState(() => _profResults = []);
      return;
    }
    final q = query.toLowerCase();
    final all = widget.professorService.professors;
    setState(() {
      _profResults =
          all.where((p) => p.name.toLowerCase().contains(q)).take(8).toList();
    });
  }

  List<ProfessorScheduleEntry> _profScheduleForDay(
    Professor prof,
    DayOfWeek day,
  ) {
    final dayStr = 'DayOfWeek.${day.name}';
    return prof.schedule.where((s) => s.days.contains(dayStr)).toList();
  }

  String? _clashReason() {
    final startSlot = timeToSlotHour(_startTime);
    final span = slotSpanFromTimes(_startTime, _endTime);
    final hours = List.generate(span, (i) => startSlot + i);

    // Check against timetable
    if (widget.selectedTimetable != null) {
      for (final sel in widget.selectedTimetable!.selectedSections) {
        for (final entry in sel.section.schedule) {
          if (entry.days.contains(_selectedDay)) {
            for (final h in hours) {
              if (entry.hours.contains(h)) {
                return 'Clashes with ${sel.courseCode} in your timetable';
              }
            }
          }
        }
      }
    }

    // Check against existing custom events
    for (final event in widget.existingEvents) {
      if (event.day == _selectedDay) {
        for (final h in hours) {
          if (event.occupiedHours.contains(h)) {
            return 'Clashes with "${event.title}"';
          }
        }
      }
    }

    // Check against professor's schedule (for prof meetings)
    if (_eventType == 'prof_meeting' && _selectedProfessor != null) {
      final profEntries = _profScheduleForDay(
        _selectedProfessor!,
        _selectedDay,
      );
      for (final entry in profEntries) {
        for (final h in hours) {
          if (entry.hours.contains(h)) {
            return '${_selectedProfessor!.name} has a class (${entry.courseCode}) at this time';
          }
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clashMsg = _clashReason();

    return AlertDialog(
      title: const Text('Add Event'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Event type
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'custom',
                    label: Text('Custom'),
                    icon: Icon(Icons.event),
                  ),
                  ButtonSegment(
                    value: 'prof_meeting',
                    label: Text('Prof Meeting'),
                    icon: Icon(Icons.person),
                  ),
                ],
                selected: {_eventType},
                onSelectionChanged: (val) {
                  setState(() {
                    _eventType = val.first;
                    if (_eventType == 'prof_meeting') {
                      _titleController.text = '';
                    }
                  });
                },
              ),
              const SizedBox(height: AppDesign.spacingMd),

              if (_eventType == 'prof_meeting') ...[
                TextField(
                  controller: _profSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search professor',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _searchProfs,
                ),
                if (_profResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                      borderRadius: AppDesign.borderRadiusSm,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _profResults.length,
                      itemBuilder: (_, i) {
                        final prof = _profResults[i];
                        final isSelected = _selectedProfessor?.id == prof.id;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          title: Text(prof.name),
                          subtitle: Text(
                            'Chamber: ${prof.chamber}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedProfessor = prof;
                              _profSearchController.text = prof.name;
                              _profResults = [];
                              _titleController.text =
                                  'Meeting with ${prof.name}';
                            });
                          },
                        );
                      },
                    ),
                  ),
                if (_selectedProfessor != null) ...[
                  const SizedBox(height: 12),
                  _buildProfScheduleInfo(theme),
                ],
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Event title'),
              ),
              const SizedBox(height: 12),

              if (_eventType == 'custom')
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 2,
                ),
              if (_eventType == 'custom') const SizedBox(height: 12),

              // Day picker
              DropdownButtonFormField<DayOfWeek>(
                initialValue: _selectedDay,
                decoration: const InputDecoration(
                  labelText: 'Day',
                  isDense: true,
                ),
                items:
                    DayOfWeek.values.map((d) {
                      return DropdownMenuItem(
                        value: d,
                        child: Text(getDayName(d)),
                      );
                    }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDay = val);
                },
              ),
              const SizedBox(height: 12),

              // Start time + end time
              Row(
                children: [
                  Expanded(
                    child: _TimeTile(
                      label: 'Start time',
                      time: _startTime,
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (picked != null) {
                          setState(() {
                            _startTime = picked;
                            // Auto-advance end if it's before start
                            if (_endTime.hour * 60 + _endTime.minute <=
                                picked.hour * 60 + picked.minute) {
                              _endTime = TimeOfDay(
                                hour: picked.hour + 1,
                                minute: picked.minute,
                              );
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeTile(
                      label: 'End time',
                      time: _endTime,
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (picked != null) {
                          setState(() => _endTime = picked);
                        }
                      },
                    ),
                  ),
                ],
              ),

              if (_endTime.hour * 60 + _endTime.minute <=
                  _startTime.hour * 60 + _startTime.minute) ...[
                const SizedBox(height: AppDesign.spacingSm),
                Text(
                  'End time must be after start time',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppDesign.danger(context),
                  ),
                ),
              ],

              if (clashMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppDesign.spacingSm),
                  decoration: BoxDecoration(
                    color: AppDesign.warning(context).withValues(alpha: 0.1),
                    borderRadius: AppDesign.borderRadiusSm,
                    border: Border.all(
                      color: AppDesign.warning(context).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: AppDesign.warning(context),
                        size: 18,
                      ),
                      const SizedBox(width: AppDesign.spacingSm),
                      Expanded(
                        child: Text(
                          clashMsg,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppDesign.warning(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _titleController.text.trim().isEmpty ||
                      (_endTime.hour * 60 + _endTime.minute <=
                          _startTime.hour * 60 + _startTime.minute)
                  ? null
                  : () {
                    final startSlot = timeToSlotHour(_startTime);
                    final span = slotSpanFromTimes(_startTime, _endTime);
                    final event = CalendarEvent(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: _titleController.text.trim(),
                      description:
                          _descController.text.trim().isNotEmpty
                              ? _descController.text.trim()
                              : null,
                      type: _eventType,
                      professorId: _selectedProfessor?.id,
                      professorName: _selectedProfessor?.name,
                      day: _selectedDay,
                      hour: startSlot.clamp(1, 12),
                      durationHours: span,
                      startTime: _startTime,
                      endTime: _endTime,
                    );
                    Navigator.pop(context, event);
                  },
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildProfScheduleInfo(ThemeData theme) {
    final prof = _selectedProfessor!;
    final dayEntries = _profScheduleForDay(prof, _selectedDay);

    if (dayEntries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppDesign.success(context).withValues(alpha: 0.1),
          borderRadius: AppDesign.borderRadiusSm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: AppDesign.success(context),
              size: 18,
            ),
            const SizedBox(width: AppDesign.spacingSm),
            Text(
              '${prof.name} has no classes on ${dayFullName(_selectedDay)}',
              style: TextStyle(fontSize: 12, color: AppDesign.success(context)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppDesign.borderRadiusSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${prof.name}\'s classes on ${dayFullName(_selectedDay)}:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ...dayEntries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.courseCode} (${entry.sectionId}) — ${entry.hourRangeString}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Models ---

enum _ItemType { classSlot, exam, announcement, customEvent, academic }

class _TimeIndicatorLine extends StatefulWidget {
  final int startHour;
  final int endHour;
  final double hourHeight;

  const _TimeIndicatorLine({
    required this.startHour,
    required this.endHour,
    required this.hourHeight,
  });

  @override
  State<_TimeIndicatorLine> createState() => _TimeIndicatorLineState();
}

class _TimeIndicatorLineState extends State<_TimeIndicatorLine> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fractional = (now.hour - 8) + now.minute / 60.0;
    final range = (widget.endHour - widget.startHour + 1).toDouble();
    if (fractional < 0 || fractional > range) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: fractional * widget.hourHeight - 1,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: scheme.error,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: scheme.error.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: scheme.error,
                boxShadow: [
                  BoxShadow(
                    color: scheme.error.withValues(alpha: 0.2),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarItem {
  final _ItemType type;
  final String title;
  final String subtitle;
  final int hour;
  final int spanHours;
  final double? fractionalHour;
  final double? fractionalSpan;
  final Color color;
  final String? instructor;
  final String? examDate;
  final String? examRoom;
  final CourseAnnouncement? announcement;
  final String slotKey;
  final bool scrapped;
  final CalendarEvent? event;

  _CalendarItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.hour,
    this.spanHours = 1,
    this.fractionalHour,
    this.fractionalSpan,
    required this.color,
    this.instructor,
    this.examDate,
    this.examRoom,
    this.announcement,
    required this.slotKey,
    this.scrapped = false,
    this.event,
  });

  double get effectiveHour => fractionalHour ?? hour.toDouble();
  double get effectiveSpan => fractionalSpan ?? spanHours.toDouble();
}

class _RawSlotGroup {
  final String courseCode;
  final String sectionId;
  final String room;
  final String instructor;
  final Color color;
  final List<int> hours;

  _RawSlotGroup({
    required this.courseCode,
    required this.sectionId,
    required this.room,
    required this.instructor,
    required this.color,
    required this.hours,
  });
}

class _TimeTile extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _TimeTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final m = time.minute.toString().padLeft(2, '0');
    final p = time.hour < 12 ? 'AM' : 'PM';

    return InkWell(
      onTap: onTap,
      borderRadius: AppDesign.borderRadiusMd,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Text('$h:$m $p', style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

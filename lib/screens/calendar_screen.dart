import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/responsive_service.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../widgets/common/shimmer_loading.dart';
import '../models/course_announcement.dart';
import '../services/timetable_service.dart';
import '../services/exam_seating_service.dart';
import '../services/course_announcement_service.dart';
import '../services/professor_service.dart';
import '../services/auth_service.dart';
import '../services/config_service.dart';
import '../services/course_data_service.dart';
import '../services/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/app_button.dart';


int _timeToSlotHour(TimeOfDay t) => t.hour - 7;

int _slotSpanFromTimes(TimeOfDay start, TimeOfDay end) {
  final startSlot = _timeToSlotHour(start);
  final endSlot = _timeToSlotHour(end);
  return (endSlot - startSlot).clamp(1, 12);
}

String _dayFullName(DayOfWeek day) {
  const names = {
    DayOfWeek.M: 'Monday', DayOfWeek.T: 'Tuesday', DayOfWeek.W: 'Wednesday',
    DayOfWeek.Th: 'Thursday', DayOfWeek.F: 'Friday', DayOfWeek.S: 'Saturday',
  };
  return names[day] ?? day.name;
}

class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final String type; // 'prof_meeting', 'custom'
  final String? professorId;
  final String? professorName;
  final DayOfWeek day;
  final int hour;
  final int durationHours;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;

  CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.type,
    this.professorId,
    this.professorName,
    required this.day,
    required this.hour,
    this.durationHours = 1,
    this.startTime,
    this.endTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'type': type,
        'professorId': professorId,
        'professorName': professorName,
        'day': day.toString(),
        'hour': hour,
        'durationHours': durationHours,
        if (startTime != null) 'startTimeHour': startTime!.hour,
        if (startTime != null) 'startTimeMinute': startTime!.minute,
        if (endTime != null) 'endTimeHour': endTime!.hour,
        if (endTime != null) 'endTimeMinute': endTime!.minute,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    TimeOfDay? start;
    TimeOfDay? end;
    if (json['startTimeHour'] != null) {
      start = TimeOfDay(hour: json['startTimeHour'], minute: json['startTimeMinute'] ?? 0);
    }
    if (json['endTimeHour'] != null) {
      end = TimeOfDay(hour: json['endTimeHour'], minute: json['endTimeMinute'] ?? 0);
    }
    return CalendarEvent(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      type: json['type'] ?? 'custom',
      professorId: json['professorId'],
      professorName: json['professorName'],
      day: DayOfWeek.values.firstWhere(
        (e) => e.toString() == json['day'],
        orElse: () => DayOfWeek.M,
      ),
      hour: json['hour'] ?? 1,
      durationHours: json['durationHours'] ?? 1,
      startTime: start,
      endTime: end,
    );
  }

  List<int> get occupiedHours =>
      List.generate(durationHours, (i) => hour + i);

  String get timeRangeLabel {
    if (startTime != null && endTime != null) {
      return '${_formatTime(startTime!)} – ${_formatTime(endTime!)}';
    }
    final slotStart = TimeSlotInfo.hourSlotNames[hour] ?? '';
    return slotStart.isNotEmpty ? slotStart : 'Hour $hour';
  }

  static String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $p';
  }
}

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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  // Scrapped (dismissed) slots: keys are "day-hour" for timetable, event IDs for custom
  Set<String> _scrappedForWeek = {};

  DateTime _weekStart = _mondayOf(DateTime.now());
  int _mobileDayIndex = DateTime.now().weekday - 1; // 0=Mon, 5=Sat

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
  }

  @override
  void dispose() {
    _announcementSub?.cancel();
    super.dispose();
  }

  DocumentReference? get _calendarPrefsRef {
    final uid = _authService.userDocId;
    if (uid == null) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('calendar_prefs')
        .doc('data');
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final (timetables, userData, allExams, _, courses, prefsDoc) =
          await (
        _timetableService.getAllTimetables(),
        _examSeatingService.loadUserData(),
        _examSeatingService.fetchAllExamSeating(),
        _professorService.loadProfessors(),
        CourseDataService().fetchCourses().catchError((_) => <Course>[]),
        _calendarPrefsRef?.get() ?? Future.value(null),
      ).wait;

      _courseMap = {for (final c in courses) c.courseCode: c};

      String? savedTimetableId;
      if (prefsDoc != null && prefsDoc.exists) {
        final data = prefsDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          savedTimetableId = data['selectedTimetableId'] as String?;
          final eventsRaw = data['customEvents'] as List<dynamic>? ?? [];
          _customEvents = eventsRaw
              .map((e) =>
                  CalendarEvent.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }

      Timetable? selected;
      if (savedTimetableId != null) {
        selected = timetables
            .where((t) => t.id == savedTimetableId)
            .firstOrNull;
      }
      selected ??= timetables.isNotEmpty ? timetables.first : null;

      setState(() {
        _timetables = timetables;
        _selectedTimetable = selected;
        _studentId = userData?.studentId;
        _examSeatingData = allExams;
      });

      _resolveExamRooms();
      _watchAnnouncements();
    } catch (e) {
      ToastService.showError('Failed to load calendar data');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _resolveExamRooms() {
    if (_selectedTimetable == null ||
        _studentId == null ||
        _studentId!.isEmpty) {
      setState(() => _examRooms = {});
      return;
    }

    final rooms = <String, ExamRoom?>{};
    final courseCodes =
        _selectedTimetable!.selectedSections.map((s) => s.courseCode).toSet();

    for (final code in courseCodes) {
      final exam =
          _examSeatingData.where((e) => e.courseCode == code).firstOrNull;
      if (exam != null) {
        rooms[code] = exam.findRoomForStudent(_studentId!);
      }
    }

    setState(() => _examRooms = rooms);
  }

  void _watchAnnouncements() {
    _announcementSub?.cancel();
    if (_selectedTimetable == null) return;

    final codes = _selectedTimetable!.selectedSections
        .map((s) => s.courseCode)
        .toSet()
        .toList();

    if (codes.isEmpty) return;

    _announcementSub =
        _announcementService.watchAnnouncements(codes).listen((announcements) {
      if (mounted) {
        setState(() => _announcements = announcements);
      }
    });
  }

  Future<void> _savePrefs() async {
    final prefsRef = _calendarPrefsRef;
    if (prefsRef == null) return;

    await prefsRef.set({
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
                    '${sel.courseCode} (${_dayLabel(day)} H$hour) clashes with "${event.title}"');
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
            const Text(
                'This timetable clashes with your custom events:'),
            const SizedBox(height: 12),
            ...clashes
                .take(5)
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber,
                              size: 16, color: AppDesign.warning(context)),
                          const SizedBox(width: AppDesign.spacingSm),
                          Expanded(
                              child: Text(c,
                                  style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    )),
            if (clashes.length > 5)
              Text('...and ${clashes.length - 5} more',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: AppDesign.opacityMedium))),
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
    });
    _resolveExamRooms();
    _watchAnnouncements();
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
    setState(() {
      _weekStart = _mondayOf(DateTime.now());
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
      setState(() => _studentId = result.toUpperCase());

      final codes = _selectedTimetable?.selectedSections
              .map((s) => s.courseCode)
              .toList() ??
          [];
      await _examSeatingService.saveUserData(
        selectedCourseCodes: codes,
        studentId: result.toUpperCase(),
      );

      _resolveExamRooms();
    }
  }

  // --- Custom event management ---

  Future<void> _addEvent() async {
    final eventWidget = _AddEventDialog(
      professorService: _professorService,
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
        builder: (ctx) => DraggableScrollableSheet(
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
    final parts = raw.split(RegExp(r'[,/]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    final seen = <String>{};
    final unique = <String>[];
    for (final p in parts) {
      if (seen.add(p.toLowerCase())) unique.add(p);
    }
    return unique.join(', ');
  }

  bool _isScrapped(String slotKey) =>
      _scrappedForWeek.contains('$_weekKey:$slotKey');



  _PeriodType _periodForDate(DateTime date) {
    if (date.isAfter(_config.semesterEnd)) return _PeriodType.afterSemester;
    if (!date.isBefore(_config.midsemStart) && !date.isAfter(_config.midsemEnd)) {
      return _PeriodType.midsem;
    }
    if (!date.isBefore(_config.endsemStart) && !date.isAfter(_config.endsemEnd)) {
      return _PeriodType.endsem;
    }
    if (date.isBefore(_config.semesterStart)) return _PeriodType.beforeSemester;
    return _PeriodType.classes;
  }

  // Build calendar items for a given day, merging consecutive identical slots
  List<_CalendarItem> _itemsForDay(DayOfWeek day, {DateTime? date}) {
    final items = <_CalendarItem>[];
    if (_selectedTimetable == null) return items;

    final period = date != null ? _periodForDate(date) : _PeriodType.classes;

    // During exam periods or after semester, show exams instead of classes
    if (period == _PeriodType.midsem || period == _PeriodType.endsem) {
      if (date != null) {
        items.addAll(_examItemsForDate(date, period));
      }
      // Still show custom events during exam weeks
      _addCustomEvents(items, day);
      return items;
    }

    if (period == _PeriodType.afterSemester || period == _PeriodType.beforeSemester) {
      _addCustomEvents(items, day);
      return items;
    }

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

  void _addCustomEvents(List<_CalendarItem> items, DayOfWeek day) {
    for (final event in _customEvents) {
      if (event.day == day) {
        final key = 'event-${event.id}-${event.hour}';
        final anyScrapped = event.occupiedHours
            .any((h) => _isScrapped('event-${event.id}-$h'));
        items.add(_CalendarItem(
          type: _ItemType.customEvent,
          title: event.title,
          subtitle: event.professorName ?? event.description ?? '',
          hour: event.hour,
          spanHours: event.durationHours,
          color: event.type == 'prof_meeting'
              ? _courseColor('_prof_meeting')
              : _courseColor('_custom_event'),
          slotKey: key,
          scrapped: anyScrapped,
          event: event,
        ));
      }
    }
  }

  List<_CalendarItem> _examItemsForDate(DateTime date, _PeriodType period) {
    final items = <_CalendarItem>[];
    if (_selectedTimetable == null) return items;

    final isMidsem = period == _PeriodType.midsem;
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

      // Map TimeSlot to grid hours
      int startHour;
      int spanHours;
      String timeLabel;
      switch (exam.timeSlot) {
        case TimeSlot.MS1:
          startHour = 2; timeLabel = '9:30 - 11:00'; spanHours = 2;
        case TimeSlot.MS2:
          startHour = 4; timeLabel = '11:30 - 1:00'; spanHours = 2;
        case TimeSlot.MS3:
          startHour = 7; timeLabel = '2:00 - 3:30'; spanHours = 2;
        case TimeSlot.MS4:
          startHour = 9; timeLabel = '4:00 - 5:30'; spanHours = 2;
        case TimeSlot.FN:
          startHour = 1; timeLabel = '9:00 - 12:00'; spanHours = 4;
        case TimeSlot.AN:
          startHour = 8; timeLabel = '2:00 - 5:00'; spanHours = 3;
      }

      // Look up exam room if we have student ID
      final roomInfo = _examRooms[sel.courseCode];

      items.add(_CalendarItem(
        type: _ItemType.exam,
        title: '$examLabel: ${sel.courseCode}',
        subtitle: timeLabel,
        examRoom: roomInfo?.roomNo,
        hour: startHour,
        spanHours: spanHours,
        color: isMidsem
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.error,
        slotKey: 'exam-${sel.courseCode}-${date.day}',
        scrapped: false,
        examDate: '${date.day}/${date.month}/${date.year}',
      ));
    }
    return items;
  }

  _CalendarItem _makeClassItem(
      _RawSlotGroup group, DayOfWeek day, int startHour, int endHour) {
    final span = endHour - startHour + 1;
    final key = 'class-${day.name}-$startHour';
    final anyScrapped = List.generate(span, (i) => startHour + i)
        .any((h) => _isScrapped('class-${day.name}-$h'));

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

  List<_CalendarItem> _bannersForDay(DateTime date) {
    final items = <_CalendarItem>[];

    // Exam seating
    for (final entry in _examSeatingData) {
      if (_selectedTimetable == null) break;
      final codes =
          _selectedTimetable!.selectedSections.map((s) => s.courseCode).toSet();
      if (!codes.contains(entry.courseCode)) continue;

      final examDate = _parseExamDate(entry.examDate);
      if (examDate != null && _sameDay(examDate, date)) {
        final room = _examRooms[entry.courseCode];
        items.add(_CalendarItem(
          type: _ItemType.exam,
          title: '${entry.courseCode} Exam',
          subtitle: room != null ? 'Room ${room.roomNo}' : 'No room found',
          hour: 0,
          color: Colors.red.shade700,
          examDate: entry.examDate,
          slotKey: 'exam-${entry.courseCode}',
        ));
      }
    }

    // Announcements
    for (final ann in _announcements) {
      if (_sameDay(ann.eventDate, date)) {
        items.add(_CalendarItem(
          type: _ItemType.announcement,
          title: ann.title,
          subtitle: ann.courseCode,
          hour: ann.startTime?.hour ?? 0,
          color: const Color(0xFFEF6C00),
          announcement: ann,
          slotKey: 'ann-${ann.id}',
        ));
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
              int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
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

  String _dayLabel(DayOfWeek d) {
    switch (d) {
      case DayOfWeek.M:
        return 'Mon';
      case DayOfWeek.T:
        return 'Tue';
      case DayOfWeek.W:
        return 'Wed';
      case DayOfWeek.Th:
        return 'Thu';
      case DayOfWeek.F:
        return 'Fri';
      case DayOfWeek.S:
        return 'Sat';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'scrap_week') _scrapAllForWeek();
              if (val == 'restore_week') {
                setState(() {
                  _scrappedForWeek.removeWhere((k) => k.startsWith(_weekKey));
                });
              }
              if (val == 'student_id') _editStudentId();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'scrap_week',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.event_busy),
                  title: Text('Scrap entire week'),
                ),
              ),
              const PopupMenuItem(
                value: 'restore_week',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.restore),
                  title: Text('Restore week'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'student_id',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Set Student ID'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const CalendarSkeleton()
          : Column(
              children: [
                _buildHeader(theme),
                _buildWeekNav(theme),
                const Divider(height: 1),
                if (ResponsiveService.isMobile(context)) ...[
                  _buildMobileDaySelector(theme),
                  Expanded(child: _buildSingleDayView(theme)),
                ] else
                  Expanded(child: _buildWeekView(theme)),
              ],
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    if (_timetables.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Text(
          'No timetables found. Create one in TT Builder first.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedTimetable?.id,
              decoration: const InputDecoration(
                labelText: 'Timetable',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: _timetables.map((tt) {
                return DropdownMenuItem(value: tt.id, child: Text(tt.name));
              }).toList(),
              onChanged: (id) {
                if (id == null) return;
                final tt = _timetables.firstWhere((t) => t.id == id);
                _onTimetableChanged(tt);
              },
            ),
          ),
          if (_studentId != null && _studentId!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Chip(
              avatar: const Icon(Icons.badge, size: 16),
              label: Text(_studentId!, style: const TextStyle(fontSize: 12)),
            ),
          ],
          if (!isToday) ...[
            const SizedBox(width: AppDesign.spacingSm),
            IconButton(
              icon: const Icon(Icons.today, size: 20),
              tooltip: 'Go to today',
              onPressed: _goToToday,
            ),
          ],
        ],
      ),
    );
  }

  bool get isToday => _sameDay(_weekStart, _mondayOf(DateTime.now()));

  Widget _buildWeekNav(ThemeData theme) {
    final weekEnd = _weekStart.add(const Duration(days: 5));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    String label;
    if (_weekStart.month == weekEnd.month) {
      label =
          '${_weekStart.day} - ${weekEnd.day} ${months[_weekStart.month - 1]} ${_weekStart.year}';
    } else {
      label =
          '${_weekStart.day} ${months[_weekStart.month - 1]} - ${weekEnd.day} ${months[weekEnd.month - 1]} ${weekEnd.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left), onPressed: _previousWeek),
          Text(label,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          IconButton(
              icon: const Icon(Icons.chevron_right), onPressed: _nextWeek),
        ],
      ),
    );
  }

  Widget _buildMobileDaySelector(ThemeData theme) {
    final days = List.generate(6, (i) => _weekStart.add(Duration(days: i)));
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final today = DateTime.now();

    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: 6,
        itemBuilder: (context, i) {
          final isToday = _sameDay(days[i], today);
          final isSelected = i == _mobileDayIndex.clamp(0, 5);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => setState(() => _mobileDayIndex = i),
              child: Container(
                width: 54,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : isToday
                          ? theme.colorScheme.primary.withValues(alpha: AppDesign.opacityDivider)
                          : Colors.transparent,
                  borderRadius: AppDesign.borderRadiusMd,
                  border: isToday && !isSelected
                      ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayLabels[i],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${days[i].day}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSingleDayView(ThemeData theme) {
    final dayIndex = _mobileDayIndex.clamp(0, 5);
    final bitsDays = [DayOfWeek.M, DayOfWeek.T, DayOfWeek.W, DayOfWeek.Th, DayOfWeek.F, DayOfWeek.S];
    final fullDayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final day = bitsDays[dayIndex];
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
        if (details.primaryVelocity! < -200 && dayIndex < 5) {
          setState(() => _mobileDayIndex = dayIndex + 1);
        } else if (details.primaryVelocity! > 200 && dayIndex > 0) {
          setState(() => _mobileDayIndex = dayIndex - 1);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: endHour - startHour + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final monthDay = '${date.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][date.month - 1]}';
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
                Icon(Icons.swipe, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                const SizedBox(width: AppDesign.spacingXs),
                Text(
                  'Swipe to change day',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        TimeSlotInfo.getHourSlotName(hour),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: ResponsiveService.clampedFontSize(context, 9),
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: hourItems.isEmpty && hourBanners.isEmpty
                    ? Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLowest,
                          borderRadius: AppDesign.borderRadiusSm,
                          border: Border(
                            bottom: BorderSide(
                              color: theme.colorScheme.outline.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          'Free',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...hourBanners.map((b) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: GestureDetector(
                                  onTap: () => _showItemDetail(context, b),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: b.color.withValues(alpha: 0.15),
                                      borderRadius: AppDesign.borderRadiusSm,
                                    ),
                                    child: Text(
                                      b.title,
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: b.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              )),
                          ...hourItems.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _SlotBlock(
                                  item: item,
                                  onTap: () => _showItemDetail(context, item),
                                  onLongPress: () => _showItemDetail(context, item),
                                ),
                              )),
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
    final days = List.generate(6, (i) => _weekStart.add(Duration(days: i)));
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final today = DateTime.now();
    final bitsDays = [
      DayOfWeek.M,
      DayOfWeek.T,
      DayOfWeek.W,
      DayOfWeek.Th,
      DayOfWeek.F,
      DayOfWeek.S,
    ];

    const startHour = 1;
    const endHour = 12;
    const hourHeight = 64.0;
    const headerHeight = 60.0;
    const timeColWidth = 56.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = (constraints.maxWidth - timeColWidth) / 6;

        return Column(
          children: [
            // Day headers
            SizedBox(
              height: headerHeight,
              child: Row(
                children: [
                  SizedBox(width: timeColWidth),
                  ...List.generate(6, (i) {
                    final isToday = _sameDay(days[i], today);
                    final banners = _bannersForDay(days[i]);
                    final hasExam =
                        banners.any((b) => b.type == _ItemType.exam);
                    final hasAnn =
                        banners.any((b) => b.type == _ItemType.announcement);

                    return GestureDetector(
                      onLongPress: () => _showDayMenu(bitsDays[i]),
                      child: SizedBox(
                        width: dayWidth.clamp(44.0, double.infinity),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayLabels[i],
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isToday
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: AppDesign.opacityMedium),
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isToday
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${days[i].day}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isToday
                                      ? theme.colorScheme.onPrimary
                                      : null,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasExam)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(
                                        top: 2, right: 2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                if (hasAnn)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(top: 2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFFEF6C00),
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
            _buildBannerRow(days, dayWidth, timeColWidth, theme),

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
                          children:
                              List.generate(endHour - startHour + 1, (i) {
                            final hour = startHour + i;
                            final label = TimeSlotInfo.hourSlotNames[hour]
                                    ?.split('-')[0]
                                    .trim() ??
                                '$hour';
                            return SizedBox(
                              height: hourHeight,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(right: 6, top: 2),
                                  child: Text(
                                    label,
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5),
                                      fontSize: ResponsiveService.clampedFontSize(context, 10),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // Day columns
                      ...List.generate(6, (dayIdx) {
                        final dayItems = _itemsForDay(bitsDays[dayIdx], date: days[dayIdx]);
                        final now = DateTime.now();
                        final isToday = days[dayIdx].year == now.year &&
                            days[dayIdx].month == now.month &&
                            days[dayIdx].day == now.day;
                        // Hour 1 = 8:00 AM, so offset = (nowHour - 8) + min/60
                        final nowFractional =
                            (now.hour - 8) + now.minute / 60.0;
                        final nowInRange = nowFractional >= 0 &&
                            nowFractional <=
                                (endHour - startHour + 1).toDouble();

                        return SizedBox(
                          width: dayWidth,
                          child: Stack(
                            children: [
                              // Grid lines + alternating background
                              ...List.generate(endHour - startHour + 1, (i) {
                                final hour = startHour + i;
                                final hasItem = dayItems.any((it) => it.hour == hour || (it.hour < hour && it.hour + it.spanHours > hour));
                                return Positioned(
                                  top: i * hourHeight,
                                  left: 0,
                                  right: 0,
                                  height: hourHeight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: hasItem ? null : (i.isEven ? theme.colorScheme.surfaceContainerLowest : null),
                                      border: Border(
                                        top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: 0,
                                child: Container(
                                  width: 1,
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.08),
                                ),
                              ),
                              // Items
                              ...dayItems.map((item) {
                                final top =
                                    (item.hour - startHour) * hourHeight;
                                final height =
                                    item.spanHours * hourHeight - 2;
                                return Positioned(
                                  top: top + 1,
                                  left: 2,
                                  right: 2,
                                  height: height,
                                  child: _SlotBlock(
                                    item: item,
                                    onTap: () =>
                                        _showItemDetail(context, item),
                                    onLongPress: () =>
                                        _showSlotMenu(item),
                                  ),
                                );
                              }),
                              if (isToday && nowInRange)
                                Positioned(
                                  top: nowFractional * hourHeight,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.error,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 2,
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
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
    List<DateTime> days,
    double dayWidth,
    double timeColWidth,
    ThemeData theme,
  ) {
    final allBanners = <int, List<_CalendarItem>>{};
    bool any = false;
    for (int i = 0; i < 6; i++) {
      final banners = _bannersForDay(days[i]);
      allBanners[i] = banners;
      if (banners.isNotEmpty) any = true;
    }

    if (!any) return const SizedBox.shrink();

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: timeColWidth),
          ...List.generate(6, (i) {
            final banners = allBanners[i] ?? [];
            if (banners.isEmpty) return SizedBox(width: dayWidth);
            return SizedBox(
              width: dayWidth,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Column(
                  children: banners.map((item) {
                    return GestureDetector(
                      onTap: () => _showItemDetail(context, item),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 3),
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border(
                              left:
                                  BorderSide(color: item.color, width: 3)),
                        ),
                        child: Text(
                          item.title,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: item.color,
                            fontWeight: FontWeight.w600,
                            fontSize: ResponsiveService.clampedFontSize(context, 9),
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
      builder: (ctx) => SafeArea(
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
                      (k) => k.startsWith('$_weekKey:') && k.contains('-${day.name}-'));
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
      builder: (ctx) => SafeArea(
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
                leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
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
      builder: (ctx) => Padding(
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
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: item.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (item.scrapped)
                  Chip(
                    label: const Text('Scrapped',
                        style: TextStyle(fontSize: 11)),
                    backgroundColor:
                        theme.colorScheme.error.withValues(alpha: 0.1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.subtitle.isNotEmpty)
              _detailRow(Icons.info_outline, item.subtitle, theme),
            if (item.examRoom != null)
              _detailRow(Icons.meeting_room, 'Room ${item.examRoom}', theme),
            if (item.instructor != null)
              _detailRow(Icons.person, item.instructor!, theme),
            if (item.type == _ItemType.classSlot)
              _detailRow(
                  Icons.access_time,
                  TimeSlotInfo.getHourRangeName(
                      List.generate(item.spanHours, (i) => item.hour + i)),
                  theme),
            if (item.type == _ItemType.customEvent && item.event != null)
              _detailRow(Icons.access_time, item.event!.timeRangeLabel, theme),
            if (item.type == _ItemType.exam && item.examDate != null)
              _detailRow(Icons.event, item.examDate!, theme),
            if (item.announcement != null &&
                item.announcement!.description.isNotEmpty)
              _detailRow(
                  Icons.description, item.announcement!.description, theme),
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
            if (item.type == _ItemType.customEvent && item.event != null) ...[
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
          Icon(icon,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: AppDesign.opacityMedium)),
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
    final isScrapped = item.scrapped;
    final tall = item.spanHours > 1;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isScrapped ? 0.35 : 1.0,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: isScrapped ? 0.06 : 0.18),
            borderRadius: AppDesign.borderRadiusSm,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: isScrapped
                        ? item.color.withValues(alpha: 0.3)
                        : item.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppDesign.spacingSm,
                  vertical: tall ? AppDesign.spacingSm : AppDesign.spacingXs,
                ),
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: item.color,
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
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: tall ? 13 : 11,
                    fontWeight: FontWeight.w600,
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
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.7),
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
                    fontSize: ResponsiveService.clampedFontSize(context, 9),
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
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

  const _AddEventDialog({
    required this.professorService,
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

  DayOfWeek _selectedDay = DayOfWeek.M;
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
      _profResults = all
          .where((p) => p.name.toLowerCase().contains(q))
          .take(8)
          .toList();
    });
  }

  List<ProfessorScheduleEntry> _profScheduleForDay(
      Professor prof, DayOfWeek day) {
    final dayStr = 'DayOfWeek.${day.name}';
    return prof.schedule
        .where((s) => s.days.contains(dayStr))
        .toList();
  }

  String? _clashReason() {
    final startSlot = _timeToSlotHour(_startTime);
    final span = _slotSpanFromTimes(_startTime, _endTime);
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
      final profEntries = _profScheduleForDay(_selectedProfessor!, _selectedDay);
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
                      icon: Icon(Icons.event)),
                  ButtonSegment(
                      value: 'prof_meeting',
                      label: Text('Prof Meeting'),
                      icon: Icon(Icons.person)),
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
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.3)),
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
                          subtitle: Text('Chamber: ${prof.chamber}',
                              style: const TextStyle(fontSize: 11)),
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
                decoration: const InputDecoration(
                  labelText: 'Event title',
                ),
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
                items: DayOfWeek.values.map((d) {
                  const labels = {
                    DayOfWeek.M: 'Monday',
                    DayOfWeek.T: 'Tuesday',
                    DayOfWeek.W: 'Wednesday',
                    DayOfWeek.Th: 'Thursday',
                    DayOfWeek.F: 'Friday',
                    DayOfWeek.S: 'Saturday',
                  };
                  return DropdownMenuItem(
                      value: d, child: Text(labels[d] ?? d.name));
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
                                  hour: picked.hour + 1, minute: picked.minute);
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
                  style: TextStyle(fontSize: 12, color: AppDesign.danger(context)),
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
                        color: AppDesign.warning(context).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: AppDesign.warning(context), size: 18),
                      const SizedBox(width: AppDesign.spacingSm),
                      Expanded(
                        child: Text(
                          clashMsg,
                          style: TextStyle(fontSize: 12, color: AppDesign.warning(context)),
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
          onPressed: _titleController.text.trim().isEmpty ||
                  (_endTime.hour * 60 + _endTime.minute <=
                      _startTime.hour * 60 + _startTime.minute)
              ? null
              : () {
                  final startSlot = _timeToSlotHour(_startTime);
                  final span = _slotSpanFromTimes(_startTime, _endTime);
                  final event = CalendarEvent(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: _titleController.text.trim(),
                    description: _descController.text.trim().isNotEmpty
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
            Icon(Icons.check_circle, color: AppDesign.success(context), size: 18),
            const SizedBox(width: AppDesign.spacingSm),
            Text(
              '${prof.name} has no classes on ${_dayFullName(_selectedDay)}',
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
            '${prof.name}\'s classes on ${_dayFullName(_selectedDay)}:',
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...dayEntries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${entry.courseCode} (${entry.sectionId}) — ${entry.hourRangeString}',
                  style: theme.textTheme.bodySmall,
                ),
              )),
        ],
      ),
    );
  }
}

// --- Models ---

enum _PeriodType { classes, midsem, endsem, beforeSemester, afterSemester }

enum _ItemType { classSlot, exam, announcement, customEvent }

class _CalendarItem {
  final _ItemType type;
  final String title;
  final String subtitle;
  final int hour;
  final int spanHours;
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
    required this.color,
    this.instructor,
    this.examDate,
    this.examRoom,
    this.announcement,
    required this.slotKey,
    this.scrapped = false,
    this.event,
  });
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
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
        ),
        child: Text('$h:$m $p', style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/data/exam_seating_service.dart';
import '../widgets/common/empty_state_widget.dart';
import '../widgets/common/shimmer_loading.dart';
import '../services/core/timetable_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../services/ui/page_leave_warning_service.dart';
import '../services/data/profile_service.dart';
import '../models/timetable.dart';
import '../utils/design_constants.dart';
import '../widgets/command_palette.dart';
import '../widgets/app_destinations.dart';
import '../services/ui/tutorial_service.dart';
import '../utils/page_info_helper.dart';

/// Whether an exam-seating entry covers [courseCode].
///
/// Combined exams are stored under one hyphen-joined code: the official seating
/// sheet writes "CS F211/MAC F242" and the parser turns the slash into a dash
/// for the document id (the code lives only in the id), so the client sees
/// "CS F211-MAC F242". A timetable course therefore matches when its code equals
/// the whole entry *or* any of the hyphen-separated parts — otherwise a student
/// in only one of a combined pair could never import their seating.
bool examCoversCourse(String examCourseCode, String courseCode) {
  String norm(String s) => s.replaceAll(' ', '').toUpperCase();
  final target = norm(courseCode);
  if (target.isEmpty) return false;
  final exam = norm(examCourseCode);
  return exam == target || exam.split('-').any((part) => part == target);
}

/// Course code as it should read to a human. A combined exam is *stored* with a
/// hyphen — the parser turns the seating sheet's slash into a dash for the
/// document id — so restore the slash for display only:
/// "CS F211-MAC F242" → "CS F211 / MAC F242". The stored value keeps its dash,
/// so identity and [examCoversCourse] matching are unaffected.
String displayExamCode(String code) => code.replaceAll('-', ' / ');

class ExamSeatingScreen extends StatefulWidget {
  const ExamSeatingScreen({super.key});

  @override
  State<ExamSeatingScreen> createState() => _ExamSeatingScreenState();
}

class _ExamSeatingScreenState extends State<ExamSeatingScreen> {
  final ExamSeatingService _examSeatingService = ExamSeatingService();
  final TimetableService _timetableService = TimetableService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _idController = TextEditingController();

  List<ExamSeating> _allExams = [];
  final List<ExamSeating> _selectedCourses = [];
  Map<String, ExamRoom?> _searchResults = {};
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExamData();
    CommandPaletteActions.register(DrawerScreen.examSeating, () => [
      CommandPaletteEntry(
        label: 'Import from Timetable',
        subtitle: 'Load exam courses from a saved timetable',
        icon: Icons.file_download,
        category: CommandCategory.context,
        onSelect: _importCoursesFromTimetable,
      ),
      CommandPaletteEntry(
        label: 'Search Room',
        subtitle: 'Find your seat by ID number',
        icon: Icons.search,
        category: CommandCategory.context,
        onSelect: _searchForRoom,
      ),
    ]);
  }

  @override
  void dispose() {
    CommandPaletteActions.unregister(DrawerScreen.examSeating);
    PageLeaveWarningService().clear('examSeating');
    _searchController.dispose();
    _idController.dispose();
    super.dispose();
  }

  /// Selected courses and the ID are only persisted via the Save button, so
  /// flag them for the web unload prompt as soon as they diverge from what was
  /// last loaded/saved.
  void _markDirty() =>
      PageLeaveWarningService().setUnsaved('examSeating', true);

  void _onIdChanged() => _markDirty();

  Future<void> _loadExamData() async {
    setState(() => _isLoading = true);
    final exams = await _examSeatingService.fetchAllExamSeating();

    // Load saved user data + profile defaults
    final savedData = await _examSeatingService.loadUserData();
    final profile = await ProfileService().load();

    setState(() {
      _allExams = exams;
      _isLoading = false;

      // Restore saved courses and student ID
      if (savedData != null) {
        _idController.text = savedData.studentId;

        // Find matching exams for saved course codes
        for (final courseCode in savedData.selectedCourseCodes) {
          final exam = exams.firstWhere(
            (e) => examCoversCourse(e.courseCode, courseCode),
            orElse: () => ExamSeating(
              courseCode: courseCode,
              courseTitle: '',
              examDate: '',
              rooms: [],
            ),
          );
          if (exam.rooms.isNotEmpty &&
              !_selectedCourses.any((c) => c.courseCode == exam.courseCode)) {
            _selectedCourses.add(exam);
          }
        }
      }

      // Fall back to the profile's default ID when nothing was saved.
      if (_idController.text.trim().isEmpty && profile.studentId.isNotEmpty) {
        _idController.text = profile.studentId;
      }
    });

    // Attach only after restoring saved state so the initial fill doesn't
    // register as an unsaved edit.
    if (!mounted) return;
    _idController.addListener(_onIdChanged);
  }

  Future<void> _importCoursesFromTimetable() async {
    try {
      final allTimetables = await _timetableService.getAllTimetables();

      if (allTimetables.isEmpty) {
        ToastService.showError(
          'No timetables found. Please create a timetable first.',
        );
        return;
      }

      if (!mounted) return;

      final selectedCourses = await showDialog<List<String>>(
        context: context,
        builder: (context) => _TimetableCourseSelectionDialog(
          timetables: allTimetables,
          allExams: _allExams,
        ),
      );

      if (selectedCourses == null || selectedCourses.isEmpty) {
        return;
      }

      // Find exam seating data for selected courses
      final coursesToAdd = <ExamSeating>[];
      for (final courseCode in selectedCourses) {
        final exam = _allExams.firstWhere(
          (e) => examCoversCourse(e.courseCode, courseCode),
          orElse: () => ExamSeating(
            courseCode: courseCode,
            courseTitle: '',
            examDate: '',
            rooms: [],
          ),
        );
        if (exam.rooms.isNotEmpty &&
            !_selectedCourses.any((c) => c.courseCode == exam.courseCode)) {
          coursesToAdd.add(exam);
        }
      }

      if (coursesToAdd.isEmpty) {
        ToastService.showInfo(
          'No exam seating data found for the selected courses.',
        );
        return;
      }

      setState(() {
        _selectedCourses.addAll(coursesToAdd);
      });
      _markDirty();

      ToastService.showSuccess(
        'Added ${coursesToAdd.length} course${coursesToAdd.length != 1 ? 's' : ''}!',
      );
    } catch (e) {
      ToastService.showError('Error importing courses: $e');
    }
  }

  void _addCourse(ExamSeating exam) {
    if (_selectedCourses.any((c) => c.courseCode == exam.courseCode)) {
      ToastService.showInfo('Course already added');
      return;
    }

    setState(() {
      _selectedCourses.add(exam);
      _searchController.clear();
    });
    _markDirty();
  }

  void _removeCourse(ExamSeating exam) {
    setState(() {
      _selectedCourses.removeWhere((c) => c.courseCode == exam.courseCode);
      _searchResults.remove(exam.courseCode);
    });
    _markDirty();
  }

  void _searchForRoom() {
    final studentId = _idController.text.trim();
    if (studentId.isEmpty) {
      ToastService.showError('Please enter your ID number');
      return;
    }

    if (_selectedCourses.isEmpty) {
      ToastService.showError('Please add at least one course');
      return;
    }

    setState(() => _isSearching = true);

    final results = <String, ExamRoom?>{};
    for (final course in _selectedCourses) {
      results[course.courseCode] = course.findRoomForStudent(studentId);
    }

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _saveUserData() async {
    if (_selectedCourses.isEmpty && _idController.text.trim().isEmpty) {
      ToastService.showInfo('Nothing to save');
      return;
    }

    setState(() => _isSaving = true);

    final success = await _examSeatingService.saveUserData(
      selectedCourseCodes: _selectedCourses.map((c) => c.courseCode).toList(),
      studentId: _idController.text.trim(),
    );

    setState(() => _isSaving = false);

    if (success) {
      PageLeaveWarningService().clear('examSeating');
      ToastService.showSuccess('Saved successfully!');
    } else {
      ToastService.showError('Please sign in to save your data');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Exam Seating'),
        body: const CourseListSkeleton(),
      );
    }

    final isMobile = ResponsiveService.isMobile(context);
    final saveButton = IconButton(
      icon: _isSaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined),
      tooltip: 'Save',
      onPressed: _isSaving ? null : _saveUserData,
    );

    return Scaffold(
      appBar: AppDesign.appBar(
        context,
        title: 'Exam Seating',
        // On mobile keep Save visible and tuck the rest into a ⋮ menu so the
        // bar isn't four icons wide next to the title.
        actions: isMobile
            ? [
                saveButton,
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More',
                  onSelected: (value) {
                    switch (value) {
                      case 'import':
                        _importCoursesFromTimetable();
                        break;
                      case 'reload':
                        _loadExamData();
                        break;
                      case 'info':
                        PageInfoHelper.show(context, PageInfoHelper.examSeating);
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'import',
                      child: ListTile(
                        leading: Icon(Icons.file_download_outlined),
                        title: Text('Import from Timetable'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'reload',
                      child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('Reload Data'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'info',
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('About This Page'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ]
            : [
                PageInfoHelper.infoButton(context, PageInfoHelper.examSeating, key: TutorialKeys.infoExamSeating),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: 'Import Courses from Timetable',
                  onPressed: _importCoursesFromTimetable,
                ),
                saveButton,
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload Data',
                  onPressed: _loadExamData,
                ),
              ],
      ),
      body: Column(
        children: [
          _buildSearchSection(),
          Expanded(child: _buildSelectedCourses()),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Container(
      padding: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Course search
          TypeAheadField<ExamSeating>(
            controller: _searchController,
            suggestionsCallback: (pattern) async {
              if (pattern.isEmpty) return [];
              return _allExams
                  .where((exam) =>
                      exam.courseCode
                          .toUpperCase()
                          .contains(pattern.toUpperCase()) ||
                      exam.courseTitle
                          .toUpperCase()
                          .contains(pattern.toUpperCase()))
                  .take(10)
                  .toList();
            },
            builder: (context, controller, focusNode) {
              return Semantics(
                label: 'Search Exam Seating',
                textField: true,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    hintText: 'Search for a course...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              );
            },
            itemBuilder: (context, exam) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(displayExamCode(exam.courseCode), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  exam.courseTitle.isNotEmpty
                      ? exam.courseTitle
                      : 'No title available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                trailing: exam.examDate.isNotEmpty
                    ? Text(
                        exam.examDate,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                      )
                    : null,
              );
            },
            onSelected: _addCourse,
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No courses found'),
            ),
          ),

          const SizedBox(height: 16),

          // ID Number input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    hintText: 'Enter your ID Number (e.g., 2022A7PS0001H)',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _searchForRoom(),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                label: 'Find Room',
                button: true,
                child: FilledButton.icon(
                  onPressed: _isSearching ? null : _searchForRoom,
                  icon: _isSearching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Find Room'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compare two exam date strings for sorting
  /// Expected format: "DD/MM/YYYY AN/FN" or similar
  int _compareExamDates(String dateA, String dateB) {
    if (dateA.isEmpty && dateB.isEmpty) return 0;
    if (dateA.isEmpty) return 1; // Empty dates go to end
    if (dateB.isEmpty) return -1;

    try {
      // Parse date and time from strings like "03/12/2024 AN" or "03/12/2024 FN"
      final parsedA = _parseExamDateTime(dateA);
      final parsedB = _parseExamDateTime(dateB);

      if (parsedA == null && parsedB == null) return dateA.compareTo(dateB);
      if (parsedA == null) return 1;
      if (parsedB == null) return -1;

      return parsedA.compareTo(parsedB);
    } catch (e) {
      // Fallback to string comparison
      return dateA.compareTo(dateB);
    }
  }

  /// Parse exam date string to DateTime for comparison
  /// Handles formats like:
  /// - "03/12/2024 AN", "03/12/2024 FN", "3/12/2024"
  /// - "09 March 26 - 04:00 PM to 05:30 PM"
  /// - "09 March 26 - 09:30 AM to 11:00 AM"
  DateTime? _parseExamDateTime(String dateStr) {
    try {
      final normalized = dateStr.trim();

      // Try format: "DD Month YY - HH:MM AM/PM to HH:MM AM/PM"
      // Example: "09 March 26 - 04:00 PM to 05:30 PM"
      final monthNames = {
        'JANUARY': 1, 'JAN': 1,
        'FEBRUARY': 2, 'FEB': 2,
        'MARCH': 3, 'MAR': 3,
        'APRIL': 4, 'APR': 4,
        'MAY': 5,
        'JUNE': 6, 'JUN': 6,
        'JULY': 7, 'JUL': 7,
        'AUGUST': 8, 'AUG': 8,
        'SEPTEMBER': 9, 'SEP': 9,
        'OCTOBER': 10, 'OCT': 10,
        'NOVEMBER': 11, 'NOV': 11,
        'DECEMBER': 12, 'DEC': 12,
      };

      // Pattern: DD Month YY - HH:MM AM/PM
      final newFormatRegex = RegExp(
        r'(\d{1,2})\s+(\w+)\s+(\d{2,4})\s*-\s*(\d{1,2}):(\d{2})\s*(AM|PM)',
        caseSensitive: false,
      );
      final newMatch = newFormatRegex.firstMatch(normalized);
      if (newMatch != null) {
        final day = int.tryParse(newMatch.group(1)!);
        final monthStr = newMatch.group(2)!.toUpperCase();
        var year = int.tryParse(newMatch.group(3)!);
        var hour = int.tryParse(newMatch.group(4)!);
        final minute = int.tryParse(newMatch.group(5)!);
        final ampm = newMatch.group(6)!.toUpperCase();
        final month = monthNames[monthStr];

        if (day != null && month != null && year != null && hour != null && minute != null) {
          // Handle 2-digit year
          if (year < 100) {
            year += 2000;
          }
          // Convert to 24-hour format
          if (ampm == 'PM' && hour != 12) {
            hour += 12;
          } else if (ampm == 'AM' && hour == 12) {
            hour = 0;
          }
          return DateTime(year, month, day, hour, minute);
        }
      }

      // Fallback: Try DD/MM/YYYY AN/FN format
      final upperNormalized = normalized.toUpperCase();
      final isAfternoon = upperNormalized.contains('FN');

      // Extract date part (remove AN/FN)
      final datePart = upperNormalized
          .replaceAll('AN', '')
          .replaceAll('FN', '')
          .replaceAll('(', '')
          .replaceAll(')', '')
          .trim();

      // Try DD/MM/YYYY format
      final parts = datePart.split('/');
      if (parts.length >= 3) {
        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);

        if (day != null && month != null && year != null) {
          // AN = 9:00 AM, FN = 2:00 PM
          final hour = isAfternoon ? 14 : 9;
          return DateTime(year, month, day, hour);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static const _monthAbbr = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "24 Nov" from a parseable exam date, else null.
  String? _examDayLabel(String raw) {
    final dt = _parseExamDateTime(raw);
    if (dt == null) return null;
    return '${dt.day} ${_monthAbbr[dt.month]}';
  }

  /// The session token — AN/FN, or a start time like "9:30 AM" — else null.
  String? _sessionLabel(String raw) {
    final u = raw.toUpperCase();
    if (RegExp(r'\bAN\b').hasMatch(u)) return 'AN';
    if (RegExp(r'\bFN\b').hasMatch(u)) return 'FN';
    final t = RegExp(r'\d{1,2}:\d{2}\s*(AM|PM)', caseSensitive: false)
        .firstMatch(raw);
    return t?.group(0)?.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  }

  /// Days-until label; null once the exam is in the past or unparseable.
  ({String text, bool urgent})? _countdown(String raw) {
    final dt = _parseExamDateTime(raw);
    if (dt == null) return null;
    final now = DateTime.now();
    final days = DateTime(dt.year, dt.month, dt.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) return null;
    if (days == 0) return (text: 'today', urgent: true);
    if (days == 1) return (text: 'tomorrow', urgent: true);
    return (text: 'in $days days', urgent: days <= 3);
  }

  /// A small rounded pill used for the date / session / countdown metadata.
  Widget _metaChip(IconData? icon, String label, {Color? fg, Color? bg}) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = fg ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  /// The room-lookup result strip (found / not-found), tinted by [color].
  Widget _resultBox({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color.withValues(alpha: 0.9),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedCourses() {
    if (_selectedCourses.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.event_seat_outlined,
        title: 'No courses selected',
        subtitle: 'Search for a course above or import from your timetable',
      );
    }

    // Sort courses by exam date
    final sortedCourses = List<ExamSeating>.from(_selectedCourses)
      ..sort((a, b) => _compareExamDates(a.examDate, b.examDate));

    return RefreshIndicator(
      onRefresh: _loadExamData,
      child: ListView.builder(
      scrollCacheExtent: ScrollCacheExtent.pixels(800),
      padding: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      itemCount: sortedCourses.length,
      itemBuilder: (context, index) {
        final course = sortedCourses[index];
        final room = _searchResults[course.courseCode];
        final hasSearched = _searchResults.containsKey(course.courseCode);

        final scheme = Theme.of(context).colorScheme;
        final dayLabel = _examDayLabel(course.examDate);
        final session = _sessionLabel(course.examDate);
        final countdown = _countdown(course.examDate);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayExamCode(course.courseCode),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (course.courseTitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                course.courseTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Subtle, compact remove affordance.
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: scheme.onSurfaceVariant,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeCourse(course),
                      tooltip: 'Remove course',
                    ),
                  ],
                ),

                // Date / session / countdown chips (fall back to the raw string
                // when the date can't be parsed into a day + session).
                if (dayLabel != null || session != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (dayLabel != null)
                        _metaChip(Icons.calendar_today_outlined, dayLabel),
                      if (session != null)
                        _metaChip(
                          null,
                          session,
                          fg: scheme.onPrimaryContainer,
                          bg: scheme.primaryContainer,
                        ),
                      if (countdown != null)
                        _metaChip(
                          Icons.schedule,
                          countdown.text,
                          fg: countdown.urgent
                              ? AppDesign.warning(context)
                              : scheme.onSurfaceVariant,
                          bg: countdown.urgent
                              ? AppDesign.warning(context).withValues(alpha: 0.12)
                              : scheme.surfaceContainerHighest,
                        ),
                    ],
                  ),
                ] else if (course.examDate.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _metaChip(Icons.event, course.examDate),
                ],

                // Room result once the user has searched their ID.
                if (hasSearched) ...[
                  const SizedBox(height: 14),
                  if (room != null)
                    _resultBox(
                      icon: Icons.check_circle,
                      color: AppDesign.success(context),
                      title: 'Room ${room.roomNo}',
                      subtitle: 'Seats ${room.idFrom} – ${room.idTo}',
                    )
                  else
                    _resultBox(
                      icon: Icons.warning_amber_rounded,
                      color: AppDesign.warning(context),
                      title: 'No room found',
                      subtitle: 'Your ID isn\'t in this course\'s seating list',
                    ),
                ],
              ],
            ),
          ),
        );
      },
    ),
    );
  }
}

/// Dialog for selecting courses from timetables
class _TimetableCourseSelectionDialog extends StatefulWidget {
  final List<Timetable> timetables;
  final List<ExamSeating> allExams;

  const _TimetableCourseSelectionDialog({
    required this.timetables,
    required this.allExams,
  });

  @override
  State<_TimetableCourseSelectionDialog> createState() =>
      _TimetableCourseSelectionDialogState();
}

class _TimetableCourseSelectionDialogState
    extends State<_TimetableCourseSelectionDialog> {
  Timetable? _selectedTimetable;
  final Set<String> _selectedCourses = {};

  @override
  void initState() {
    super.initState();
    if (widget.timetables.isNotEmpty) {
      _selectedTimetable = widget.timetables.first;
    }
  }

  List<String> get _availableCourses {
    if (_selectedTimetable == null) return [];

    // Get unique course codes from selectedSections (courses actually in the timetable)
    final courseCodes = <String>{};
    for (final selectedSection in _selectedTimetable!.selectedSections) {
      courseCodes.add(selectedSection.courseCode);
    }

    // Filter to only courses that have exam seating data
    return courseCodes.where((code) {
      return widget.allExams.any((exam) => examCoversCourse(exam.courseCode, code));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Courses'),
      content: SizedBox(
        width: ResponsiveService.isMobile(context) ? MediaQuery.sizeOf(context).width * 0.85 : 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timetable selector
            DropdownButtonFormField<Timetable>(
              initialValue: _selectedTimetable,
              decoration: const InputDecoration(
                labelText: 'Select Timetable',
              ),
              items: widget.timetables
                  .map((tt) => DropdownMenuItem(
                        value: tt,
                        child: Text(tt.name),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTimetable = value;
                  _selectedCourses.clear();
                });
              },
            ),
            const SizedBox(height: 16),

            // Course list
            if (_availableCourses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No courses with exam seating data found in this timetable.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableCourses.length,
                  itemBuilder: (context, index) {
                    final courseCode = _availableCourses[index];
                    final isSelected = _selectedCourses.contains(courseCode);

                    return CheckboxListTile(
                      title: Text(courseCode),
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
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedCourses.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedCourses.toList()),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

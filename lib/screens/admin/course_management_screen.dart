import 'package:flutter/material.dart';
import '../../services/ui/secure_logger.dart';
import '../../utils/debouncer.dart';
import '../../models/course.dart';
import '../../services/data/admin_data_service.dart';
import '../../services/data/admin_service.dart';
import '../../services/data/campus_service.dart';
import '../../services/data/professor_service.dart';
import '../../services/ui/toast_service.dart';
import '../../constants/app_constants.dart';
import '../../utils/design_constants.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/app_search_field.dart';

class CourseManagementScreen extends StatefulWidget {
  const CourseManagementScreen({super.key});

  @override
  State<CourseManagementScreen> createState() => _CourseManagementScreenState();
}

Widget _badge(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

class _CourseManagementScreenState extends State<CourseManagementScreen> {
  static const _campusIds = CampusConstants.ids;
  static const _campusLabels = CampusConstants.labels;

  final _crud = AdminDataService();
  final _searchController = TextEditingController();
  final _debounce = Debouncer(duration: const Duration(milliseconds: 400));
  List<Map<String, dynamic>> _courses = [];
  bool _loading = true;
  List<String> _professorNames = [];
  String _campusId = CampusService.campusId;

  @override
  void initState() {
    super.initState();
    // Force one fresh read per screen visit; the debounced search
    // keystrokes afterwards are served from the cached rows.
    _loadCourses(force: true);
    _loadProfessorNames();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce.dispose();
    super.dispose();
  }

  void _switchCampus() {
    final idx = (_campusIds.indexOf(_campusId) + 1) % _campusIds.length;
    setState(() => _campusId = _campusIds[idx]);
    _loadCourses();
  }

  Future<void> _loadCourses({bool force = false}) async {
    setState(() => _loading = true);
    try {
      final q = _searchController.text.trim();
      _courses = await _crud.fetchCourses(_campusId,
          query: q.isEmpty ? null : q, forceRefresh: force);
    } catch (e) {
      ToastService.showError('Failed to load courses');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadProfessorNames() async {
    try {
      final profService = ProfessorService();
      await profService.loadProfessors();
      _professorNames =
          profService.professors.map((p) => p.name).toSet().toList()..sort();
    } catch (e) {
      SecureLogger.warning('COURSE_ADMIN', 'Failed to load professor names', {'error': e.toString()});
    }
  }

  void _onSearchChanged(String _) {
    _debounce.run(_loadCourses);
  }

  String _docId(String courseCode) =>
      courseCode.trim().replaceAll(RegExp(r'\s+'), '_');

  static const _dayLabels = DayConstants.singleChar;
  static const _dayValues = [
    'DayOfWeek.M', 'DayOfWeek.T', 'DayOfWeek.W',
    'DayOfWeek.Th', 'DayOfWeek.F', 'DayOfWeek.S',
  ];
  static const _hourLabels = ScheduleConstants.hourLabels;

  Widget _scheduleEditor(
      Map<String, dynamic> section, StateSetter setDialogState) {
    final schedule = (section['schedule'] as List?) ?? [];
    section['schedule'] = schedule;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Schedule',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppDesign.muted(context))),
              const Spacer(),
              InkWell(
                onTap: () => setDialogState(() => schedule.add({
                      'days': <String>[],
                      'hours': <int>[],
                    })),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 14, color: scheme.primary),
                      const SizedBox(width: 2),
                      Text('Add',
                          style:
                              TextStyle(fontSize: 11, color: scheme.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          for (var ei = 0; ei < schedule.length; ei++)
            _scheduleEntryRow(schedule, ei, setDialogState),
        ],
      ),
    );
  }

  Widget _scheduleEntryRow(
      List<dynamic> schedule, int ei, StateSetter setDialogState) {
    final entry = schedule[ei] as Map<String, dynamic>;
    final days = List<String>.from(entry['days'] ?? []);
    final hours = List<int>.from((entry['hours'] ?? []).map((h) => h is int ? h : int.tryParse(h.toString()) ?? 0));
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var di = 0; di < _dayLabels.length; di++)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setDialogState(() {
                      final dv = _dayValues[di];
                      if (days.contains(dv)) {
                        days.remove(dv);
                      } else {
                        days.add(dv);
                      }
                      entry['days'] = days;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: days.contains(_dayValues[di])
                            ? scheme.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: days.contains(_dayValues[di])
                              ? scheme.primary.withValues(alpha: 0.5)
                              : scheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        _dayLabels[di],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: days.contains(_dayValues[di])
                              ? scheme.primary
                              : AppDesign.muted(context),
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              InkWell(
                onTap: () =>
                    setDialogState(() => schedule.removeAt(ei)),
                child: Icon(Icons.close_rounded,
                    size: 14, color: scheme.error.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: [
              for (final h in _hourLabels.keys)
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => setDialogState(() {
                    if (hours.contains(h)) {
                      hours.remove(h);
                    } else {
                      hours.add(h);
                      hours.sort();
                    }
                    entry['hours'] = hours;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: hours.contains(h)
                          ? scheme.secondary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: hours.contains(h)
                            ? scheme.secondary.withValues(alpha: 0.5)
                            : scheme.outline.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Text(
                      _hourLabels[h]!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: hours.contains(h)
                            ? scheme.secondary
                            : AppDesign.muted(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCourseDialog({Map<String, dynamic>? existing}) async {
    final isNew = existing == null;
    final codeCtrl = TextEditingController(
        text: existing?['course_code']?.toString() ?? '');
    final titleCtrl =
        TextEditingController(text: existing?['title']?.toString() ?? '');
    final icCtrl = TextEditingController(
        text: existing?['instructor_in_charge']?.toString() ?? '');
    final lecCtrl = TextEditingController(
        text: (existing?['lecture_credits'] ?? 0).toString());
    final pracCtrl = TextEditingController(
        text: (existing?['practical_credits'] ?? 0).toString());
    final totalCtrl = TextEditingController(
        text: (existing?['credits'] ?? ((existing?['lecture_credits'] ?? 0) + (existing?['practical_credits'] ?? 0))).toString());

    final sections = <Map<String, dynamic>>[];
    if (existing != null && existing['sections'] is List) {
      for (final s in existing['sections'] as List) {
        sections.add(Map<String, dynamic>.from(s as Map));
      }
    }

    ExamSchedule? midSem;
    ExamSchedule? endSem;
    if (existing?['mid_sem_exam'] != null) {
      try {
        midSem = ExamSchedule.fromJson(
            Map<String, dynamic>.from(existing!['mid_sem_exam'] as Map));
      } catch (e) {
        SecureLogger.warning('COURSE_ADMIN', 'Failed to parse stored mid-sem exam', {'error': e.toString()});
      }
    }
    if (existing?['end_sem_exam'] != null) {
      try {
        endSem = ExamSchedule.fromJson(
            Map<String, dynamic>.from(existing!['end_sem_exam'] as Map));
      } catch (e) {
        SecureLogger.warning('COURSE_ADMIN', 'Failed to parse stored end-sem exam', {'error': e.toString()});
      }
    }

    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          final accent = scheme.primary;

          Widget field(String label, TextEditingController ctrl,
              {bool readOnly = false,
              TextInputType? keyboardType,
              List<String>? autocompleteOptions,
              ValueChanged<String>? onChanged}) {
            if (autocompleteOptions != null && autocompleteOptions.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
                child: Autocomplete<String>(
                  initialValue: ctrl.value,
                  optionsBuilder: (v) {
                    if (v.text.isEmpty) return const [];
                    final q = v.text.toLowerCase();
                    return autocompleteOptions
                        .where((n) => n.toLowerCase().contains(q))
                        .take(5);
                  },
                  onSelected: (v) => ctrl.text = v,
                  fieldViewBuilder: (_, textCtrl, focusNode, onSubmit) {
                    textCtrl.text = ctrl.text;
                    textCtrl.addListener(() => ctrl.text = textCtrl.text);
                    return TextField(
                      controller: textCtrl,
                      focusNode: focusNode,
                      style: const TextStyle(fontSize: 13),
                      decoration: AppDesign.inputDecoration(ctx,
                          label: label, hint: label),
                    );
                  },
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
              child: TextField(
                controller: ctrl,
                readOnly: readOnly,
                keyboardType: keyboardType,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 13),
                decoration:
                    AppDesign.inputDecoration(ctx, label: label, hint: label),
              ),
            );
          }

          Widget examPicker(String label, ExamSchedule? exam,
              ValueChanged<ExamSchedule?> onChanged, bool isMidSem) {
            final slots =
                isMidSem ? [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4] : [TimeSlot.FN, TimeSlot.AN];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      const Spacer(),
                      if (exam != null)
                        IconButton(
                          icon: Icon(Icons.clear_rounded,
                              size: 16, color: scheme.error),
                          onPressed: () =>
                              setDialogState(() => onChanged(null)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: exam?.date ?? DateTime.now(),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setDialogState(() => onChanged(ExamSchedule(
                                  date: picked,
                                  timeSlot:
                                      exam?.timeSlot ?? slots.first)));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: AppDesign.borderRadiusSm,
                              border: Border.all(
                                  color:
                                      scheme.outline.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              exam != null
                                  ? '${exam.date.day}/${exam.date.month}/${exam.date.year}'
                                  : 'Pick date',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: exam != null
                                      ? scheme.onSurface
                                      : scheme.onSurface
                                          .withValues(alpha: 0.38)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<TimeSlot>(
                        value: exam?.timeSlot ?? slots.first,
                        underline: const SizedBox(),
                        style:
                            TextStyle(fontSize: 13, color: scheme.onSurface),
                        items: slots
                            .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                    '${s.name} (${TimeSlotInfo.getTimeSlotName(s, campus: _campusId)})',
                                    style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: exam == null
                            ? null
                            : (v) {
                                if (v != null) {
                                  setDialogState(() => onChanged(
                                      ExamSchedule(
                                          date: exam.date, timeSlot: v)));
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          Widget sectionCard(int idx) {
            final s = sections[idx];
            final idCtrl =
                TextEditingController(text: s['sectionId']?.toString() ?? '');
            final instrCtrl =
                TextEditingController(text: s['instructor']?.toString() ?? '');
            final roomCtrl =
                TextEditingController(text: s['room']?.toString() ?? '');
            final typeStr = s['type']?.toString() ?? 'SectionType.L';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: AppDesign.borderRadiusSm,
                border: Border(
                  left: BorderSide(
                    color: typeStr.contains('.P')
                        ? AppDesign.success(ctx)
                        : typeStr.contains('.T')
                            ? AppDesign.warning(ctx)
                            : AppDesign.info(ctx),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: idCtrl,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                              hintText: 'L1',
                              isDense: true,
                              border: InputBorder.none),
                          onChanged: (v) => s['sectionId'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: typeStr,
                        underline: const SizedBox(),
                        style:
                            TextStyle(fontSize: 12, color: scheme.onSurface),
                        items: const [
                          DropdownMenuItem(
                              value: 'SectionType.L', child: Text('Lecture')),
                          DropdownMenuItem(
                              value: 'SectionType.P',
                              child: Text('Practical')),
                          DropdownMenuItem(
                              value: 'SectionType.T',
                              child: Text('Tutorial')),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => s['type'] = v),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: scheme.error),
                        onPressed: () =>
                            setDialogState(() => sections.removeAt(idx)),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Autocomplete<String>(
                    initialValue: instrCtrl.value,
                    optionsBuilder: (v) {
                      if (v.text.isEmpty) return const [];
                      final q = v.text.toLowerCase();
                      return _professorNames
                          .where((n) => n.toLowerCase().contains(q))
                          .take(5);
                    },
                    onSelected: (v) {
                      instrCtrl.text = v;
                      s['instructor'] = v;
                    },
                    fieldViewBuilder: (_, tc, fn, __) {
                      tc.text = instrCtrl.text;
                      tc.addListener(() {
                        instrCtrl.text = tc.text;
                        s['instructor'] = tc.text;
                      });
                      return TextField(
                        controller: tc,
                        focusNode: fn,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Instructor',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: roomCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Room',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => s['room'] = v,
                  ),
                  _scheduleEditor(s, setDialogState),
                ],
              ),
            );
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            isNew
                                ? Icons.add_rounded
                                : Icons.edit_rounded,
                            color: accent),
                        const SizedBox(width: 10),
                        Text(isNew ? 'Add Course' : 'Edit Course',
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          field('Course Code', codeCtrl, readOnly: !isNew),
                          field('Course Title', titleCtrl),
                          field('Instructor-in-Charge', icCtrl,
                              autocompleteOptions: _professorNames),
                          Row(
                            children: [
                              Expanded(
                                  child: field('L', lecCtrl,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) {
                                        final l = int.tryParse(lecCtrl.text) ?? 0;
                                        final p = int.tryParse(pracCtrl.text) ?? 0;
                                        totalCtrl.text = '${l + p}';
                                      })),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: field('P', pracCtrl,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) {
                                        final l = int.tryParse(lecCtrl.text) ?? 0;
                                        final p = int.tryParse(pracCtrl.text) ?? 0;
                                        totalCtrl.text = '${l + p}';
                                      })),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: field('Total', totalCtrl,
                                      keyboardType: TextInputType.number)),
                            ],
                          ),
                          examPicker('Mid-Sem Exam', midSem, (v) {
                            midSem = v;
                          }, true),
                          examPicker('End-Sem Exam', endSem, (v) {
                            endSem = v;
                          }, false),
                          const Divider(),
                          Row(
                            children: [
                              Text('Sections',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface)),
                              const Spacer(),
                              TextButton.icon(
                                icon: Icon(Icons.add_rounded,
                                    size: 16, color: accent),
                                label: Text('Add',
                                    style: TextStyle(
                                        fontSize: 12, color: accent)),
                                onPressed: () => setDialogState(() =>
                                    sections.add({
                                      'sectionId': '',
                                      'type': 'SectionType.L',
                                      'instructor': '',
                                      'room': '',
                                      'schedule': [],
                                    })),
                              ),
                            ],
                          ),
                          for (var i = 0; i < sections.length; i++)
                            sectionCard(i),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (!isNew)
                          AppButton(
                            label: 'Delete',
                            icon: Icons.delete_outline_rounded,
                            variant: AppButtonVariant.danger,
                            onTap: saving
                                ? null
                                : () async {
                                    final confirm = await AppDialog.confirm(
                                      context: ctx,
                                      title: 'Delete Course',
                                      message:
                                          'Delete ${codeCtrl.text}? This cannot be undone.',
                                      isDangerous: true,
                                    );
                                    if (confirm && ctx.mounted) {
                                      try {
                                        await _crud.deleteCourse(
                                            _campusId, existing['docId']);
                                        ToastService.showSuccess(
                                            'Course deleted');
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        _loadCourses();
                                      } catch (e) {
                                        ToastService.showError(
                                            'Delete failed');
                                      }
                                    }
                                  },
                          ),
                        const Spacer(),
                        AppButton(
                          label: 'Cancel',
                          variant: AppButtonVariant.ghost,
                          onTap:
                              saving ? null : () => Navigator.pop(ctx),
                        ),
                        const SizedBox(width: 8),
                        AppButton(
                          label: 'Save',
                          icon: Icons.check_rounded,
                          isLoading: saving,
                          onTap: saving
                              ? null
                              : () async {
                                  final code = codeCtrl.text.trim();
                                  if (code.isEmpty) {
                                    ToastService.showError(
                                        'Course code is required');
                                    return;
                                  }
                                  setDialogState(() => saving = true);
                                  try {
                                    final docId =
                                        isNew ? _docId(code) : existing['docId'];
                                    final lec =
                                        int.tryParse(lecCtrl.text) ?? 0;
                                    final prac =
                                        int.tryParse(pracCtrl.text) ?? 0;
                                    final total =
                                        int.tryParse(totalCtrl.text) ?? (lec + prac);
                                    final ic = icCtrl.text.trim();
                                    await _crud.saveCourse(_campusId,
                                      docId: docId,
                                      timetableData: {
                                        'sections': sections,
                                        'mid_sem_exam': midSem?.toJson(),
                                        'end_sem_exam': endSem?.toJson(),
                                        'lecture_credits': lec,
                                        'practical_credits': prac,
                                        if (ic.isNotEmpty)
                                          'instructor_in_charge': ic,
                                      },
                                      masterData: {
                                        'course_code': code,
                                        'title': titleCtrl.text.trim(),
                                        'credits': total,
                                        'type': 'Normal',
                                        if (ic.isNotEmpty)
                                          'instructor_in_charge': ic,
                                      },
                                    );
                                    ToastService.showSuccess('Course saved');
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _loadCourses();
                                  } catch (e) {
                                    ToastService.showError('Save failed: $e');
                                  } finally {
                                    if (ctx.mounted) {
                                      setDialogState(() => saving = false);
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    codeCtrl.dispose();
    titleCtrl.dispose();
    icCtrl.dispose();
    lecCtrl.dispose();
    pracCtrl.dispose();
    totalCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminService().isAdmin) {
      return Scaffold(
        appBar: AppDesign.appBar(context, title: 'Course Management'),
        body: const Center(child: Text('Admin access required')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Course Management'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        onPressed: () => _showCourseDialog(),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppDesign.spacingMd),
            child: Row(
              children: [
                InkWell(
                  onTap: _switchCampus,
                  borderRadius: BorderRadius.circular(6),
                  child: _badge(
                      _campusLabels[_campusId]!, accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSearchField(
                    controller: _searchController,
                    hint: 'Search courses...',
                    onChanged: _onSearchChanged,
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_courses.isEmpty)
            Expanded(
              child: Center(
                child: Text('No courses found',
                    style: TextStyle(color: AppDesign.muted(context))),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppDesign.spacingMd),
                itemCount: _courses.length,
                itemBuilder: (_, i) {
                  final c = _courses[i];
                  final code = c['course_code']?.toString() ?? '';
                  final title = c['title']?.toString() ?? '';
                  final secsList = (c['sections'] as List?) ?? [];
                  final lSec = secsList.where((s) => s['type']?.toString().contains('.L') ?? true).length;
                  final pSec = secsList.where((s) => s['type']?.toString().contains('.P') ?? false).length;
                  final tSec = secsList.where((s) => s['type']?.toString().contains('.T') ?? false).length;
                  final lec = c['lecture_credits'] ?? 0;
                  final prac = c['practical_credits'] ?? 0;
                  final total = c['credits'] ?? (lec + prac);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppDesign.borderRadiusSm,
                      side: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.12)),
                    ),
                    child: InkWell(
                      borderRadius: AppDesign.borderRadiusSm,
                      onTap: () => _showCourseDialog(existing: c),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: accent, width: 3),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(code,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onSurface)),
                                const SizedBox(width: 8),
                                if (lSec > 0) _badge('L:$lSec sec', AppDesign.info(context)),
                                if (tSec > 0) Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: _badge('T:$tSec sec', AppDesign.warning(context)),
                                ),
                                if (pSec > 0) Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: _badge('P:$pSec sec', AppDesign.success(context)),
                                ),
                                const Spacer(),
                                if (lec > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: _badge(
                                        'L:$lec', AppDesign.info(context)),
                                  ),
                                if (prac > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: _badge('P:$prac',
                                        AppDesign.success(context)),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: _badge('U:$total',
                                      AppDesign.warning(context)),
                                ),
                              ],
                            ),
                            if (title.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(title,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurface.withValues(
                                            alpha: AppDesign.opacityMedium)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

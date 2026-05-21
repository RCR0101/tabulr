import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../models/course.dart';
import '../services/auth_service.dart';
import '../services/timetable_service.dart';
import '../services/responsive_service.dart';
import '../services/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/share_timetable_dialog.dart';
import 'calendar_screen.dart';

class FreeSlotFinderScreen extends StatefulWidget {
  const FreeSlotFinderScreen({super.key});

  @override
  State<FreeSlotFinderScreen> createState() => _FreeSlotFinderScreenState();
}

class _FreeSlotFinderScreenState extends State<FreeSlotFinderScreen> {
  final TimetableService _timetableService = TimetableService();
  final AuthService _authService = AuthService();
  List<Timetable> _myTimetables = [];
  final List<_SlotSource> _sources = [];
  bool _isLoading = true;

  // Selection state
  int? _selDayIdx;
  int? _selStartHour;
  int? _selEndHour;

  static const _days = [
    DayOfWeek.M, DayOfWeek.T, DayOfWeek.W,
    DayOfWeek.Th, DayOfWeek.F, DayOfWeek.S,
  ];
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _hours = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  static String _hourStartTime(int hour) {
    final full = TimeSlotInfo.hourSlotNames[hour] ?? '';
    if (full.isEmpty) return 'H$hour';
    return full.split('-')[0].trim();
  }

  static String _hourEndTime(int hour) {
    final full = TimeSlotInfo.hourSlotNames[hour] ?? '';
    if (full.isEmpty) return '';
    final parts = full.split('-');
    return parts.length > 1 ? parts[1].trim() : '';
  }

  @override
  void initState() {
    super.initState();
    _loadTimetables();
  }

  Future<void> _loadTimetables() async {
    try {
      final timetables = await _timetableService.getAllTimetables();
      setState(() {
        _myTimetables = timetables;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ToastService.showError('Error loading timetables');
    }
  }

  void _addMyTimetable(Timetable tt) {
    if (_sources.any((s) => s.name == tt.name)) return;
    setState(() {
      _sources.add(_SlotSource(
        name: tt.name,
        busySlots: _extractBusySlots(tt.selectedSections),
        color: _sourceColor(_sources.length),
      ));
    });
  }

  Future<void> _addFromCode() async {
    final result = await ImportTimetableDialog.show(context);
    if (result == null || !mounted) return;
    final label = '${result.name} (${result.ownerName})';
    if (_sources.any((s) => s.name == label)) return;
    setState(() {
      _sources.add(_SlotSource(
        name: label,
        busySlots: _extractBusySlots(result.sections),
        color: _sourceColor(_sources.length),
      ));
    });
  }

  Set<String> _extractBusySlots(List<SelectedSection> sections) {
    final busy = <String>{};
    for (final sel in sections) {
      for (final entry in sel.section.schedule) {
        for (final day in entry.days) {
          for (final hour in entry.hours) {
            busy.add('${day.index}-$hour');
          }
        }
      }
    }
    return busy;
  }

  Color _sourceColor(int index) {
    const palette = [
      Color(0xFF58A6FF), Color(0xFF3FB950), Color(0xFFF778BA), Color(0xFFD29922),
      Color(0xFFBC8CFF), Color(0xFF39D2C0), Color(0xFFFF7B72), Color(0xFF79C0FF),
    ];
    return palette[index % palette.length];
  }

  Map<String, List<_SlotSource>> _computeBusyMap() {
    final allBusy = <String, List<_SlotSource>>{};
    for (final source in _sources) {
      for (final slot in source.busySlots) {
        allBusy.putIfAbsent(slot, () => []).add(source);
      }
    }
    return allBusy;
  }

  bool _isSlotFree(Map<String, List<_SlotSource>> busyMap, int dayIdx, int hour) {
    final key = '${_days[dayIdx].index}-$hour';
    return (busyMap[key] ?? []).isEmpty;
  }

  bool _isInSelection(int dayIdx, int hour) {
    if (_selDayIdx == null || _selDayIdx != dayIdx) return false;
    if (_selEndHour != null) {
      final lo = _selStartHour! < _selEndHour! ? _selStartHour! : _selEndHour!;
      final hi = _selStartHour! > _selEndHour! ? _selStartHour! : _selEndHour!;
      return hour >= lo && hour <= hi;
    }
    return hour == _selStartHour;
  }

  void _onSlotTap(int dayIdx, int hour, Map<String, List<_SlotSource>> busyMap) {
    if (!_isSlotFree(busyMap, dayIdx, hour)) return;

    setState(() {
      if (_selDayIdx == null || _selStartHour == null) {
        // First tap — start selection
        _selDayIdx = dayIdx;
        _selStartHour = hour;
        _selEndHour = null;
      } else if (_selDayIdx == dayIdx && _selEndHour == null) {
        if (hour == _selStartHour) {
          // Tapped same slot again — confirm single slot
          _selEndHour = hour;
          return;
        }
        // Second tap on same day — check all slots in range are free
        final lo = _selStartHour! < hour ? _selStartHour! : hour;
        final hi = _selStartHour! > hour ? _selStartHour! : hour;
        for (int h = lo; h <= hi; h++) {
          if (!_isSlotFree(busyMap, dayIdx, h)) {
            ToastService.showWarning('Busy slot in range — pick a different endpoint');
            return;
          }
        }
        _selEndHour = hour;
      } else {
        // Different day or already have a range — restart
        _selDayIdx = dayIdx;
        _selStartHour = hour;
        _selEndHour = null;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selDayIdx = null;
      _selStartHour = null;
      _selEndHour = null;
    });
  }

  int get _rangeStart {
    if (_selStartHour == null) return 0;
    if (_selEndHour == null) return _selStartHour!;
    return _selStartHour! < _selEndHour! ? _selStartHour! : _selEndHour!;
  }

  int get _rangeEnd {
    if (_selStartHour == null) return 0;
    if (_selEndHour == null) return _selStartHour!;
    return _selStartHour! > _selEndHour! ? _selStartHour! : _selEndHour!;
  }

  String get _selectionLabel {
    if (_selDayIdx == null || _selStartHour == null) return '';
    final day = _dayLabels[_selDayIdx!];
    if (_selEndHour == null) {
      return '$day ${_hourStartTime(_selStartHour!)} — tap another slot to extend';
    }
    final lo = _rangeStart;
    final hi = _rangeEnd;
    final startStr = _hourStartTime(lo);
    final endStr = _hourEndTime(hi);
    final count = hi - lo + 1;
    return '$day $startStr – $endStr ($count ${count == 1 ? 'hour' : 'hours'})';
  }

  Future<void> _createEventFromSelection() async {
    if (_selDayIdx == null || _selStartHour == null) return;

    final lo = _rangeStart;
    final hi = _rangeEnd;
    final day = _days[_selDayIdx!];
    final dayLabel = _dayLabels[_selDayIdx!];
    final duration = hi - lo + 1;
    final timeRange = '${_hourStartTime(lo)} – ${_hourEndTime(hi)}';

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          shape: AppDesign.dialogShape,
          title: Text('Add event'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: AppDesign.borderRadiusSm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '$dayLabel $timeRange',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: AppDesign.inputDecoration(
                    ctx,
                    label: 'Event title',
                    hint: 'e.g. Study session, Lunch',
                  ),
                  onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              icon: const Icon(Icons.calendar_month, size: 16),
              label: const Text('Add to Calendar'),
            ),
          ],
        );
      },
    );

    if (title == null || title.isEmpty || !mounted) return;

    final event = CalendarEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      type: 'custom',
      day: day,
      hour: lo,
      durationHours: duration,
      startTime: _hourToTimeOfDay(lo),
      endTime: _hourToTimeOfDay(hi + 1),
    );

    try {
      await _saveEventToCalendar(event);
      if (mounted) {
        ToastService.showSuccess('Added "$title" to calendar');
        _clearSelection();
      }
    } catch (e) {
      if (mounted) ToastService.showError('Failed to add event');
    }
  }

  TimeOfDay _hourToTimeOfDay(int hour) {
    const mapping = {
      1: TimeOfDay(hour: 8, minute: 0),
      2: TimeOfDay(hour: 9, minute: 0),
      3: TimeOfDay(hour: 10, minute: 0),
      4: TimeOfDay(hour: 11, minute: 0),
      5: TimeOfDay(hour: 12, minute: 0),
      6: TimeOfDay(hour: 13, minute: 0),
      7: TimeOfDay(hour: 14, minute: 0),
      8: TimeOfDay(hour: 15, minute: 0),
      9: TimeOfDay(hour: 16, minute: 0),
      10: TimeOfDay(hour: 17, minute: 0),
      11: TimeOfDay(hour: 18, minute: 0),
    };
    return mapping[hour] ?? TimeOfDay(hour: 7 + hour, minute: 0);
  }

  Future<void> _saveEventToCalendar(CalendarEvent event) async {
    final uid = _authService.userDocId;
    if (uid == null) throw Exception('Not authenticated');

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('calendar_prefs')
        .doc('data');

    final doc = await ref.get();
    final existing = <Map<String, dynamic>>[];
    if (doc.exists) {
      final data = doc.data();
      if (data != null && data['customEvents'] != null) {
        for (final e in data['customEvents'] as List<dynamic>) {
          existing.add(Map<String, dynamic>.from(e as Map));
        }
      }
    }
    existing.add(event.toJson());

    await ref.set({
      if (doc.exists && doc.data()?['selectedTimetableId'] != null)
        'selectedTimetableId': doc.data()!['selectedTimetableId'],
      'customEvents': existing,
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = ResponsiveService.isMobile(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Free Time Finder')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 12 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSourceSelector(scheme),
                      const SizedBox(height: 16),
                      if (_sources.length >= 2) ...[
                        _buildLegend(scheme),
                        const SizedBox(height: 12),
                        _buildGrid(scheme, isMobile),
                        if (_selStartHour != null) ...[
                          const SizedBox(height: 12),
                          _buildSelectionBar(scheme),
                        ],
                      ] else
                        _buildHint(scheme),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSourceSelector(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add timetables to compare',
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._myTimetables
                  .where((tt) => !_sources.any((s) => s.name == tt.name))
                  .map((tt) => ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: _sourceColor(_sources.length),
                      radius: 6,
                    ),
                    label: Text(tt.name),
                    onPressed: () => _addMyTimetable(tt),
                  )),
              ActionChip(
                avatar: Icon(Icons.download, size: 16, color: scheme.tertiary),
                label: const Text('Import from code'),
                onPressed: _addFromCode,
              ),
            ],
          ),
          if (_sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _sources
                  .map((s) => Chip(
                        avatar: CircleAvatar(backgroundColor: s.color, radius: 6),
                        label: Text(s.name, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => setState(() => _sources.remove(s)),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend(ColorScheme scheme) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _legendItem(
          Colors.green.withValues(alpha: 0.2),
          Colors.green.withValues(alpha: 0.5),
          'Free — tap to select',
          scheme,
        ),
        _legendItem(
          scheme.error.withValues(alpha: 0.15),
          scheme.error.withValues(alpha: 0.3),
          'Busy',
          scheme,
        ),
        ..._sources.map((s) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(s.name,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7))),
              ],
            )),
      ],
    );
  }

  Widget _legendItem(Color fill, Color border, String label, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: border),
            )),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildSelectionBar(ColorScheme scheme) {
    final hasRange = _selEndHour != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: AppDesign.borderRadiusMd,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _selectionLabel,
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
            ),
          ),
          TextButton(
            onPressed: _clearSelection,
            child: const Text('Cancel'),
          ),
          if (hasRange)
            FilledButton.icon(
              onPressed: _createEventFromSelection,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Create Event'),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(ColorScheme scheme, bool isMobile) {
    final busyMap = _computeBusyMap();

    if (isMobile) {
      return _buildVerticalGrid(scheme, busyMap);
    }
    return _buildHorizontalGrid(scheme, busyMap);
  }

  Widget _buildVerticalGrid(ColorScheme scheme, Map<String, List<_SlotSource>> busyMap) {
    final cellSize = 44.0;
    final headerHeight = 36.0;
    final hourColWidth = 44.0;

    return Center(
      child: Container(
        decoration: AppDesign.cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(width: hourColWidth, height: headerHeight),
                ..._dayLabels.map((label) => Expanded(
                      child: Container(
                        height: headerHeight,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.15)),
                            left: BorderSide(color: scheme.outline.withValues(alpha: 0.08)),
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    )),
              ],
            ),
            ..._hours.map((hour) => Row(
                  children: [
                    Container(
                      width: hourColWidth,
                      height: cellSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.08)),
                        ),
                      ),
                      child: Text(
                        _hourStartTime(hour),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    ...List.generate(_days.length, (dayIdx) {
                      return Expanded(
                        child: _buildCell(scheme, busyMap, dayIdx, hour,
                            width: null, height: cellSize, isMobile: true),
                      );
                    }),
                  ],
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalGrid(ColorScheme scheme, Map<String, List<_SlotSource>> busyMap) {
    final cellWidth = 72.0;
    final cellHeight = 48.0;
    final dayColWidth = 56.0;
    final totalWidth = dayColWidth + (cellWidth * _hours.length);

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: totalWidth),
        decoration: AppDesign.cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(width: dayColWidth, height: cellHeight),
                  ..._hours.map((h) => Container(
                        width: cellWidth,
                        height: cellHeight,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.15)),
                            left: BorderSide(color: scheme.outline.withValues(alpha: 0.08)),
                          ),
                        ),
                        child: Text(
                          _hourStartTime(h),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      )),
                ],
              ),
              ...List.generate(_days.length, (dayIdx) {
                return Row(
                  children: [
                    Container(
                      width: dayColWidth,
                      height: cellHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.08)),
                        ),
                      ),
                      child: Text(
                        _dayLabels[dayIdx],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    ..._hours.map((hour) {
                      return _buildCell(scheme, busyMap, dayIdx, hour,
                          width: cellWidth, height: cellHeight, isMobile: false);
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCell(ColorScheme scheme, Map<String, List<_SlotSource>> busyMap,
      int dayIdx, int hour,
      {double? width, required double height, required bool isMobile}) {
    final key = '${_days[dayIdx].index}-$hour';
    final busySources = busyMap[key] ?? [];
    final isFree = busySources.isEmpty;
    final isSelected = _isInSelection(dayIdx, hour);

    Color cellColor;
    if (isSelected) {
      cellColor = scheme.primary.withValues(alpha: 0.25);
    } else if (isFree) {
      cellColor = Colors.green.withValues(alpha: 0.12);
    } else {
      cellColor = scheme.error.withValues(alpha: 0.08);
    }

    return GestureDetector(
      onTap: isFree ? () => _onSlotTap(dayIdx, hour, busyMap) : null,
      child: MouseRegion(
        cursor: isFree ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: cellColor,
            border: Border(
              bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.08)),
              left: BorderSide(color: scheme.outline.withValues(alpha: 0.08)),
            ),
          ),
          child: Center(
            child: isSelected
                ? Icon(Icons.check_circle,
                    size: isMobile ? 16 : 20, color: scheme.primary)
                : isFree
                    ? Icon(Icons.add_circle_outline,
                        size: isMobile ? 14 : 18,
                        color: Colors.green.withValues(alpha: 0.5))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: busySources
                            .take(4)
                            .map((s) => Container(
                                  width: isMobile ? 6 : 8,
                                  height: isMobile ? 6 : 8,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                      color: s.color, shape: BoxShape.circle),
                                ))
                            .toList(),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildHint(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        children: [
          Icon(Icons.group, size: 48, color: scheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'Add at least 2 timetables to find common free slots',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SlotSource {
  final String name;
  final Set<String> busySlots;
  final Color color;

  _SlotSource({required this.name, required this.busySlots, required this.color});
}

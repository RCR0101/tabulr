import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../models/course.dart';
import '../services/timetable_service.dart';
import '../services/timetable_sharing_service.dart';
import '../services/responsive_service.dart';
import '../services/toast_service.dart';
import '../utils/design_constants.dart';
import '../widgets/share_timetable_dialog.dart';

class FreeSlotFinderScreen extends StatefulWidget {
  const FreeSlotFinderScreen({super.key});

  @override
  State<FreeSlotFinderScreen> createState() => _FreeSlotFinderScreenState();
}

class _FreeSlotFinderScreenState extends State<FreeSlotFinderScreen> {
  final TimetableService _timetableService = TimetableService();
  List<Timetable> _myTimetables = [];
  final List<_SlotSource> _sources = [];
  bool _isLoading = true;

  static const _days = [
    DayOfWeek.M,
    DayOfWeek.T,
    DayOfWeek.W,
    DayOfWeek.Th,
    DayOfWeek.F,
    DayOfWeek.S,
  ];
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _hours = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

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
        busySlots: _extractBusySlots(tt.selectedSections, tt.availableCourses),
        color: _sourceColor(_sources.length),
      ));
    });
  }

  Future<void> _addFromCode() async {
    final result = await ImportTimetableDialog.show(context);
    if (result == null || !mounted) return;
    if (_sources.any((s) => s.name == '${result.name} (${result.ownerName})')) return;
    setState(() {
      _sources.add(_SlotSource(
        name: '${result.name} (${result.ownerName})',
        busySlots: _extractBusySlotsFromSections(result.sections),
        color: _sourceColor(_sources.length),
      ));
    });
  }

  Set<String> _extractBusySlots(List<SelectedSection> sections, List<Course> courses) {
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

  Set<String> _extractBusySlotsFromSections(List<SelectedSection> sections) {
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
      Color(0xFF58A6FF),
      Color(0xFF3FB950),
      Color(0xFFF778BA),
      Color(0xFFD29922),
      Color(0xFFBC8CFF),
      Color(0xFF39D2C0),
      Color(0xFFFF7B72),
      Color(0xFF79C0FF),
    ];
    return palette[index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Free Slot Finder')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(ResponsiveService.isMobile(context) ? 12 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSourceSelector(scheme),
                      const SizedBox(height: 16),
                      if (_sources.length >= 2) ...[
                        _buildLegend(scheme),
                        const SizedBox(height: 12),
                        _buildGrid(scheme),
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
          Text('Add timetables to compare', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._myTimetables.map((tt) => ActionChip(
                    avatar: Icon(Icons.schedule, size: 16, color: scheme.primary),
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
              children: _sources.map((s) => Chip(
                    avatar: CircleAvatar(backgroundColor: s.color, radius: 6),
                    label: Text(s.name, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() => _sources.remove(s)),
                    visualDensity: VisualDensity.compact,
                  )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegend(ColorScheme scheme) {
    return Row(
      children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        )),
        const SizedBox(width: 6),
        Text('Free for all', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7))),
        const SizedBox(width: 16),
        Container(width: 16, height: 16, decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
        )),
        const SizedBox(width: 6),
        Text('Busy', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildGrid(ColorScheme scheme) {
    final allBusy = <String, List<_SlotSource>>{};
    for (final source in _sources) {
      for (final slot in source.busySlots) {
        allBusy.putIfAbsent(slot, () => []).add(source);
      }
    }

    return Container(
      decoration: AppDesign.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 4,
          headingRowHeight: 36,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 32,
          border: TableBorder.all(color: scheme.outline.withValues(alpha: 0.1)),
          columns: [
            const DataColumn(label: SizedBox(width: 40, child: Text('', style: TextStyle(fontSize: 12)))),
            ..._hours.map((h) => DataColumn(
                  label: SizedBox(
                    width: 36,
                    child: Text('H$h', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                  ),
                )),
          ],
          rows: List.generate(_days.length, (dayIdx) {
            return DataRow(
              cells: [
                DataCell(Text(_dayLabels[dayIdx], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                ..._hours.map((hour) {
                  final key = '${_days[dayIdx].index}-$hour';
                  final busySources = allBusy[key] ?? [];
                  final isFree = busySources.isEmpty;
                  return DataCell(
                    Center(
                      child: Container(
                        width: 32,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isFree
                              ? Colors.green.withValues(alpha: 0.15)
                              : scheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: isFree
                            ? Icon(Icons.check, size: 12, color: Colors.green.withValues(alpha: 0.7))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: busySources.take(3).map((s) =>
                                  Container(
                                    width: 6, height: 6,
                                    margin: const EdgeInsets.symmetric(horizontal: 1),
                                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                                  ),
                                ).toList(),
                              ),
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
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

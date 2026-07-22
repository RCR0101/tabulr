import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/data/timetable_storage_service.dart';
import '../utils/design_constants.dart';
import '../widgets/timetable_widget.dart';

class ArchivedTimetablesScreen extends StatefulWidget {
  final ArchivedSemester semester;

  const ArchivedTimetablesScreen({super.key, required this.semester});

  @override
  State<ArchivedTimetablesScreen> createState() => _ArchivedTimetablesScreenState();
}

class _ArchivedTimetablesScreenState extends State<ArchivedTimetablesScreen> {
  List<Timetable>? _timetables;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final timetables = await TimetableStorageService().getArchivedTimetables(widget.semester.id);
    if (mounted) {
      setState(() {
        _timetables = timetables;
        _isLoading = false;
      });
    }
  }

  List<TimetableSlot> _buildSlots(Timetable timetable) {
    final slots = <TimetableSlot>[];
    for (final ss in timetable.selectedSections) {
      final baseTitle = timetable.availableCourses
              .where((c) => c.courseCode == ss.courseCode)
              .firstOrNull
              ?.courseTitle ??
          ss.courseCode;

      for (final entry in ss.section.schedule) {
        for (final day in entry.days) {
          final title = ss.section.type == SectionType.L
              ? baseTitle
              : '$baseTitle (${ss.section.type.name})';
          slots.add(TimetableSlot(
            day: day,
            hours: entry.hours,
            courseCode: ss.courseCode,
            courseTitle: title,
            sectionId: ss.sectionId,
            instructor: ss.section.instructor,
            room: ss.section.room,
          ));
        }
      }
    }
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: widget.semester.label),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _timetables == null || _timetables!.isEmpty
              ? Center(
                  child: Text(
                    'No archived timetables',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  itemCount: _timetables!.length,
                  itemBuilder: (context, index) {
                    final tt = _timetables![index];
                    final courseCodes = tt.selectedSections.map((s) => s.courseCode).toSet().toList();
                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: AppDesign.borderRadiusMd),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: AppDesign.borderRadiusMd,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ArchivedTimetableDetailScreen(
                              timetable: tt,
                              semesterLabel: widget.semester.label,
                              slots: _buildSlots(tt),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppDesign.spacingMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(tt.name, style: Theme.of(context).textTheme.titleMedium),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: scheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Archived',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: scheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (courseCodes.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: courseCodes.map((code) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      code,
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurface.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  )).toList(),
                                ),
                              ],
                              const SizedBox(height: AppDesign.spacingSm),
                              Text(
                                '${courseCodes.length} course${courseCodes.length != 1 ? 's' : ''}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: AppDesign.opacityMedium),
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
}

class _ArchivedTimetableDetailScreen extends StatelessWidget {
  final Timetable timetable;
  final String semesterLabel;
  final List<TimetableSlot> slots;

  const _ArchivedTimetableDetailScreen({
    required this.timetable,
    required this.semesterLabel,
    required this.slots,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(context, title: timetable.name),
      body: slots.isEmpty
          ? Center(
              child: Text(
                'No sections in this timetable',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          : TimetableWidget(timetableSlots: slots),
    );
  }
}

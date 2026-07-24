import 'package:flutter/material.dart';
import '../../models/course.dart';
import '../../models/timetable_constraints.dart';

class TimeAvoidanceDialog extends StatefulWidget {
  /// Hours already marked to avoid, per day. These are shown as locked in the
  /// grid so the same slot can't be picked twice.
  final Map<DayOfWeek, Set<int>> disabledByDay;

  const TimeAvoidanceDialog({super.key, this.disabledByDay = const {}});

  @override
  State<TimeAvoidanceDialog> createState() => _TimeAvoidanceDialogState();
}

class _TimeAvoidanceDialogState extends State<TimeAvoidanceDialog> {
  DayOfWeek? _selectedDay;
  final List<int> _selectedHours = [];

  Set<int> get _alreadyAvoided =>
      _selectedDay == null ? const {} : (widget.disabledByDay[_selectedDay] ?? const {});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Time to Avoid'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<DayOfWeek>(
              decoration: const InputDecoration(labelText: 'Day'),
              initialValue: _selectedDay,
              items: DayOfWeek.values.map((day) => DropdownMenuItem(
                value: day,
                child: Text(day.name),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDay = value;
                  // A slot picked for the previous day may already be avoided
                  // for the new one — clear so nothing invalid carries over.
                  _selectedHours.removeWhere(_alreadyAvoided.contains);
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Hours to avoid:'),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              width: double.infinity,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: 10,
                itemBuilder: (context, index) {
                  final hour = index + 1;
                  final alreadyAvoided = _alreadyAvoided.contains(hour);
                  final isSelected = _selectedHours.contains(hour);
                  return FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (alreadyAvoided)
                          const Padding(
                            padding: EdgeInsets.only(right: 2),
                            child: Icon(Icons.lock, size: 10),
                          ),
                        Text(hour.toString(), style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                    tooltip: alreadyAvoided
                        ? '${TimeSlotInfo.getHourSlotName(hour)} — already avoided'
                        : TimeSlotInfo.getHourSlotName(hour),
                    selected: isSelected || alreadyAvoided,
                    // Locked once already avoided for this day — can't re-pick.
                    onSelected: alreadyAvoided
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected) {
                                _selectedHours.add(hour);
                              } else {
                                _selectedHours.remove(hour);
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
          onPressed: _selectedDay != null && _selectedHours.isNotEmpty
            ? () {
                final avoidTime = TimeAvoidance(
                  day: _selectedDay!,
                  hours: [..._selectedHours],
                );
                Navigator.pop(context, avoidTime);
              }
            : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

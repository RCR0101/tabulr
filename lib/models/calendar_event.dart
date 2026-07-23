import 'package:flutter/material.dart';
import '../utils/datetime_utils.dart';
import 'course.dart';

int timeToSlotHour(TimeOfDay t) => t.hour - 7;

int slotSpanFromTimes(TimeOfDay start, TimeOfDay end) {
  final startSlot = timeToSlotHour(start);
  final endSlot = timeToSlotHour(end);
  return (endSlot - startSlot).clamp(1, 12);
}

String dayFullName(DayOfWeek day) => getDayName(day);

class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final String type;
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
      return '${formatTime(startTime!)} – ${formatTime(endTime!)}';
    }
    final slotStart = TimeSlotInfo.hourSlotNames[hour] ?? '';
    return slotStart.isNotEmpty ? slotStart : 'Hour $hour';
  }

  static String formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $p';
  }
}

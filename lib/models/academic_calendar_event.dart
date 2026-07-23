import 'package:flutter/material.dart';

/// What kind of academic-calendar entry this is. Drives both the calendar
/// overlay's styling and whether it becomes a reminder in the ICS export.
enum AcademicEventCategory {
  /// A gazetted holiday — no classes.
  holiday,

  /// An examination window (mid-sem, comprehensive).
  exam,

  /// An action the student must take by a date (registration, add/drop,
  /// withdrawal). These are the ones worth a calendar reminder.
  deadline,

  /// A term boundary or administrative marker (classwork begins, semester ends,
  /// grading day, vacation).
  milestone,

  /// Everything else — fests, PS dates, one-off events.
  event;

  static AcademicEventCategory fromName(String? name) {
    return AcademicEventCategory.values.firstWhere(
      (c) => c.name == name,
      orElse: () => AcademicEventCategory.event,
    );
  }

  /// Whether an entry of this kind should export as a reminder.
  bool get isReminderWorthy =>
      this == AcademicEventCategory.deadline || this == AcademicEventCategory.exam;
}

/// One dated entry on a campus's academic calendar, as parsed from the
/// timetable booklet and curated by an admin. [endDate] is set only for
/// multi-day entries (an exam window, a fest) and is inclusive.
@immutable
class AcademicCalendarEvent {
  const AcademicCalendarEvent({
    required this.date,
    this.endDate,
    required this.label,
    required this.category,
    this.dayOfWeek,
  });

  final DateTime date;
  final DateTime? endDate;
  final String label;
  final AcademicEventCategory category;

  /// The booklet's day-of-week token (e.g. "M", "Th"), kept only for display;
  /// never trusted over [date].
  final String? dayOfWeek;

  bool get isRange => endDate != null && endDate!.isAfter(date);

  /// Whether [day] (date-only) falls within this entry's span, inclusive.
  bool coversDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(date.year, date.month, date.day);
    if (d.isBefore(start)) return false;
    final end = endDate == null
        ? start
        : DateTime(endDate!.year, endDate!.month, endDate!.day);
    return !d.isAfter(end);
  }

  Map<String, dynamic> toJson() => {
        'date': _fmt(date),
        if (endDate != null) 'endDate': _fmt(endDate!),
        'label': label,
        'category': category.name,
        if (dayOfWeek != null) 'dayOfWeek': dayOfWeek,
      };

  factory AcademicCalendarEvent.fromJson(Map<String, dynamic> json) {
    final start = DateTime.parse(json['date'] as String);
    final rawEnd = json['endDate'];
    return AcademicCalendarEvent(
      date: start,
      endDate: rawEnd is String ? DateTime.tryParse(rawEnd) : null,
      label: (json['label'] as String?)?.trim() ?? '',
      category: AcademicEventCategory.fromName(json['category'] as String?),
      dayOfWeek: json['dayOfWeek'] as String?,
    );
  }

  AcademicCalendarEvent copyWith({
    DateTime? date,
    DateTime? endDate,
    bool clearEndDate = false,
    String? label,
    AcademicEventCategory? category,
    String? dayOfWeek,
  }) =>
      AcademicCalendarEvent(
        date: date ?? this.date,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        label: label ?? this.label,
        category: category ?? this.category,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      );

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Short chip label for a category — shared by the admin editor and the
/// calendar overlay so the two never label a category differently.
String academicCategoryShort(AcademicEventCategory c) => switch (c) {
      AcademicEventCategory.holiday => 'HOL',
      AcademicEventCategory.exam => 'EXAM',
      AcademicEventCategory.deadline => 'DUE',
      AcademicEventCategory.milestone => 'MILE',
      AcademicEventCategory.event => 'EVT',
    };

/// Accent colour for a category, consistent between the admin list and the
/// calendar overlay.
Color academicCategoryColor(BuildContext context, AcademicEventCategory c) {
  final scheme = Theme.of(context).colorScheme;
  return switch (c) {
    AcademicEventCategory.holiday => scheme.error,
    AcademicEventCategory.exam => scheme.tertiary,
    AcademicEventCategory.deadline => scheme.primary,
    AcademicEventCategory.milestone => scheme.secondary,
    AcademicEventCategory.event => scheme.onSurface.withValues(alpha: 0.6),
  };
}

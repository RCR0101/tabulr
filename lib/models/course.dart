import '../constants/app_constants.dart';
export '../constants/app_constants.dart' show TimeSlot, ExamSlotConstants;

/// A BITS course offering for a particular semester and campus.
///
/// Contains the full catalog entry: credits, all available sections
/// (lectures, practicals, tutorials), and exam schedules.
/// Deserialized from Firestore via [Course.fromJson]; the JSON uses
/// both snake_case (uploader output) and camelCase (app-serialized) keys.
class Course {
  final String courseCode;
  final String courseTitle;
  final double lectureCredits;
  final double practicalCredits;
  final double totalCredits;

  /// Every section offered for this course (L, P, and T combined).
  final List<Section> sections;
  final ExamSchedule? midSemExam;
  final ExamSchedule? endSemExam;

  Course({
    required this.courseCode,
    required this.courseTitle,
    required this.lectureCredits,
    required this.practicalCredits,
    required this.totalCredits,
    required this.sections,
    this.midSemExam,
    this.endSemExam,
  });

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'lectureCredits': lectureCredits,
      'practicalCredits': practicalCredits,
      'totalCredits': totalCredits,
      'sections': sections.map((s) => s.toJson()).toList(),
      'midSemExam': midSemExam?.toJson(),
      'endSemExam': endSemExam?.toJson(),
    };
  }

  factory Course.fromJson(Map<String, dynamic> json, {String? courseCode, String? resolvedTitle}) {
    final code = courseCode ?? json['courseCode'] ?? '';
    return Course(
      courseCode: code,
      courseTitle: resolvedTitle ?? json['courseTitle'] ?? code,
      lectureCredits: (json['lecture_credits'] ?? json['lectureCredits'] ?? 0).toDouble(),
      practicalCredits: (json['practical_credits'] ?? json['practicalCredits'] ?? 0).toDouble(),
      totalCredits: ((json['lecture_credits'] ?? json['lectureCredits'] ?? 0) +
          (json['practical_credits'] ?? json['practicalCredits'] ?? 0)).toDouble(),
      sections: (json['sections'] as List?)
              ?.map((s) => Section.fromJson(s))
              .toList() ??
          [],
      midSemExam: (json['mid_sem_exam'] ?? json['midSemExam']) != null
          ? ExamSchedule.fromJson(json['mid_sem_exam'] ?? json['midSemExam'])
          : null,
      endSemExam: (json['end_sem_exam'] ?? json['endSemExam']) != null
          ? ExamSchedule.fromJson(json['end_sem_exam'] ?? json['endSemExam'])
          : null,
    );
  }
}

/// One section (lecture, practical, or tutorial) of a [Course].
///
/// A section can have multiple [ScheduleEntry]s when it meets at different
/// day/hour combinations (e.g. MWF hour 3 + T hour 7).
class Section {
  /// E.g. "L1", "P2", "T1".
  final String sectionId;
  final SectionType type;
  final String instructor;
  final String room;
  final List<ScheduleEntry> schedule;

  Section({
    required this.sectionId,
    required this.type,
    required this.instructor,
    required this.room,
    required this.schedule,
  });

  // Convenience getters for backward compatibility
  List<DayOfWeek> get days => schedule.expand((entry) => entry.days).toSet().toList();
  List<int> get hours => schedule.expand((entry) => entry.hours).toList();

  Map<String, dynamic> toJson() {
    return {
      'sectionId': sectionId,
      'type': type.toString(),
      'instructor': instructor,
      'room': room,
      'schedule': schedule.map((entry) => entry.toJson()).toList(),
    };
  }

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      sectionId: json['sectionId'],
      type: SectionType.values.firstWhere(
        (e) => e.toString() == json['type'],
      ),
      instructor: json['instructor'],
      room: json['room'],
      schedule: (json['schedule'] as List)
          .map((entry) => ScheduleEntry.fromJson(entry))
          .toList(),
    );
  }
}

/// A set of days × hours when a section meets (cartesian: every listed day
/// at every listed hour). Multiple entries per section allow disjoint
/// day/hour blocks.
class ScheduleEntry {
  final List<DayOfWeek> days;

  /// 1-based hour indices (1 = 8:00 AM, see [TimeSlotInfo.hourSlotNames]).
  final List<int> hours;

  ScheduleEntry({
    required this.days,
    required this.hours,
  });

  Map<String, dynamic> toJson() {
    return {
      'days': days.map((d) => d.toString()).toList(),
      'hours': hours,
    };
  }

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      days: (json['days'] as List)
          .map((d) => DayOfWeek.values.firstWhere(
                (e) => e.toString() == d,
              ))
          .toList(),
      hours: List<int>.from(json['hours']),
    );
  }
}


/// Date + time-slot for a midsem or comprehensive exam.
class ExamSchedule {
  /// Date only (time component is midnight); the actual exam window is
  /// determined by [timeSlot] and the campus.
  final DateTime date;
  final TimeSlot timeSlot;

  ExamSchedule({
    required this.date,
    required this.timeSlot,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'timeSlot': timeSlot.toString(),
    };
  }

  factory ExamSchedule.fromJson(Map<String, dynamic> json) {
    // Parse only the date part to avoid timezone issues
    final dateString = json['date'] as String;
    final dateParts = dateString.split('T')[0].split('-');
    final year = int.parse(dateParts[0]);
    final month = int.parse(dateParts[1]);
    final day = int.parse(dateParts[2]);
    
    return ExamSchedule(
      date: DateTime(year, month, day),
      timeSlot: TimeSlot.values.firstWhere(
        (e) => e.toString() == json['timeSlot'],
      ),
    );
  }
}

/// L = Lecture, P = Practical, T = Tutorial.
enum SectionType { L, P, T }

/// Monday through Saturday; [T] is Tuesday, [Th] is Thursday.
// ignore: constant_identifier_names
enum DayOfWeek { M, T, W, Th, F, S }

/// Exam time windows. MS* slots are for midsems; FN/AN are for compres.
/// Maps hour indices and [TimeSlot]s to human-readable clock strings,
/// with campus-specific overrides for exam windows.
/// Data lives in [ExamSlotConstants] and [ScheduleConstants]; this class
/// provides convenience accessors.
class TimeSlotInfo {
  static const Map<TimeSlot, String> timeSlotNames =
      ExamSlotConstants.defaultTimeSlotNames;

  static final Map<int, String> hourSlotNames = ScheduleConstants.hourSlotNames;

  static String getTimeSlotName(TimeSlot slot, {String? campus}) {
    if (campus != null &&
        ExamSlotConstants.campusTimeSlotNames.containsKey(campus)) {
      return ExamSlotConstants.campusTimeSlotNames[campus]![slot] ?? '';
    }
    return timeSlotNames[slot] ?? '';
  }

  static String getHourSlotName(int hour) {
    return hourSlotNames[hour] ?? '';
  }

  static String getHourRangeName(List<int> hours) {
    if (hours.isEmpty) return '';
    if (hours.length == 1) return getHourSlotName(hours.first);
    hours.sort();
    String startTime = hourSlotNames[hours.first]?.split('-')[0] ?? '';
    String endTime = hourSlotNames[hours.last]?.split('-')[1] ?? '';
    return '$startTime-$endTime';
  }

  static List<String> getScheduleEntryNames(List<ScheduleEntry> schedule) {
    List<String> result = [];
    for (var entry in schedule) {
      for (var day in entry.days) {
        String dayStr = day.toString().split('.').last;
        String hourStr = getHourRangeName(entry.hours);
        result.add('$dayStr $hourStr');
      }
    }
    return result;
  }

  static String getFormattedSchedule(List<ScheduleEntry> schedule) {
    if (schedule.isEmpty) return '';
    return getScheduleEntryNames(schedule).join(', ');
  }

  static bool isMidSemSlot(TimeSlot slot) {
    return [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4]
        .contains(slot);
  }

  static bool isEndSemSlot(TimeSlot slot) {
    return [TimeSlot.FN, TimeSlot.AN].contains(slot);
  }

  static List<TimeSlot> getMidSemSlots() {
    return [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4];
  }

  static List<TimeSlot> getEndSemSlots() {
    return [TimeSlot.FN, TimeSlot.AN];
  }

  static Map<TimeSlot, List<int>> getCampusExamTimes(String campus) {
    return ExamSlotConstants.campusExamStartTimes[campus] ??
        ExamSlotConstants.campusExamStartTimes['hyderabad']!;
  }
}
class Course {
  final String courseCode;
  final String courseTitle;
  final int lectureCredits;
  final int practicalCredits;
  final int totalCredits;
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

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      courseCode: json['courseCode'],
      courseTitle: json['courseTitle'],
      lectureCredits: json['lectureCredits'],
      practicalCredits: json['practicalCredits'],
      totalCredits: json['totalCredits'],
      sections: (json['sections'] as List)
          .map((s) => Section.fromJson(s))
          .toList(),
      midSemExam: json['midSemExam'] != null
          ? ExamSchedule.fromJson(json['midSemExam'])
          : null,
      endSemExam: json['endSemExam'] != null
          ? ExamSchedule.fromJson(json['endSemExam'])
          : null,
    );
  }
}

class Section {
  final String sectionId;
  final SectionType type;
  final String instructor;
  final String room;
  final List<ScheduleEntry> schedule; // Changed to list of schedule entries

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

class ScheduleEntry {
  final List<DayOfWeek> days;
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


class ExamSchedule {
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
    return ExamSchedule(
      date: DateTime.parse(json['date']),
      timeSlot: TimeSlot.values.firstWhere(
        (e) => e.toString() == json['timeSlot'],
      ),
    );
  }
}

enum SectionType { L, P, T }

enum DayOfWeek { M, T, W, Th, F, S }

enum TimeSlot {
  FN, // 9:30AM-12:30PM (EndSem only)
  AN, // 2:00PM-5:00PM (EndSem only)
  MS1, // 9:30AM-11:00AM (MidSem)
  MS2, // 11:30AM-1:00PM (MidSem)
  MS3, // 1:30PM-3:00PM (MidSem)
  MS4, // 3:30PM-5:00PM (MidSem)
}

class TimeSlotInfo {
  static const Map<TimeSlot, String> timeSlotNames = {
    TimeSlot.FN: '9:30AM-12:30PM',
    TimeSlot.AN: '2:00PM-5:00PM',
    TimeSlot.MS1: '9:30AM-11:00AM',
    TimeSlot.MS2: '11:30AM-1:00PM',
    TimeSlot.MS3: '1:30PM-3:00PM',
    TimeSlot.MS4: '3:30PM-5:00PM',
  };

  static const Map<int, String> hourSlotNames = {
    1: '8:00AM-8:50AM',
    2: '9:00AM-9:50AM',
    3: '10:00AM-10:50AM',
    4: '11:00AM-11:50AM',
    5: '12:00PM-12:50PM',
    6: '1:00PM-1:50PM',
    7: '2:00PM-2:50PM',
    8: '3:00PM-3:50PM',
    9: '4:00PM-4:50PM',
    10: '5:00PM-5:50PM',
  };

  static String getTimeSlotName(TimeSlot slot) {
    return timeSlotNames[slot] ?? '';
  }

  static String getHourSlotName(int hour) {
    return hourSlotNames[hour] ?? '';
  }

  static String getHourRangeName(List<int> hours) {
    if (hours.isEmpty) return '';
    if (hours.length == 1) return getHourSlotName(hours.first);
    
    hours.sort();
    int startHour = hours.first;
    int endHour = hours.last;
    String startTime = hourSlotNames[startHour]?.split('-')[0] ?? '';
    String endTime = hourSlotNames[endHour]?.split('-')[1] ?? '';
    return '$startTime-$endTime';
  }

  // New method to handle schedule entries with individual day-hour pairs
  static List<String> getScheduleEntryNames(List<ScheduleEntry> schedule) {
    List<String> result = [];
    
    for (var entry in schedule) {
      // For each day in the entry, pair it with the hour range
      for (var day in entry.days) {
        String dayStr = day.toString().split('.').last;
        String hourStr = getHourRangeName(entry.hours);
        result.add('$dayStr $hourStr');
      }
    }
    
    return result;
  }

  // New method to get formatted string for all schedule entries
  static String getFormattedSchedule(List<ScheduleEntry> schedule) {
    if (schedule.isEmpty) return '';
    
    List<String> entryNames = getScheduleEntryNames(schedule);
    return entryNames.join(', ');
  }

  static bool isMidSemSlot(TimeSlot slot) {
    return [TimeSlot.MS1, TimeSlot.MS2, TimeSlot.MS3, TimeSlot.MS4].contains(slot);
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
}
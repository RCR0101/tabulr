import '../constants/app_constants.dart';
export '../constants/app_constants.dart' show TimeSlot, ExamSlotConstants;

/// What a course counts in. The two cannot be added together — 4 units and 12
/// credit hours are the same course, described for different batches.
enum CreditBasis {
  units('credits'),
  hours('credit hours');

  const CreditBasis(this.label);

  /// For prose: "12 credit hours", "over the credit limit".
  final String label;
}

/// One way a course is on offer: a com cod, and the credits that go with it.
///
/// From 2026-27 Pilani prints some courses twice — once normally, once under a
/// com cod >= 5000 for the 2026 batch, stated in contact hours rather than
/// units. Same sections, same rooms, same times; what differs is which row a
/// student registers under. Both are offered simultaneously, so this is a
/// choice to show rather than a duplicate to hide.
class CourseVariant {
  const CourseVariant({
    required this.comCode,
    required this.credits,
    required this.creditHours,
  });

  /// 0 when the booklet prints no com cod (Goa 2026-27 dropped the column).
  final int comCode;
  final double credits;
  final double creditHours;

  /// Whether this row states contact hours instead of units.
  bool get isInHours => creditHours > 0 && credits == 0;

  CreditBasis get basis => isInHours ? CreditBasis.hours : CreditBasis.units;

  /// The number this variant contributes to a timetable's total.
  double get amount => isInHours ? creditHours : credits;

  factory CourseVariant.fromJson(Map<String, dynamic> json) => CourseVariant(
        comCode: (json['com_code'] ?? json['comCode'] as num?)?.toInt() ?? 0,
        credits: ((json['credits'] ?? 0) as num).toDouble(),
        creditHours:
            ((json['credit_hours'] ?? json['creditHours'] ?? 0) as num)
                .toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'com_code': comCode,
        'credits': credits,
        'credit_hours': creditHours,
      };
}

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

  /// Contact hours, for the batches whose booklet row is printed in them.
  ///
  /// A separate number from [totalCredits], not a multiple of it: Pilani's
  /// CHEM U101 is 3 units and 7 credit hours. 0 where the booklet prints none,
  /// which is every Hyderabad and Goa course today.
  final double totalCreditHours;

  /// Every com cod this course was printed under. Two for a Pilani course that
  /// also has a 2026-batch row, empty for booklets with no com code column.
  final List<int> comCodes;

  /// Stored only when the course is on offer more than one way; [variants] is
  /// what callers should read, so the ordinary case needs no special handling.
  final List<CourseVariant> _storedVariants;

  /// The ways this course can be taken, always at least one.
  ///
  /// Synthesised from the course's own credits when the booklet offers it a
  /// single way, which is every course outside Pilani's 2026-batch pairs — so
  /// a caller can render or choose without asking which case it is in.
  List<CourseVariant> get variants => _storedVariants.isNotEmpty
      ? _storedVariants
      : [
          CourseVariant(
            comCode: comCodes.isNotEmpty ? comCodes.first : 0,
            credits: totalCredits,
            creditHours: totalCreditHours,
          )
        ];

  /// Whether a student has to pick which way to take this course.
  bool get hasVariantChoice => _storedVariants.length > 1;

  /// The variant a selection means. Falls back to the first, which is what an
  /// older saved timetable — stored before com cods existed — resolves to.
  CourseVariant variantFor(int? comCode) => variants.firstWhere(
        (v) => v.comCode == comCode,
        orElse: () => variants.first,
      );

  /// Whether this course can be taken on [basis] at all.
  ///
  /// Most courses offer exactly one, which is what makes this a filter: a
  /// credit-hours timetable cannot hold a course the booklet only prints units
  /// for, so showing it in the list would only lead to a refusal later.
  bool offersBasis(CreditBasis basis) => variants.any((v) => v.basis == basis);

  /// The variant to use on [basis], or null when the course is not offered
  /// that way.
  CourseVariant? variantOn(CreditBasis basis) =>
      variants.where((v) => v.basis == basis).firstOrNull;

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
    this.totalCreditHours = 0,
    this.comCodes = const [],
    List<CourseVariant> variants = const [],
    required this.sections,
    this.midSemExam,
    this.endSemExam,
  }) : _storedVariants = variants;

  Map<String, dynamic> toJson() {
    return {
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'lectureCredits': lectureCredits,
      'practicalCredits': practicalCredits,
      'totalCredits': totalCredits,
      'totalCreditHours': totalCreditHours,
      'comCodes': comCodes,
      if (_storedVariants.isNotEmpty)
        'variants': [for (final v in _storedVariants) v.toJson()],
      'sections': sections.map((s) => s.toJson()).toList(),
      'midSemExam': midSemExam?.toJson(),
      'endSemExam': endSemExam?.toJson(),
    };
  }

  factory Course.fromJson(Map<String, dynamic> json, {String? courseCode, String? resolvedTitle}) {
    final code = courseCode ?? json['courseCode'] ?? '';
    final lecture = (json['lecture_credits'] ?? json['lectureCredits'] ?? 0).toDouble();
    final practical = (json['practical_credits'] ?? json['practicalCredits'] ?? 0).toDouble();
    // Prefer the stored unit count (U). Many BITS courses — projects, theses,
    // labs, seminars — carry units that are NOT lecture + practical (the PDF
    // gives them as "- - 3"), so falling back to L+P here reported 0 for all of
    // them. Only fall back when no total was persisted (older data).
    final storedTotal = json['total_credits'] ?? json['totalCredits'] ?? json['credits'];
    return Course(
      courseCode: code,
      courseTitle: resolvedTitle ?? json['courseTitle'] ?? code,
      lectureCredits: lecture,
      practicalCredits: practical,
      totalCredits: storedTotal != null
          ? (storedTotal as num).toDouble()
          : lecture + practical,
      // Never falls back to units or to L + P: an absent value means the
      // booklet printed no hours for this course, not that they equal
      // something else. Rendering must say "not published", not guess.
      totalCreditHours:
          ((json['total_credit_hours'] ?? json['totalCreditHours']) as num?)
                  ?.toDouble() ??
              0,
      comCodes: [
        for (final c in (json['com_codes'] ?? json['comCodes']) as List? ??
            const [])
          (c as num).toInt()
      ],
      variants: [
        for (final v in json['variants'] as List? ?? const [])
          CourseVariant.fromJson(Map<String, dynamic>.from(v as Map))
      ],
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

  static String dedupeInstructors(String field) {
    final seen = <String>{};
    final kept = <String>[];
    for (final name in field.split(',')) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) kept.add(trimmed);
    }
    return kept.join(', ');
  }

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      sectionId: json['sectionId'],
      type: SectionType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => SectionType.L,
      ),
      instructor: dedupeInstructors(json['instructor'] as String? ?? ''),
      room: json['room'],
      schedule: (json['schedule'] as List? ?? const [])
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
      // Defensive: drop an unrecognised day rather than crashing the load or
      // defaulting to a wrong day (a class on the wrong weekday is worse than a
      // missing one).
      days: (json['days'] as List)
          .map((d) => DayOfWeek.values
              .cast<DayOfWeek?>()
              .firstWhere((e) => e.toString() == d, orElse: () => null))
          .whereType<DayOfWeek>()
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
      // Defensive: an unrecognised slot keeps the (correct) exam date rather
      // than failing the whole timetable load. FN is a neutral fallback.
      timeSlot: TimeSlot.values.firstWhere(
        (e) => e.toString() == json['timeSlot'],
        orElse: () => TimeSlot.FN,
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
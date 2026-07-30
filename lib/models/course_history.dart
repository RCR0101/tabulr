import '../utils/course_code.dart';
import '../utils/name_utils.dart';

/// Helpers for the `2026-27-1` term ids the history bundle is keyed on:
/// academic session, then the semester within it.
///
/// The format sorts chronologically as a plain string, which is why nothing
/// here parses one just to order it.
abstract final class Terms {
  /// `Sem 1 · 2026-27` — a chip, a column header, a filter label.
  static String label(String term) {
    final parts = term.split('-');
    if (parts.length != 3) return term;
    return 'Sem ${parts[2]} · ${parts[0]}-${parts[1]}';
  }

  /// `Sem 1 '26` — for the term strip, where the full session won't fit.
  static String tickLabel(String term) {
    final parts = term.split('-');
    if (parts.length != 3) return term;
    return "S${parts[2]} '${parts[0].substring(2)}";
  }

  /// How the gap between a term and the newest one reads to a student.
  ///
  /// Deliberately words the answer rather than printing a number: "this
  /// semester" is what someone scanning for "can I take it now" is looking for.
  static String relative(int termsAgo) => switch (termsAgo) {
        <= 0 => 'This semester',
        1 => 'Last semester',
        _ => '$termsAgo semesters ago',
      };

  /// An absolute semester count, so the distance between two terms is real
  /// elapsed semesters rather than how many happen to be on record.
  ///
  /// Null when the id is not a term. Two semesters a year, so the session's
  /// opening year doubles and the semester picks the half.
  static int? ordinal(String term) {
    final parts = term.split('-');
    if (parts.length != 3) return null;
    final start = int.tryParse(parts[0]);
    final semester = int.tryParse(parts[2]);
    if (start == null || semester == null) return null;
    return start * 2 + (semester - 1);
  }

  /// Real semesters from [from] to [to], or null if either is unparseable.
  ///
  /// The record has holes — Hyderabad's booklets jump from 2021-22 Sem 2 to
  /// 2024-25 Sem 1 — so counting positions in the recorded list reports a course
  /// last offered in 2021-22 as "5 semesters ago" when it is really 9.
  static int? distance(String from, String to) {
    final a = ordinal(from);
    final b = ordinal(to);
    if (a == null || b == null) return null;
    return b - a;
  }

  /// Whether [later] is the semester straight after [earlier] — i.e. nothing is
  /// missing from the record between them.
  static bool areConsecutive(String earlier, String later) =>
      distance(earlier, later) == 1;
}

/// One term's record for one course: that it ran, and who taught it.
class CourseOffering {
  const CourseOffering({
    required this.term,
    required this.instructors,
    required this.inCharge,
    required this.sections,
  });

  final String term;

  /// Distinct instructors, upper-cased: the app's canonical professor key.
  /// Includes [inCharge].
  final List<String> instructors;

  /// Whoever ran the course this term — the booklet marks them by CAPITALISING
  /// the name, which `build_term_offerings` reads before normalising.
  ///
  /// Usually one name, occasionally two, and sometimes none: 10 of the 333
  /// courses in the 2026-27 booklet print no capitalised instructor at all, so
  /// every caller has to render an empty list.
  final List<String> inCharge;

  final int sections;

  /// Instructors who were not in charge, in recorded order.
  List<String> get supporting =>
      [for (final name in instructors) if (!inCharge.contains(name)) name];

  static List<String> _names(dynamic raw) =>
      [for (final name in (raw as List?) ?? const []) name.toString()];

  factory CourseOffering.fromMap(String term, Map<String, dynamic> map) {
    return CourseOffering(
      term: term,
      instructors: _names(map['instructors']),
      inCharge: _names(map['ic']),
      sections: (map['sections'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Every term one course ran in, oldest first.
///
/// A course only appears in the history for terms it was actually offered in,
/// so the gaps in [offerings] are the answer to "is this coming back".
class CourseTimeline {
  CourseTimeline({required this.courseCode, required this.offerings});

  final String courseCode;

  /// Chronological, never empty, and only the terms this course ran in.
  ///
  /// Neither titles nor credits are in here — both live in courses_master, which
  /// is the app's only source of them, and the parsed titles are truncated at the
  /// first line of a wrapped cell anyway. Resolve with `CoursesMasterService`.
  final List<CourseOffering> offerings;

  String get lastOfferedTerm => offerings.last.term;
  String get firstOfferedTerm => offerings.first.term;
  int get timesOffered => offerings.length;

  /// Distinct instructors across every term, most recent first — which is the
  /// order that answers "who teaches this" rather than "who ever did".
  List<String> get instructors {
    final seen = <String>{};
    final names = <String>[];
    for (final offering in offerings.reversed) {
      for (final name in offering.instructors) {
        if (seen.add(name)) names.add(name);
      }
    }
    return names;
  }

  CourseOffering? offeringIn(String term) {
    for (final offering in offerings) {
      if (offering.term == term) return offering;
    }
    return null;
  }

  /// Real semesters elapsed since this course last ran; 0 means it is running
  /// now. Counts calendar semesters, not entries on record — the two differ
  /// wherever the booklet archive has a hole.
  int termsSinceOffered(List<String> terms) {
    if (terms.isEmpty) return 0;
    return Terms.distance(lastOfferedTerm, terms.last) ??
        terms.length - 1 - terms.indexOf(lastOfferedTerm);
  }

  /// True when the history has never seen this course before the newest term —
  /// as far as the record goes, it is new.
  bool isNewIn(List<String> terms) =>
      terms.isNotEmpty && firstOfferedTerm == terms.last;
}

/// Every course one instructor taught, and when.
class InstructorTimeline {
  InstructorTimeline({
    required this.name,
    required this.coursesByTerm,
    required this.inChargeByTerm,
  });

  /// Canonical, upper-cased — the same key Prof Chambers matches on.
  final String name;

  /// Term id to the course codes taught in it. Only terms they taught in.
  final Map<String, List<String>> coursesByTerm;

  /// The subset of [coursesByTerm] they were instructor-in-charge of — the
  /// difference between running a course and teaching a section of it.
  final Map<String, List<String>> inChargeByTerm;

  bool wasInChargeOf(String term, String courseCode) =>
      inChargeByTerm[term]?.contains(courseCode) ?? false;

  /// Distinct courses they have ever run, however many terms ago.
  late final Set<String> everInCharge = {
    for (final codes in inChargeByTerm.values) ...codes
  };

  late final String displayName = titleCaseName(name);

  /// Chronological.
  late final List<String> terms = coursesByTerm.keys.toList()..sort();

  String get lastActiveTerm => terms.last;

  late final List<String> courses = () {
    final seen = <String>{};
    // Reversed so the courses they teach now lead the list.
    for (final term in terms.reversed) {
      seen.addAll(coursesByTerm[term]!);
    }
    return seen.toList();
  }();

  int termsSinceActive(List<String> allTerms) {
    if (allTerms.isEmpty) return 0;
    return Terms.distance(lastActiveTerm, allTerms.last) ??
        allTerms.length - 1 - allTerms.indexOf(lastActiveTerm);
  }

  String get searchText => displayName.toLowerCase();
}

/// A campus's whole offering record, assembled from the history bundle.
class CourseHistory {
  const CourseHistory({
    required this.terms,
    required this.courses,
    required this.instructors,
  });

  static const empty =
      CourseHistory(terms: [], courses: [], instructors: []);

  /// Chronological. The last entry is the term the app currently holds a
  /// timetable for, which every "is it offered now" answer is relative to.
  final List<String> terms;

  /// Sorted by course code.
  final List<CourseTimeline> courses;

  /// Sorted by name.
  final List<InstructorTimeline> instructors;

  bool get isEmpty => terms.isEmpty;
  String? get currentTerm => terms.isEmpty ? null : terms.last;

  /// Builds the whole record from the bundle's term entries.
  ///
  /// The bundle is a list of `{term, courses: {docId: {...}}}`, one per term,
  /// written by `record_term_offerings` in `functions-python/main.py`. Both the
  /// course and instructor views are derived here in one pass — the screen
  /// needs to answer questions from both directions and the data is small
  /// enough (~38 KB a term) that indexing it up front beats scanning per query.
  factory CourseHistory.fromBundle(List<Map<String, dynamic>> entries) {
    final terms = <String>[];
    final offeringsByCourse = <String, List<CourseOffering>>{};
    final coursesByInstructor = <String, Map<String, List<String>>>{};
    final inChargeByInstructor = <String, Map<String, List<String>>>{};

    // Chronological regardless of how the bundle was ordered, because
    // "last offered" is read straight off the end of each course's list.
    final sorted = [...entries]..sort(
        (a, b) => (a['term'] as String).compareTo(b['term'] as String));

    for (final entry in sorted) {
      final term = entry['term'] as String;
      final courses = (entry['courses'] as Map?) ?? const {};
      if (courses.isEmpty) continue;
      terms.add(term);

      for (final course in courses.entries) {
        final code = docIdToCourseCode(course.key.toString());
        final offering = CourseOffering.fromMap(
            term, Map<String, dynamic>.from(course.value as Map));
        offeringsByCourse.putIfAbsent(code, () => []).add(offering);

        for (final name in offering.instructors) {
          coursesByInstructor
              .putIfAbsent(name, () => {})
              .putIfAbsent(term, () => [])
              .add(code);
        }
        for (final name in offering.inCharge) {
          inChargeByInstructor
              .putIfAbsent(name, () => {})
              .putIfAbsent(term, () => [])
              .add(code);
        }
      }
    }

    final courses = [
      for (final entry in offeringsByCourse.entries)
        CourseTimeline(courseCode: entry.key, offerings: entry.value)
    ]..sort((a, b) => a.courseCode.compareTo(b.courseCode));

    final instructors = [
      for (final entry in coursesByInstructor.entries)
        InstructorTimeline(
          name: entry.key,
          coursesByTerm: entry.value,
          inChargeByTerm: inChargeByInstructor[entry.key] ?? const {},
        )
    ]..sort((a, b) => a.name.compareTo(b.name));

    return CourseHistory(
        terms: terms, courses: courses, instructors: instructors);
  }
}

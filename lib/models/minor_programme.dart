import 'package:cloud_firestore/cloud_firestore.dart';

/// One course inside a minor's requirement list.
class MinorCourse {
  const MinorCourse({
    required this.code,
    this.title = '',
    this.units,
    this.alternatives = const [],
  });

  final String code;

  /// Equally acceptable substitutes, from Bulletin rows that read
  /// "PHY F212 or ECE F212 / EEE F212 / INSTR F212". Clearing any one of them
  /// satisfies the requirement, so progress must match on [codes], never on
  /// [code] alone.
  final List<String> alternatives;

  /// Every code that satisfies this requirement, preferred one first.
  List<String> get codes => [code, ...alternatives];

  /// Filled in from the course master when the catalogue loads, not persisted
  /// — see [toMap]. Empty for a code the catalogue doesn't carry.
  final String title;

  /// Null where the Bulletin omits or footnotes the unit count.
  ///
  /// Kept in the document rather than read off the course master: the Bulletin
  /// states a minor's requirement in units, while the master carries the credit
  /// count of the current offering. They usually agree, but they answer
  /// different questions and the 15-unit minimum is the Bulletin's.
  final int? units;

  /// Still reads a stored `title` so documents written before titles were
  /// dropped keep working until their next save.
  factory MinorCourse.fromMap(Map<String, dynamic> map) => MinorCourse(
        code: (map['code'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        units: (map['units'] as num?)?.toInt(),
        alternatives: ((map['alternatives'] as List<dynamic>?) ?? [])
            .map((a) => a.toString())
            .toList(),
      );

  /// No title: it belongs to the course master, which carries the same ~2,800
  /// courses for every campus. Storing a copy here only created something that
  /// could drift out of date.
  Map<String, dynamic> toMap() => {
        'code': code,
        if (units != null) 'units': units,
        if (alternatives.isNotEmpty) 'alternatives': alternatives,
      };

  MinorCourse copyWith({
    String? code,
    String? title,
    int? units,
    List<String>? alternatives,
  }) =>
      MinorCourse(
        code: code ?? this.code,
        title: title ?? this.title,
        units: units ?? this.units,
        alternatives: alternatives ?? this.alternatives,
      );
}

/// A named bucket of courses within a minor — "Core Courses", "Electives",
/// or a discipline-specific pool. The Bulletin varies the naming per minor, so
/// this is a free-form label rather than an enum.
class MinorCourseGroup {
  const MinorCourseGroup({
    required this.name,
    required this.courses,
    this.required,
  });

  final String name;
  final List<MinorCourse> courses;

  /// How many of [courses] must be cleared. Equal to `courses.length` for a
  /// core group, where every listed course is mandatory; smaller for an
  /// elective group, where you pick from the pool.
  ///
  /// Null where the Bulletin states only a combined figure — English Studies
  /// gives two elective pools and one total across both, so neither pool has a
  /// minimum of its own. Callers must treat null as "unknown", not zero.
  final int? required;

  /// True for a group you must clear outright, which is what "core" means in
  /// practice regardless of the label the Bulletin used.
  bool get isMandatory => required != null && required! >= courses.length;

  factory MinorCourseGroup.fromMap(Map<String, dynamic> map) =>
      MinorCourseGroup(
        name: (map['name'] ?? '').toString(),
        courses: ((map['courses'] as List<dynamic>?) ?? [])
            .map((c) => MinorCourse.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList(),
        required: (map['required'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'courses': courses.map((c) => c.toMap()).toList(),
        if (required != null) 'required': required,
      };

  MinorCourseGroup copyWith({
    String? name,
    List<MinorCourse>? courses,
    int? required,
  }) =>
      MinorCourseGroup(
        name: name ?? this.name,
        courses: courses ?? this.courses,
        required: required ?? this.required,
      );
}

/// Where a minor sits in the admin verification workflow.
///
/// Seeded records import as [notVerified]; an admin moves them through
/// [inReview] to [verified] once the groupings have been checked against the
/// Bulletin. Persisted as [name]; documents that predate this and only stored
/// the `needsReview` bool map true → [notVerified], false → [verified].
enum MinorStatus {
  notVerified('Not verified'),
  inReview('In review'),
  verified('Verified');

  const MinorStatus(this.label);

  final String label;

  static MinorStatus fromData(Map<String, dynamic> data) {
    final raw = data['status'];
    if (raw is String) {
      for (final s in MinorStatus.values) {
        if (s.name == raw) return s;
      }
    }
    return data['needsReview'] == true ? notVerified : verified;
  }
}

/// A minor programme as published in the Bulletin.
///
/// Stored in Firestore rather than compiled in, because the Bulletin is
/// reissued annually and the seed data is imperfect — the course groupings come
/// from a PDF table whose labels are vertically centred, so boundaries need
/// human correction. Admins edit these in the Minor Management screen.
class MinorProgramme {
  const MinorProgramme({
    required this.id,
    required this.name,
    this.description = '',
    this.minCourses,
    this.minUnits,
    this.groups = const [],
    this.campuses = const [],
    this.status = MinorStatus.verified,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;

  /// Minimum courses and units the minor itself demands. The institute-wide
  /// floor is 5 courses / 15 units (Bulletin, Part IV).
  final int? minCourses;
  final int? minUnits;

  final List<MinorCourseGroup> groups;

  /// Campus codes where this minor is offered. Empty means "not specified" and
  /// the UI shows it everywhere rather than hiding it.
  final List<String> campuses;

  /// Admin verification state. Seeded records start [MinorStatus.notVerified].
  final MinorStatus status;

  /// Anything not yet [MinorStatus.verified] is still on the review queue.
  bool get needsReview => status != MinorStatus.verified;

  final DateTime? updatedAt;

  int get courseCount =>
      groups.fold<int>(0, (total, g) => total + g.courses.length);

  /// Courses you have no choice about — the core groups, summed.
  int get mandatoryCourses => groups
      .where((g) => g.isMandatory)
      .fold<int>(0, (total, g) => total + g.courses.length);

  /// Courses you pick yourself: whatever the minimum leaves over once the
  /// mandatory ones are counted. Null when the split can't be worked out,
  /// which is the case until an admin has marked the core groups — the UI
  /// then falls back to the plain course minimum.
  int? get electiveCourses {
    if (minCourses == null || !groups.any((g) => g.isMandatory)) return null;
    final remaining = minCourses! - mandatoryCourses;
    return remaining < 0 ? null : remaining;
  }

  bool offeredAt(String? campusCode) =>
      campuses.isEmpty || campusCode == null || campuses.contains(campusCode);

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        groups.any((g) => g.courses.any((c) =>
            c.code.toLowerCase().contains(q) ||
            c.title.toLowerCase().contains(q)));
  }

  factory MinorProgramme.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MinorProgramme(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      minCourses: (data['minCourses'] as num?)?.toInt(),
      minUnits: (data['minUnits'] as num?)?.toInt(),
      groups: ((data['groups'] as List<dynamic>?) ?? [])
          .map((g) =>
              MinorCourseGroup.fromMap(Map<String, dynamic>.from(g as Map)))
          .toList(),
      campuses: ((data['campuses'] as List<dynamic>?) ?? [])
          .map((c) => c.toString())
          .toList(),
      status: MinorStatus.fromData(data),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        if (minCourses != null) 'minCourses': minCourses,
        if (minUnits != null) 'minUnits': minUnits,
        'groups': groups.map((g) => g.toMap()).toList(),
        'campuses': campuses,
        'status': status.name,
        // Derived, kept so an older app build still reads a review flag.
        'needsReview': needsReview,
      };

  MinorProgramme copyWith({
    String? name,
    String? description,
    int? minCourses,
    int? minUnits,
    List<MinorCourseGroup>? groups,
    List<String>? campuses,
    MinorStatus? status,
  }) =>
      MinorProgramme(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        minCourses: minCourses ?? this.minCourses,
        minUnits: minUnits ?? this.minUnits,
        groups: groups ?? this.groups,
        campuses: campuses ?? this.campuses,
        status: status ?? this.status,
        updatedAt: updatedAt,
      );
}

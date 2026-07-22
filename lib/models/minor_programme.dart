import 'package:cloud_firestore/cloud_firestore.dart';

/// One course inside a minor's requirement list.
class MinorCourse {
  const MinorCourse({
    required this.code,
    this.title = '',
    this.units,
  });

  final String code;

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
      );

  /// No title: it belongs to the course master, which carries the same ~2,800
  /// courses for every campus. Storing a copy here only created something that
  /// could drift out of date.
  Map<String, dynamic> toMap() => {
        'code': code,
        if (units != null) 'units': units,
      };

  MinorCourse copyWith({String? code, String? title, int? units}) =>
      MinorCourse(
        code: code ?? this.code,
        title: title ?? this.title,
        units: units ?? this.units,
      );
}

/// A named bucket of courses within a minor — "Core Courses", "Electives",
/// or a discipline-specific pool. The Bulletin varies the naming per minor, so
/// this is a free-form label rather than an enum.
class MinorCourseGroup {
  const MinorCourseGroup({required this.name, required this.courses});

  final String name;
  final List<MinorCourse> courses;

  factory MinorCourseGroup.fromMap(Map<String, dynamic> map) =>
      MinorCourseGroup(
        name: (map['name'] ?? '').toString(),
        courses: ((map['courses'] as List<dynamic>?) ?? [])
            .map((c) => MinorCourse.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'courses': courses.map((c) => c.toMap()).toList(),
      };

  MinorCourseGroup copyWith({String? name, List<MinorCourse>? courses}) =>
      MinorCourseGroup(
        name: name ?? this.name,
        courses: courses ?? this.courses,
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

/// User-set defaults reused across the app (exam seating ID, CDC auto-load,
/// discipline/humanities electives, quick replace, …). All fields are optional
/// so a profile can be filled in incrementally.
class UserProfile {
  /// BITS campus ID, e.g. `2023A7PS0123H`.
  final String studentId;

  /// Primary branch code (keys of `branchCodeToName`, e.g. `A7`).
  final String? primaryBranch;

  /// Secondary branch code for dual-degree students, or null.
  final String? secondaryBranch;

  /// Current year-semester, e.g. `2-1` (matches the CDC loader's values).
  final String? currentSemester;

  const UserProfile({
    this.studentId = '',
    this.primaryBranch,
    this.secondaryBranch,
    this.currentSemester,
  });

  static const empty = UserProfile();

  bool get isEmpty =>
      studentId.isEmpty &&
      primaryBranch == null &&
      secondaryBranch == null &&
      currentSemester == null;

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    String? nn(dynamic v) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    return UserProfile(
      studentId: (map['studentId'] as String?)?.trim() ?? '',
      primaryBranch: nn(map['primaryBranch']),
      secondaryBranch: nn(map['secondaryBranch']),
      currentSemester: nn(map['currentSemester']),
    );
  }

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'primaryBranch': primaryBranch,
        'secondaryBranch': secondaryBranch,
        'currentSemester': currentSemester,
      };

  UserProfile copyWith({
    String? studentId,
    String? primaryBranch,
    String? secondaryBranch,
    String? currentSemester,
    bool clearSecondaryBranch = false,
  }) {
    return UserProfile(
      studentId: studentId ?? this.studentId,
      primaryBranch: primaryBranch ?? this.primaryBranch,
      secondaryBranch:
          clearSecondaryBranch ? null : (secondaryBranch ?? this.secondaryBranch),
      currentSemester: currentSemester ?? this.currentSemester,
    );
  }
}

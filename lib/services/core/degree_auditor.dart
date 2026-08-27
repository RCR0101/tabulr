import '../../models/academic_record.dart';
import '../../models/cdc_slot.dart';

/// Where the student stands on one core (CDC) requirement.
enum CoreStatus {
  /// An option of the slot has been passed.
  cleared,

  /// Every option attempted so far was failed, and none passed — needs a retake.
  failed,

  /// Not attempted yet.
  pending,
}

/// One core requirement of the degree and the student's standing on it.
class CoreRequirement {
  final String semester; // e.g. '3-1'
  final CdcSlot slot; // choices intact
  final CoreStatus status;

  /// For a choice slot that's cleared, which option actually satisfied it.
  final String? clearedBy;

  const CoreRequirement({
    required this.semester,
    required this.slot,
    required this.status,
    this.clearedBy,
  });
}

/// A student's standing against their degree's core requirements, plus how many
/// electives they've already cleared.
///
/// Scope is deliberately core-only + earned elective *counts*: the branch data
/// carries the CDC lists and elective pools, but not the required elective
/// counts/credits to graduate — so this never claims "N electives remaining",
/// which would be invented. See [[tabulr-next-gen-roadmap]] P1.
class DegreeAudit {
  final List<CoreRequirement> requirements; // semester order, then listed order
  final int clearedDels;
  final int clearedHuels;

  const DegreeAudit({
    required this.requirements,
    this.clearedDels = 0,
    this.clearedHuels = 0,
  });

  Iterable<CoreRequirement> _where(CoreStatus s) =>
      requirements.where((r) => r.status == s);

  int get total => requirements.length;
  int get cleared => _where(CoreStatus.cleared).length;
  int get failed => _where(CoreStatus.failed).length;
  int get pending => _where(CoreStatus.pending).length;

  List<CoreRequirement> get failedRequirements => _where(CoreStatus.failed).toList();
  List<CoreRequirement> get pendingRequirements =>
      _where(CoreStatus.pending).toList();

  bool get coreComplete => total > 0 && cleared == total;
  double get fractionCleared => total == 0 ? 0 : cleared / total;

  /// Requirements grouped by semester, in the order semesters first appear.
  Map<String, List<CoreRequirement>> get bySemester {
    final out = <String, List<CoreRequirement>>{};
    for (final r in requirements) {
      (out[r.semester] ??= []).add(r);
    }
    return out;
  }
}

/// Diffs a transcript against a degree's core requirements — the P1 graduation
/// audit engine. Pure and offline: the screen fetches the branch data and record,
/// this decides the standing.
class DegreeAuditor {
  const DegreeAuditor._();

  static DegreeAudit audit({
    required Map<String, List<CdcSlot>> cdcsBySemester,
    required AcademicRecord record,
    Iterable<String> dels = const [],
    Iterable<String> huels = const [],
  }) {
    final reqs = <CoreRequirement>[];
    for (final entry in cdcsBySemester.entries) {
      for (final slot in entry.value) {
        final passed = slot.options.where(record.hasPassed).toList();
        final CoreStatus status;
        String? clearedBy;
        if (passed.isNotEmpty) {
          status = CoreStatus.cleared;
          clearedBy = passed.first;
        } else if (slot.options.any(record.hasFailed)) {
          status = CoreStatus.failed;
        } else {
          status = CoreStatus.pending;
        }
        reqs.add(CoreRequirement(
          semester: entry.key,
          slot: slot,
          status: status,
          clearedBy: clearedBy,
        ));
      }
    }
    return DegreeAudit(
      requirements: reqs,
      clearedDels: dels.where(record.hasPassed).length,
      clearedHuels: huels.where(record.hasPassed).length,
    );
  }
}

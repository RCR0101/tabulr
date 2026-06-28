import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';
import '../../models/branch_group.dart';
import '../../utils/branch_constants.dart' as constants;
import 'branch_structure_service.dart';

export '../../models/branch_group.dart';

/// Persists and resolves admin-defined branch groups.
///
/// Groups are stored in a single document `reference/branches/data/_groups`
/// (the same writable area the Course Guide admin already uses). Saving a set
/// of groups also propagates each group's first-year CDCs down to its member
/// branch documents, so the public Course Guide — which reads per-branch
/// `cdcs` — reflects the grouping without any further changes.
class BranchGroupService {
  static final BranchGroupService _instance = BranchGroupService._();
  factory BranchGroupService() => _instance;
  BranchGroupService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final BranchStructureService _branchService = BranchStructureService();

  /// Doc id that holds the group definitions. Underscore-prefixed so it is
  /// ignored by branch-listing code (the public branch list comes from
  /// `_metadata.branches`).
  static const String groupsDocId = '_groups';
  static const String sem11 = '1-1';
  static const String sem12 = '1-2';

  CollectionReference<Map<String, dynamic>> get _branchesRef => _firestore
      .collection(FirestoreCollections.reference)
      .doc(FirestoreCollections.branches)
      .collection(FirestoreCollections.data);

  /// Load the saved groups. If none exist yet, bootstrap an initial set by
  /// clustering current branches by their first-year CDC signature so the
  /// admin starts from the real data instead of a blank slate. The bootstrap
  /// is *not* persisted until the admin saves.
  Future<List<BranchGroup>> loadGroups() async {
    final doc = await _branchesRef.doc(groupsDocId).get();
    final raw = doc.data()?['groups'] as List?;
    if (raw != null && raw.isNotEmpty) {
      final groups = raw
          .map((g) => BranchGroup.fromMap(Map<String, dynamic>.from(g as Map)))
          .toList();
      return _reconcileBranches(groups);
    }
    return _reconcileBranches(await _bootstrapFromSignatures());
  }

  /// Build groups from current per-branch first-year CDCs.
  Future<List<BranchGroup>> _bootstrapFromSignatures() async {
    final snap = await _branchesRef.get();
    final bySignature = <String, BranchGroup>{};
    var index = 0;
    for (final doc in snap.docs) {
      final code = doc.id;
      if (!constants.branchCodeToName.containsKey(code)) continue;
      final cdcs = doc.data()['cdcs'] as Map<String, dynamic>? ?? {};
      final s11 = List<String>.from(cdcs[sem11] as List? ?? [])..sort();
      final s12 = List<String>.from(cdcs[sem12] as List? ?? [])..sort();
      final signature = '${s11.join(',')}||${s12.join(',')}';

      final existing = bySignature[signature];
      if (existing != null) {
        existing.branches.add(code);
      } else {
        bySignature[signature] = BranchGroup(
          id: 'g${DateTime.now().millisecondsSinceEpoch}_$index',
          name: 'Group ${String.fromCharCode(65 + index)}',
          sem11: s11,
          sem12: s12,
          branches: [code],
        );
        index++;
      }
    }
    return bySignature.values.toList();
  }

  /// Ensure every known branch appears in exactly one group's branch list, and
  /// no group references an unknown branch code. Unassigned branches are left
  /// out (surfaced as "ungrouped" by the UI).
  List<BranchGroup> _reconcileBranches(List<BranchGroup> groups) {
    final seen = <String>{};
    for (final g in groups) {
      g.branches = g.branches
          .where((c) =>
              constants.branchCodeToName.containsKey(c) && seen.add(c))
          .toList();
    }
    return groups;
  }

  /// Branch codes not assigned to any group.
  List<String> ungroupedBranches(List<BranchGroup> groups) {
    final assigned = groups.expand((g) => g.branches).toSet();
    return constants.branchCodeToName.keys
        .where((c) => !assigned.contains(c))
        .toList()
      ..sort();
  }

  /// Persist the groups document and propagate each group's first-year CDCs to
  /// its member branch docs. Other semesters on each branch are preserved
  /// (deep merge replaces only the 1-1 / 1-2 arrays).
  Future<void> saveGroups(List<BranchGroup> groups) async {
    final batch = _firestore.batch();

    final now = DateTime.now().toIso8601String();

    batch.set(_branchesRef.doc(groupsDocId), {
      'groups': groups.map((g) => g.toMap()).toList(),
      'updated_at': now,
    });

    for (final group in groups) {
      for (final code in group.branches) {
        batch.set(
          _branchesRef.doc(code),
          {
            'branch_code': code,
            'cdcs': {sem11: group.sem11, sem12: group.sem12},
          },
          SetOptions(merge: true),
        );
      }
    }

    // Bump the freshness marker so other devices' cached branch data is
    // treated as stale on next open (see LocalCacheService.readIfFresh).
    batch.set(
      _branchesRef.doc('_metadata'),
      {'lastUpdated': now},
      SetOptions(merge: true),
    );

    await batch.commit();
    // Course Guide caches branch data; invalidate so students see the change.
    _branchService.clearCache();
  }
}

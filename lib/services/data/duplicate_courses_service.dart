import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';

/// Reads and writes the course-equivalence mappings stored at
/// `reference/duplicate_courses`.
///
/// Firestore stores a reverse `codeMap` — each course code maps to the list of
/// codes considered duplicates of it. For editing, that's awkward, so this
/// service exposes the data as **equivalence groups** (a set of codes that are
/// all duplicates of one another) and serializes back to the same `codeMap`
/// shape the upload script produces, keeping it compatible.
class DuplicateCoursesService {
  static final DuplicateCoursesService _instance =
      DuplicateCoursesService._();
  factory DuplicateCoursesService() => _instance;
  DuplicateCoursesService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _docRef => _firestore
      .collection(FirestoreCollections.reference)
      .doc('duplicate_courses');

  /// Load equivalence groups by computing connected components over the
  /// reverse `codeMap`. Each returned group is a sorted list of ≥2 codes.
  Future<List<List<String>>> loadGroups() async {
    final snap = await _docRef.get();
    final raw = snap.data()?['codeMap'] as Map<String, dynamic>? ?? {};

    // Build an undirected adjacency list.
    final adj = <String, Set<String>>{};
    void link(String a, String b) {
      adj.putIfAbsent(a, () => {}).add(b);
      adj.putIfAbsent(b, () => {}).add(a);
    }

    for (final entry in raw.entries) {
      final code = entry.key;
      adj.putIfAbsent(code, () => {});
      for (final other in List<String>.from(entry.value as List? ?? [])) {
        link(code, other);
      }
    }

    // Connected components.
    final visited = <String>{};
    final groups = <List<String>>[];
    for (final node in adj.keys) {
      if (visited.contains(node)) continue;
      final stack = [node];
      final component = <String>[];
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        if (!visited.add(cur)) continue;
        component.add(cur);
        stack.addAll(adj[cur]!.where((n) => !visited.contains(n)));
      }
      if (component.length >= 2) {
        component.sort();
        groups.add(component);
      }
    }
    groups.sort((a, b) => a.first.compareTo(b.first));
    return groups;
  }

  /// Persist equivalence groups, rebuilding the reverse `codeMap`. Groups with
  /// fewer than 2 codes are dropped.
  Future<void> saveGroups(List<List<String>> groups) async {
    final codeMap = <String, List<String>>{};
    for (final group in groups) {
      final unique = group.toSet().toList();
      if (unique.length < 2) continue;
      for (final code in unique) {
        codeMap[code] = unique.where((c) => c != code).toList();
      }
    }

    await _docRef.set({
      'codeMap': codeMap,
      'lastUpdated': DateTime.now().toIso8601String(),
      'version': '1.0.0',
    });
  }
}

/// An admin-defined group that segments first-year CDCs.
///
/// A group owns the CDC lists for the first two semesters (1-1 and 1-2) and
/// the set of branches assigned to it. Every member branch inherits the
/// group's first-year CDCs — that's how groups "segment" the Course Guide.
///
/// A branch belongs to at most one group. Branches that aren't in any group
/// are treated as "ungrouped" by the admin UI.
class BranchGroup {
  String id;
  String name;
  List<String> sem11;
  List<String> sem12;
  List<String> branches;

  BranchGroup({
    required this.id,
    required this.name,
    required this.sem11,
    required this.sem12,
    required this.branches,
  });

  factory BranchGroup.fromMap(Map<String, dynamic> data) {
    return BranchGroup(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      sem11: List<String>.from(data['1-1'] as List? ?? []),
      sem12: List<String>.from(data['1-2'] as List? ?? []),
      branches: List<String>.from(data['branches'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        '1-1': sem11,
        '1-2': sem12,
        'branches': branches,
      };

  BranchGroup copy() => BranchGroup(
        id: id,
        name: name,
        sem11: List<String>.from(sem11),
        sem12: List<String>.from(sem12),
        branches: List<String>.from(branches),
      );
}

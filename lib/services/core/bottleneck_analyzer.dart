/// When in the year a course actually runs, read from its offering history.
enum OfferingParity {
  /// Only ever seen in first-semester (odd) terms.
  sem1Only,

  /// Only ever seen in second-semester (even) terms.
  sem2Only,

  /// Runs in both — no timing constraint.
  both,

  /// No offering history on record.
  unknown,
}

extension OfferingParityX on OfferingParity {
  bool get isConstrained =>
      this == OfferingParity.sem1Only || this == OfferingParity.sem2Only;

  String get label => switch (this) {
        OfferingParity.sem1Only => 'Sem 1 only',
        OfferingParity.sem2Only => 'Sem 2 only',
        OfferingParity.both => 'Both semesters',
        OfferingParity.unknown => 'No history',
      };
}

/// A remaining core that both runs in only one semester of the year and gates
/// other remaining cores — the courses to slot early or risk slipping a year.
class CourseBottleneck {
  final String code;
  final OfferingParity parity;

  /// How many still-to-do cores depend on it, directly or transitively.
  final int gatesDownstream;

  const CourseBottleneck({
    required this.code,
    required this.parity,
    required this.gatesDownstream,
  });
}

class BottleneckReport {
  /// Single-parity cores that gate ≥1 remaining core, worst (most gated) first.
  final List<CourseBottleneck> bottlenecks;

  /// The longest prerequisite chain among the remaining cores — the structural
  /// floor on how many semesters the rest of the degree still takes.
  final List<String> criticalPath;

  const BottleneckReport({
    required this.bottlenecks,
    required this.criticalPath,
  });

  int get criticalPathLength => criticalPath.length;
}

/// P2: finds the timing bottlenecks in what's left of a degree.
///
/// Pure and deterministic — no scheduling, no crowd data. Given the remaining
/// cores, when each runs, and the prereq edges between them, it names the
/// single-semester courses that gate the most downstream work and the longest
/// prereq chain still ahead. The screen supplies the data; this does the graph.
class BottleneckAnalyzer {
  const BottleneckAnalyzer._();

  /// Offering parity from the set of term ids (`YYYY-YY-S`) a course ran in.
  static OfferingParity parityOf(Iterable<String> terms) {
    var s1 = false, s2 = false;
    for (final t in terms) {
      final parts = t.split('-');
      if (parts.length != 3) continue;
      if (parts[2] == '1') s1 = true;
      if (parts[2] == '2') s2 = true;
    }
    if (s1 && s2) return OfferingParity.both;
    if (s1) return OfferingParity.sem1Only;
    if (s2) return OfferingParity.sem2Only;
    return OfferingParity.unknown;
  }

  static BottleneckReport analyze({
    required Set<String> remaining,
    required Map<String, OfferingParity> parity,
    required Map<String, Set<String>> prereqEdges, // course -> its prerequisites
  }) {
    // Successor edges (prereq -> dependent), restricted to the remaining cores.
    final successors = {for (final c in remaining) c: <String>{}};
    for (final c in remaining) {
      for (final p in prereqEdges[c] ?? const <String>{}) {
        if (remaining.contains(p)) successors[p]!.add(c);
      }
    }

    // Transitive descendants, memoized. `path` guards against a cyclic prereq
    // definition (shouldn't happen, but a bad edge must not hang the app).
    final descendants = <String, Set<String>>{};
    Set<String> descendantsOf(String node, Set<String> path) {
      final cached = descendants[node];
      if (cached != null) return cached;
      if (!path.add(node)) return const {}; // cycle: break
      final out = <String>{};
      for (final next in successors[node]!) {
        out.add(next);
        out.addAll(descendantsOf(next, path));
      }
      path.remove(node);
      descendants[node] = out;
      return out;
    }

    final bottlenecks = <CourseBottleneck>[];
    for (final c in remaining) {
      final gated = descendantsOf(c, <String>{}).length;
      final p = parity[c] ?? OfferingParity.unknown;
      if (p.isConstrained && gated > 0) {
        bottlenecks.add(
            CourseBottleneck(code: c, parity: p, gatesDownstream: gated));
      }
    }
    bottlenecks.sort((a, b) {
      final byGated = b.gatesDownstream.compareTo(a.gatesDownstream);
      return byGated != 0 ? byGated : a.code.compareTo(b.code);
    });

    // Longest prereq chain (node count), memoized over the same DAG.
    final longestFrom = <String, List<String>>{};
    List<String> longestPathFrom(String node, Set<String> path) {
      final cached = longestFrom[node];
      if (cached != null) return cached;
      if (!path.add(node)) return [node]; // cycle guard
      var best = <String>[];
      for (final next in successors[node]!) {
        final sub = longestPathFrom(next, path);
        if (sub.length > best.length) best = sub;
      }
      path.remove(node);
      final result = [node, ...best];
      longestFrom[node] = result;
      return result;
    }

    var critical = <String>[];
    for (final c in remaining) {
      final path = longestPathFrom(c, <String>{});
      if (path.length > critical.length) critical = path;
    }

    return BottleneckReport(bottlenecks: bottlenecks, criticalPath: critical);
  }
}

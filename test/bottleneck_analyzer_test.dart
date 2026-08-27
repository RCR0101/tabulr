import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/core/bottleneck_analyzer.dart';

void main() {
  group('BottleneckAnalyzer.parityOf', () {
    test('reads the semester digit of the term id', () {
      expect(BottleneckAnalyzer.parityOf(['2024-25-1', '2025-26-1']),
          OfferingParity.sem1Only);
      expect(BottleneckAnalyzer.parityOf(['2024-25-2']), OfferingParity.sem2Only);
      expect(BottleneckAnalyzer.parityOf(['2024-25-1', '2024-25-2']),
          OfferingParity.both);
      expect(BottleneckAnalyzer.parityOf(const []), OfferingParity.unknown);
    });
  });

  group('BottleneckAnalyzer.analyze', () {
    // Chain A -> B -> C, and standalone D. B and A run in one semester only.
    final report = BottleneckAnalyzer.analyze(
      remaining: {'A', 'B', 'C', 'D'},
      parity: {
        'A': OfferingParity.sem2Only,
        'B': OfferingParity.sem1Only,
        'C': OfferingParity.both,
        'D': OfferingParity.sem1Only, // constrained but gates nothing
      },
      prereqEdges: {
        'B': {'A'},
        'C': {'B'},
      },
    );

    test('bottlenecks are single-parity cores that gate downstream, worst first', () {
      expect(report.bottlenecks.map((b) => b.code), ['A', 'B']);
      // A gates B and C (transitive); B gates C. D gates nothing -> excluded.
      expect(report.bottlenecks[0].gatesDownstream, 2);
      expect(report.bottlenecks[1].gatesDownstream, 1);
    });

    test('critical path is the longest prereq chain', () {
      expect(report.criticalPath, ['A', 'B', 'C']);
      expect(report.criticalPathLength, 3);
    });

    test('edges to courses outside the remaining set are ignored', () {
      // A already cleared (not remaining): B is no longer gated by anything.
      final r = BottleneckAnalyzer.analyze(
        remaining: {'B', 'C'},
        parity: {'B': OfferingParity.sem1Only, 'C': OfferingParity.both},
        prereqEdges: {
          'B': {'A'}, // A not in remaining -> dropped
          'C': {'B'},
        },
      );
      expect(r.bottlenecks.single.code, 'B');
      expect(r.bottlenecks.single.gatesDownstream, 1);
      expect(r.criticalPath, ['B', 'C']);
    });

    test('a cyclic prereq definition does not hang', () {
      final r = BottleneckAnalyzer.analyze(
        remaining: {'X', 'Y'},
        parity: {'X': OfferingParity.both, 'Y': OfferingParity.both},
        prereqEdges: {
          'X': {'Y'},
          'Y': {'X'},
        },
      );
      expect(r.criticalPath, isNotEmpty); // returns rather than looping forever
    });
  });
}

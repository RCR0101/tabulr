import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/constants/app_constants.dart';
import 'package:timetable_maker/models/campus.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/core/undo_redo_service.dart';
import '../helpers/test_data.dart';
import '../helpers/test_reporter.dart';

/// Soak test for [UndoRedoService].
///
/// undo_redo_service_test.dart covers the specific behaviours; this drives
/// thousands of random push/undo/redo sequences against an independent
/// two-stack reference model and asserts the service's observable state
/// (canUndo/canRedo, descriptions, and every restored snapshot) matches at
/// every step — while proving the undo stack stays bounded and the redo stack
/// is dropped on each new edit.
void main() {
  final results = <Map<String, dynamic>>[];
  void record(String name, bool passed, int ms, [String? error]) {
    results.add({
      'name': name,
      'status': passed ? 'pass' : 'fail',
      'duration_ms': ms,
      if (error != null) 'error': error,
    });
  }

  tearDownAll(() async {
    await TestReporter.reportTestResults('undo_redo_soak', results);
  });

  test('random push/undo/redo sequences match a reference model', () {
    final sw = Stopwatch()..start();
    const trials = 200;
    const opsPerTrial = 80;
    try {
      for (var t = 0; t < trials; t++) {
        _runTrial(Random(0xBEEF + t), opsPerTrial, t);
      }
      sw.stop();
      record('random sequences vs reference', true, sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      record('random sequences vs reference', false, sw.elapsedMilliseconds,
          e.toString());
      rethrow;
    }
  });

  test('undo stack never exceeds maxUndoStackSize', () {
    final sw = Stopwatch()..start();
    final service = UndoRedoService();
    for (var i = 0; i < AppLimits.maxUndoStackSize + 37; i++) {
      service.pushSections(const [], 'edit$i');
    }
    var undos = 0;
    while (service.canUndo && undos <= AppLimits.maxUndoStackSize + 100) {
      service.undo(_tt(const []));
      undos++;
    }
    expect(undos, AppLimits.maxUndoStackSize);
    sw.stop();
    record('bounded stack', true, sw.elapsedMilliseconds);
  });

  test('undo then redo restores the same state (round-trip)', () {
    final service = UndoRedoService();
    var current = <SelectedSection>[];
    final history = <List<String>>[];

    for (var i = 0; i < 20; i++) {
      history.add(_keys(current));
      service.pushSections(current, 'e$i');
      current = [...current, _sec(i, 0)];
    }
    final atEnd = _keys(current);

    // Undo everything, then redo everything.
    while (service.canUndo) {
      current = service.undo(_tt(current))!.sections;
    }
    while (service.canRedo) {
      current = service.redo(_tt(current))!.sections;
    }
    expect(_keys(current), atEnd);
  });
}

void _runTrial(Random r, int ops, int trial) {
  final service = UndoRedoService();
  var current = <SelectedSection>[];

  // Reference model: parallel undo/redo stacks of (sectionKeys, description).
  final refUndo = <({List<String> keys, String desc})>[];
  final refRedo = <({List<String> keys, String desc})>[];

  for (var step = 0; step < ops; step++) {
    final choice = r.nextInt(10);
    if (choice < 6) {
      // ── Edit: capture the pre-edit state, push it, then mutate.
      final desc = 'op$step';
      service.pushSections(current, desc);
      refUndo.add((keys: _keys(current), desc: desc));
      if (refUndo.length > AppLimits.maxUndoStackSize) refUndo.removeAt(0);
      refRedo.clear();
      current = _mutate(current, r);
    } else if (choice < 8) {
      // ── Undo.
      if (service.canUndo) {
        final snap = service.undo(_tt(current))!;
        refRedo.add((keys: _keys(current), desc: refUndo.last.desc));
        final expected = refUndo.removeLast();
        expect(_keys(snap.sections), expected.keys,
            reason: 'trial=$trial step=$step undo sections');
        expect(snap.description, expected.desc,
            reason: 'trial=$trial step=$step undo desc');
        current = snap.sections;
      } else {
        expect(refUndo, isEmpty, reason: 'trial=$trial step=$step');
        expect(service.undo(_tt(current)), isNull);
      }
    } else {
      // ── Redo.
      if (service.canRedo) {
        final snap = service.redo(_tt(current))!;
        refUndo.add((keys: _keys(current), desc: refRedo.last.desc));
        final expected = refRedo.removeLast();
        expect(_keys(snap.sections), expected.keys,
            reason: 'trial=$trial step=$step redo sections');
        expect(snap.description, expected.desc,
            reason: 'trial=$trial step=$step redo desc');
        current = snap.sections;
      } else {
        expect(refRedo, isEmpty, reason: 'trial=$trial step=$step');
        expect(service.redo(_tt(current)), isNull);
      }
    }

    // Observable state must track the reference after every operation.
    expect(service.canUndo, refUndo.isNotEmpty,
        reason: 'trial=$trial step=$step canUndo');
    expect(service.canRedo, refRedo.isNotEmpty,
        reason: 'trial=$trial step=$step canRedo');
    expect(service.undoDescription, refUndo.isEmpty ? null : refUndo.last.desc,
        reason: 'trial=$trial step=$step undoDescription');
    expect(service.redoDescription, refRedo.isEmpty ? null : refRedo.last.desc,
        reason: 'trial=$trial step=$step redoDescription');
  }
}

List<SelectedSection> _mutate(List<SelectedSection> cur, Random r) {
  final next = [...cur];
  if (next.isNotEmpty && r.nextBool()) {
    next.removeAt(r.nextInt(next.length));
  } else {
    next.add(_sec(r.nextInt(20), r.nextInt(5)));
  }
  return next;
}

SelectedSection _sec(int c, int s) =>
    makeSelectedSection(courseCode: 'C$c', sectionId: 'S$s');

List<String> _keys(List<SelectedSection> s) =>
    s.map((e) => '${e.courseCode}-${e.sectionId}').toList();

Timetable _tt(List<SelectedSection> sel) => Timetable(
      id: 't',
      name: 't',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      campus: Campus.values.first,
      availableCourses: const [],
      selectedSections: sel,
      clashWarnings: const [],
    );

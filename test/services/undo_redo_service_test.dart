import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/timetable.dart';
import 'package:timetable_maker/services/core/undo_redo_service.dart';
import 'package:timetable_maker/services/data/campus_service.dart';
import '../helpers/test_data.dart';

void main() {
  late UndoRedoService service;

  setUp(() {
    service = UndoRedoService();
  });

  Timetable makeTimetable({List<SelectedSection>? sections}) {
    final courses = twoCourseNoClash();
    return Timetable(
      id: 'tt-1',
      name: 'Test',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      campus: Campus.hyderabad,
      availableCourses: courses,
      selectedSections: sections ?? [],
      clashWarnings: [],
    );
  }

  group('initial state', () {
    test('canUndo is false', () {
      expect(service.canUndo, isFalse);
    });

    test('canRedo is false', () {
      expect(service.canRedo, isFalse);
    });

    test('undoDescription is null', () {
      expect(service.undoDescription, isNull);
    });

    test('redoDescription is null', () {
      expect(service.redoDescription, isNull);
    });
  });

  group('pushState', () {
    test('enables undo after push', () {
      final tt = makeTimetable();
      service.pushState(tt, 'Added section');

      expect(service.canUndo, isTrue);
      expect(service.undoDescription, 'Added section');
    });

    test('clears redo stack on push', () {
      final tt = makeTimetable();
      service.pushState(tt, 'Step 1');
      service.undo(tt);
      expect(service.canRedo, isTrue);

      service.pushState(tt, 'Step 2');
      expect(service.canRedo, isFalse);
    });

    test('enforces max stack size of 50', () {
      final tt = makeTimetable();
      for (var i = 0; i < 55; i++) {
        service.pushState(tt, 'Step $i');
      }

      var undoCount = 0;
      while (service.canUndo) {
        service.undo(tt);
        undoCount++;
      }
      expect(undoCount, 50);
    });
  });

  group('undo', () {
    test('returns null when nothing to undo', () {
      final tt = makeTimetable();
      expect(service.undo(tt), isNull);
    });

    test('returns previous snapshot', () {
      final courses = twoCourseNoClash();
      final section = makeSelectedSection(
        courseCode: courses[0].courseCode,
        sectionId: courses[0].sections[0].sectionId,
        section: courses[0].sections[0],
      );
      final tt = makeTimetable(sections: [section]);
      service.pushState(tt, 'Added L1');

      final emptyTt = makeTimetable();
      final snapshot = service.undo(emptyTt);

      expect(snapshot, isNotNull);
      expect(snapshot!.sections.length, 1);
      expect(snapshot.description, 'Added L1');
    });

    test('enables redo after undo', () {
      final tt = makeTimetable();
      service.pushState(tt, 'Step 1');
      service.undo(tt);

      expect(service.canRedo, isTrue);
      expect(service.redoDescription, 'Step 1');
    });
  });

  group('redo', () {
    test('returns null when nothing to redo', () {
      final tt = makeTimetable();
      expect(service.redo(tt), isNull);
    });

    test('restores undone state', () {
      final tt = makeTimetable();
      service.pushState(tt, 'Step 1');
      service.undo(tt);
      final snapshot = service.redo(tt);

      expect(snapshot, isNotNull);
      expect(service.canUndo, isTrue);
      expect(service.canRedo, isFalse);
    });
  });

  group('clear', () {
    test('empties both stacks', () {
      final tt = makeTimetable();
      service.pushState(tt, 'Step 1');
      service.pushState(tt, 'Step 2');
      service.undo(tt);

      service.clear();

      expect(service.canUndo, isFalse);
      expect(service.canRedo, isFalse);
    });
  });

  group('notifyListeners', () {
    test('fires on pushState', () {
      var notified = false;
      service.addListener(() => notified = true);

      final tt = makeTimetable();
      service.pushState(tt, 'Step');
      expect(notified, isTrue);
    });

    test('fires on undo', () {
      final tt = makeTimetable();
      service.pushState(tt, 'Step');
      var notified = false;
      service.addListener(() => notified = true);
      service.undo(tt);
      expect(notified, isTrue);
    });

    test('fires on clear', () {
      var notified = false;
      service.addListener(() => notified = true);
      service.clear();
      expect(notified, isTrue);
    });
  });
}

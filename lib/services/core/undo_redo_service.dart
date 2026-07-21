import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';
import '../../models/timetable.dart';

class TimetableSnapshot {
  final List<SelectedSection> sections;
  final String description;

  TimetableSnapshot({
    required this.sections,
    required this.description,
  });
}

class UndoRedoService extends ChangeNotifier {
  final List<TimetableSnapshot> _undoStack = [];
  final List<TimetableSnapshot> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  String? get undoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get redoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;

  static List<SelectedSection> _copySelections(List<SelectedSection> sections) {
    return sections
        .map((s) => SelectedSection(
              courseCode: s.courseCode,
              sectionId: s.sectionId,
              section: s.section,
            ))
        .toList();
  }

  void pushState(Timetable timetable, String description) =>
      pushSections(timetable.selectedSections, description);

  /// Pushes an explicitly supplied section list. Use when the state to restore
  /// was captured before a mutation that has already been applied — e.g. an add
  /// that is only committed to the undo stack once it is known to have succeeded.
  void pushSections(List<SelectedSection> sections, String description) {
    _undoStack.add(TimetableSnapshot(
      sections: _copySelections(sections),
      description: description,
    ));
    if (_undoStack.length > AppLimits.maxUndoStackSize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    notifyListeners();
  }

  TimetableSnapshot? undo(Timetable currentTimetable) {
    if (!canUndo) return null;
    _redoStack.add(TimetableSnapshot(
      sections: _copySelections(currentTimetable.selectedSections),
      description: _undoStack.last.description,
    ));
    final previous = _undoStack.removeLast();
    notifyListeners();
    return previous;
  }

  TimetableSnapshot? redo(Timetable currentTimetable) {
    if (!canRedo) return null;
    _undoStack.add(TimetableSnapshot(
      sections: _copySelections(currentTimetable.selectedSections),
      description: _redoStack.last.description,
    ));
    final next = _redoStack.removeLast();
    notifyListeners();
    return next;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }
}

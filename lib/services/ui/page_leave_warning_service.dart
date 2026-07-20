import 'package:flutter/foundation.dart';
import '../../utils/web_utils.dart' as web_utils;

/// Tracks unsaved work across the app and, on web, wires up a single
/// `beforeunload` prompt so a refresh/tab-close warns the user.
///
/// Multiple screens can have unsaved changes at the same time (e.g. the CGPA
/// tab stays alive in the shell's IndexedStack while the timetable editor is
/// pushed on top), so dirty state is tracked per named [source]. The browser
/// listener is attached while *any* source is dirty and removed once none are,
/// which also means a screen that forgets to clean up can't leak a stale prompt
/// onto unrelated screens.
class PageLeaveWarningService {
  static final PageLeaveWarningService _instance =
      PageLeaveWarningService._internal();
  factory PageLeaveWarningService() => _instance;
  PageLeaveWarningService._internal();

  /// Default source key used by the back-compat [enableWarning] API.
  static const String _defaultSource = 'timetable';

  final Set<String> _dirtySources = {};
  bool _listenerAttached = false;

  bool get hasUnsavedChanges => _dirtySources.isNotEmpty;

  /// Marks [source] as having (or no longer having) unsaved changes, then
  /// reconciles the web listener with the combined state.
  void setUnsaved(String source, bool hasUnsavedChanges) {
    if (hasUnsavedChanges) {
      _dirtySources.add(source);
    } else {
      _dirtySources.remove(source);
    }
    _syncListener();
  }

  /// Clears unsaved state for a single [source]. Call from `dispose()` so a
  /// screen never leaves a dangling prompt behind.
  void clear(String source) => setUnsaved(source, false);

  /// Back-compat shim for the timetable editor's existing call sites.
  void enableWarning(bool hasUnsavedChanges) =>
      setUnsaved(_defaultSource, hasUnsavedChanges);

  /// Clears every source and detaches the listener.
  void disable() {
    _dirtySources.clear();
    _syncListener();
  }

  void _syncListener() {
    if (!kIsWeb) return;
    final shouldWarn = _dirtySources.isNotEmpty;
    if (shouldWarn && !_listenerAttached) {
      web_utils.addBeforeUnloadListener(() => _dirtySources.isNotEmpty);
      _listenerAttached = true;
    } else if (!shouldWarn && _listenerAttached) {
      web_utils.removeBeforeUnloadListener();
      _listenerAttached = false;
    }
  }
}

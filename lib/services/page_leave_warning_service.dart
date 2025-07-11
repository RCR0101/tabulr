import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class PageLeaveWarningService {
  static final PageLeaveWarningService _instance = PageLeaveWarningService._internal();
  factory PageLeaveWarningService() => _instance;
  PageLeaveWarningService._internal();

  bool _hasUnsavedChanges = false;
  bool _warningEnabled = false;

  void enableWarning(bool hasUnsavedChanges) {
    _hasUnsavedChanges = hasUnsavedChanges;
    
    if (kIsWeb) {
      if (hasUnsavedChanges && !_warningEnabled) {
        _addBeforeUnloadListener();
        _warningEnabled = true;
      } else if (!hasUnsavedChanges && _warningEnabled) {
        _removeBeforeUnloadListener();
        _warningEnabled = false;
      }
    }
  }

  void _addBeforeUnloadListener() {
    html.window.onBeforeUnload.listen((event) {
      if (_hasUnsavedChanges) {
        (event as html.BeforeUnloadEvent).returnValue = 'You have unsaved changes. Are you sure you want to leave?';
      }
    });
  }

  void _removeBeforeUnloadListener() {
    // Note: Can't actually remove the listener in modern browsers
    // but we can control the behavior via _hasUnsavedChanges
  }

  void disable() {
    _hasUnsavedChanges = false;
    _warningEnabled = false;
  }
}
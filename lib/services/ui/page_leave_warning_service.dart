import 'package:flutter/foundation.dart';
import '../../utils/web_utils.dart' as web_utils;

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
        web_utils.addBeforeUnloadListener(() => _hasUnsavedChanges);
        _warningEnabled = true;
      } else if (!hasUnsavedChanges && _warningEnabled) {
        web_utils.removeBeforeUnloadListener();
        _warningEnabled = false;
      }
    }
  }

  void disable() {
    _hasUnsavedChanges = false;
    _warningEnabled = false;
  }
}

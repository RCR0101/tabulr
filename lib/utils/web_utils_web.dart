import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void openUrl(String url) {
  html.window.open(url, '_blank');
}

html.EventListener? _beforeUnloadListener;

void addBeforeUnloadListener(bool Function() shouldWarn) {
  _beforeUnloadListener = (event) {
    if (shouldWarn()) {
      (event as html.BeforeUnloadEvent).returnValue =
          'You have unsaved changes. Are you sure you want to leave?';
    }
  };
  html.window.addEventListener('beforeunload', _beforeUnloadListener!);
}

void removeBeforeUnloadListener() {
  if (_beforeUnloadListener != null) {
    html.window.removeEventListener('beforeunload', _beforeUnloadListener!);
    _beforeUnloadListener = null;
  }
}

void addPageHideListener(void Function() callback) {
  html.window.addEventListener('pagehide', (event) {
    callback();
  });
}

void clearLocalStorageItem(String key) {
  js.context.callMethod('eval', [
    'window.localStorage.removeItem("$key")'
  ]);
}

void setLocalStorageItem(String key, String value) {
  js.context.callMethod('eval', [
    'window.localStorage.setItem("$key", \'$value\')'
  ]);
}

void usePathUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());
}

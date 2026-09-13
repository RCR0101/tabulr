import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

void openUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final allowed = {'http', 'https', 'mailto', 'tel'};
  if (!allowed.contains(uri.scheme.toLowerCase())) return;
  web.window.open(url, '_blank', 'noopener,noreferrer');
}

web.EventListener? _beforeUnloadListener;

void addBeforeUnloadListener(bool Function() shouldWarn) {
  _beforeUnloadListener =
      ((web.BeforeUnloadEvent event) {
        if (!shouldWarn()) return;

        // Browsers provide their own message, but both calls are still needed for
        // broad beforeunload compatibility.
        event.preventDefault();
        event.returnValue = 'You have unsaved changes.';
      }).toJS;
  web.window.addEventListener('beforeunload', _beforeUnloadListener);
}

void removeBeforeUnloadListener() {
  final listener = _beforeUnloadListener;
  if (listener == null) return;
  web.window.removeEventListener('beforeunload', listener);
  _beforeUnloadListener = null;
}

void addPageHideListener(void Function() callback) {
  web.window.addEventListener('pagehide', ((web.Event _) => callback()).toJS);
}

void clearLocalStorageItem(String key) {
  web.window.localStorage.removeItem(key);
}

void setLocalStorageItem(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

void usePathUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());
}

void downloadBlob(List<int> bytes, String filename) {
  final blob = web.Blob(<web.BlobPart>[Uint8List.fromList(bytes).toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.HTMLAnchorElement()
        ..href = url
        ..download = filename
        ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

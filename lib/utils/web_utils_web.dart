// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, depend_on_referenced_packages
import 'dart:html' as html;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void openUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final allowed = {'http', 'https', 'mailto', 'tel'};
  if (!allowed.contains(uri.scheme.toLowerCase())) return;
  html.window.open(url, '_blank', 'noopener,noreferrer');
}

html.EventListener? _beforeUnloadListener;

void addBeforeUnloadListener(bool Function() shouldWarn) {
  _beforeUnloadListener = (event) {
    if (shouldWarn()) {
      // Modern browsers show their own generic message and ignore this string,
      // but the confirmation dialog only fires reliably when the event is both
      // cancelled and given a returnValue — setting returnValue alone is no
      // longer enough in current Chrome.
      event.preventDefault();
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
  html.window.localStorage.remove(key);
}

void usePathUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());
}

void downloadBlob(List<int> bytes, String filename) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

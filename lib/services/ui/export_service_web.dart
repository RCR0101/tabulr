import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browser implementation for timetable and calendar exports.
class ExportServiceStub {
  static Future<String> savePngBytes(
    Uint8List pngBytes,
    String? customPath,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = customPath ?? 'timetable_$timestamp.png';
    _downloadBlob(pngBytes.toJS, 'image/png', filename);
    return filename;
  }

  static Future<String> saveIcsContent(String icsContent) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'timetable_$timestamp.ics';
    _downloadBlob(icsContent.toJS, 'text/calendar', filename);
    return filename;
  }

  static Future<String> saveTTContent(
    String ttContent,
    String? customPath,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = customPath ?? 'timetable_$timestamp.tt';
    _downloadBlob(ttContent.toJS, 'application/json', filename);
    return filename;
  }

  static Future<String> readTTFile(String filePath) async => filePath;

  static Future<String?> pickAndReadTTFile() {
    final input =
        web.HTMLInputElement()
          ..type = 'file'
          ..accept = '.tt';
    final completer = Completer<String?>();

    input.onchange =
        ((web.Event _) {
          final files = input.files;
          if (files == null || files.length == 0) {
            if (!completer.isCompleted) completer.complete(null);
            return;
          }

          final reader = web.FileReader();
          reader.onload =
              ((web.Event _) {
                final result = reader.result?.dartify();
                if (!completer.isCompleted) {
                  completer.complete(result is String ? result : null);
                }
              }).toJS;
          reader.onerror =
              ((web.Event _) {
                if (!completer.isCompleted) completer.complete(null);
              }).toJS;
          reader.readAsText(files.item(0)!);
        }).toJS;
    input.oncancel =
        ((web.Event _) {
          if (!completer.isCompleted) completer.complete(null);
        }).toJS;
    input.click();

    return completer.future;
  }

  static Future<String?> pickSaveLocationForTT(String defaultFileName) async {
    return defaultFileName;
  }

  static void _downloadBlob(
    web.BlobPart data,
    String mimeType,
    String filename,
  ) {
    final blob = web.Blob(
      <web.BlobPart>[data].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
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
}

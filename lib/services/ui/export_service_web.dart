import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

/// Web implementation for platform-specific exports
class ExportServiceStub {
  static Future<String> savePngBytes(Uint8List pngBytes, String? customPath) async {
    // For web, trigger download with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = customPath ?? 'timetable_$timestamp.png';
    
    final blob = html.Blob([pngBytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = filename;
    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    return filename;
  }
  
  static Future<String> saveIcsContent(String icsContent) async {
    // For web, trigger download with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'timetable_$timestamp.ics';
    
    final blob = html.Blob([icsContent], 'text/calendar');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = filename;
    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    return filename;
  }
  
  static Future<String> saveTTContent(String ttContent, String? customPath) async {
    // For web, trigger download with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = customPath ?? 'timetable_$timestamp.tt';
    
    final blob = html.Blob([ttContent], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = filename;
    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    return filename;
  }
  
  static Future<String> readTTFile(String filePath) async {
    // For web, this method is called after file picker selection
    // The filePath parameter is not used on web, file content is returned directly
    return filePath; // On web, this will actually be the file content
  }

  static Future<String?> pickAndReadTTFile() async {
    final input = html.FileUploadInputElement()..accept = '.tt';
    input.click();

    final completer = Completer<String?>();
    
    input.onChange.listen((e) async {
      final files = input.files;
      if (files?.isNotEmpty == true) {
        final file = files!.first;
        final reader = html.FileReader();
        
        reader.onLoad.listen((e) {
          completer.complete(reader.result as String?);
        });
        
        reader.onError.listen((e) {
          completer.complete(null);
        });
        
        reader.readAsText(file);
      } else {
        completer.complete(null);
      }
    });

    return await completer.future;
  }

  static Future<String?> pickSaveLocationForTT(String defaultFileName) async {
    // On web, we don't need to pick a save location, the browser handles it
    return defaultFileName;
  }
}
import 'dart:html' as html;
import 'dart:typed_data';

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
}
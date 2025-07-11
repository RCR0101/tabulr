import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Mobile/Desktop implementation for platform-specific exports
class ExportServiceStub {
  static Future<String> savePngBytes(Uint8List pngBytes, String? customPath) async {
    String filePath;
    
    if (customPath != null) {
      // Use custom path (assume it's a directory, append filename)
      filePath = '$customPath/timetable.png';
    } else {
      // Use default Documents directory
      final directory = await getApplicationDocumentsDirectory();
      filePath = '${directory.path}/timetable.png';
    }
    
    final file = File(filePath);
    await file.writeAsBytes(pngBytes);
    
    return filePath;
  }
  
  static Future<String> saveIcsContent(String icsContent) async {
    // Use default Documents directory
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/timetable.ics';
    
    final file = File(filePath);
    await file.writeAsString(icsContent);
    
    return filePath;
  }
}
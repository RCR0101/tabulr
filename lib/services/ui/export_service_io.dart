import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'secure_logger.dart';

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
  
  static Future<String> saveTTContent(String ttContent, String? customPath) async {
    String filePath;
    
    if (customPath != null) {
      // Use custom path (assume it's a directory, append filename)
      filePath = '$customPath/timetable.tt';
    } else {
      // Use default Documents directory
      final directory = await getApplicationDocumentsDirectory();
      filePath = '${directory.path}/timetable.tt';
    }
    
    final file = File(filePath);
    await file.writeAsString(ttContent);
    
    return filePath;
  }
  
  static Future<String> readTTFile(String filePath) async {
    final file = File(filePath);
    return await file.readAsString();
  }

  static Future<String?> pickAndReadTTFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tt'],
        allowMultiple: false,
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      SecureLogger.error('EXPORT', 'Error picking file', e);
      return null;
    }
  }

  static Future<String?> pickSaveLocationForTT(String defaultFileName) async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Timetable',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['tt'],
      );
      return outputFile;
    } catch (e) {
      SecureLogger.error('EXPORT', 'Error picking save location', e);
      return null;
    }
  }
}
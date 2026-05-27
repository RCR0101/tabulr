import 'dart:typed_data';

/// Stub implementation for platform-specific exports
class ExportServiceStub {
  static Future<String> savePngBytes(Uint8List pngBytes, String? customPath) async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<String> saveIcsContent(String icsContent) async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<String> saveTTContent(String ttContent, String? customPath) async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<String> readTTFile(String filePath) async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<String?> pickAndReadTTFile() async {
    throw UnsupportedError('Platform not supported');
  }
  
  static Future<String?> pickSaveLocationForTT(String defaultFileName) async {
    throw UnsupportedError('Platform not supported');
  }
}
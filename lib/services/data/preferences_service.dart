import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';
import '../../models/timetable_display.dart';

class PreferencesService extends ChangeNotifier {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  TimetableSize _timetableSize = TimetableSize.medium;
  TimetableLayout _timetableLayout = TimetableLayout.vertical;
  

  TimetableSize get timetableSize => _timetableSize;
  TimetableLayout get timetableLayout => _timetableLayout;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load timetable size preference
    final sizeIndex = prefs.getInt(StorageKeys.timetableSize) ?? TimetableSize.medium.index;
    _timetableSize = TimetableSize.values[sizeIndex];
    
    // Load timetable layout preference
    final layoutIndex = prefs.getInt(StorageKeys.timetableLayout) ?? TimetableLayout.vertical.index;
    _timetableLayout = TimetableLayout.values[layoutIndex];
    
    notifyListeners();
  }

  Future<void> setTimetableSize(TimetableSize size) async {
    _timetableSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageKeys.timetableSize, size.index);
    notifyListeners();
  }

  Future<void> setTimetableLayout(TimetableLayout layout) async {
    _timetableLayout = layout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageKeys.timetableLayout, layout.index);
    notifyListeners();
  }

  // Display names live on the enums themselves so a new value cannot be added
  // without every label site picking it up.
  String getTimetableSizeName(TimetableSize size) => size.label;

  String getTimetableLayoutName(TimetableLayout layout) => layout.label;
}
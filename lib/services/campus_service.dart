import 'package:shared_preferences/shared_preferences.dart';

enum Campus {
  hyderabad,
  pilani,
}

class CampusService {
  static const String _campusKey = 'selected_campus';
  
  static Campus _currentCampus = Campus.hyderabad;
  
  static Campus get currentCampus => _currentCampus;
  
  static String get currentCampusCode {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'hyderabad';
      case Campus.pilani:
        return 'pilani';
    }
  }
  
  static String get currentCampusDisplayName {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'Hyderabad';
      case Campus.pilani:
        return 'Pilani';
    }
  }
  
  static String get currentCoursesCollection {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'hyd-courses';
      case Campus.pilani:
        return 'pilani-courses';
    }
  }
  
  static String get currentMetadataDocument {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'current-hyderabad';
      case Campus.pilani:
        return 'current-pilani';
    }
  }
  
  static Future<void> initializeCampus() async {
    final prefs = await SharedPreferences.getInstance();
    final campusIndex = prefs.getInt(_campusKey) ?? Campus.pilani.index;
    _currentCampus = Campus.values[campusIndex];
  }
  
  static Future<void> setCampus(Campus campus) async {
    _currentCampus = campus;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_campusKey, campus.index);
  }
  
  static List<Campus> get allCampuses => Campus.values;
  
  static String getCampusDisplayName(Campus campus) {
    switch (campus) {
      case Campus.hyderabad:
        return 'Hyderabad';
      case Campus.pilani:
        return 'Pilani';
    }
  }
  
  static String getCampusCode(Campus campus) {
    switch (campus) {
      case Campus.hyderabad:
        return 'hyderabad';
      case Campus.pilani:
        return 'pilani';
    }
  }
}
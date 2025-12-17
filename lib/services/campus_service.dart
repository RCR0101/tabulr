import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

enum Campus {
  hyderabad,
  pilani,
  goa,
}

class CampusService {
  static const String _campusKey = 'selected_campus';
  
  static Campus _currentCampus = Campus.hyderabad;
  static final StreamController<Campus> _campusChangeController = StreamController<Campus>.broadcast();
  
  static Campus get currentCampus {
    return _currentCampus;
  }
  
  static Stream<Campus> get campusChangeStream => _campusChangeController.stream;
  
  static String get currentCampusCode {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'hyderabad';
      case Campus.pilani:
        return 'pilani';
      case Campus.goa:
        return 'goa';
    }
  }
  
  static String get currentCampusDisplayName {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'Hyderabad';
      case Campus.pilani:
        return 'Pilani';
      case Campus.goa:
        return 'Goa';
    }
  }
  
  static String get currentCoursesCollection {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'hyd-courses';
      case Campus.pilani:
        return 'pilani-courses';
      case Campus.goa:
        return 'goa-courses';
    }
  }
  
  static String get currentMetadataDocument {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'current-hyderabad';
      case Campus.pilani:
        return 'current-pilani';
      case Campus.goa:
        return 'current-goa';
    }
  }
  
  static Future<void> initializeCampus() async {
    final prefs = await SharedPreferences.getInstance();
    final campusIndex = prefs.getInt(_campusKey) ?? Campus.hyderabad.index;
    print('CampusService: Loading campus with index $campusIndex');
    
    // Validate the index to prevent out-of-bounds errors
    if (campusIndex >= 0 && campusIndex < Campus.values.length) {
      _currentCampus = Campus.values[campusIndex];
      print('CampusService: Loaded campus ${_currentCampus.toString()}');
    } else {
      print('CampusService: Invalid campus index $campusIndex, defaulting to Hyderabad');
      _currentCampus = Campus.hyderabad;
    }
    
    _campusChangeController.add(_currentCampus); // Notify initial state
  }
  
  static Future<void> setCampus(Campus campus) async {
    _currentCampus = campus;
    final prefs = await SharedPreferences.getInstance();
    print('CampusService: Saving campus ${campus.toString()} with index ${campus.index}');
    await prefs.setInt(_campusKey, campus.index);
    _campusChangeController.add(campus); // Notify listeners
  }
  
  static List<Campus> get allCampuses => Campus.values;
  
  static String getCampusDisplayName(Campus campus) {
    switch (campus) {
      case Campus.hyderabad:
        return 'Hyderabad';
      case Campus.pilani:
        return 'Pilani';
      case Campus.goa:
        return 'Goa';
    }
  }
  
  static String getCampusCode(Campus campus) {
    switch (campus) {
      case Campus.hyderabad:
        return 'hyderabad';
      case Campus.pilani:
        return 'pilani';
      case Campus.goa:
        return 'goa';
    }
  }
}
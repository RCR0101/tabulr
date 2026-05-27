import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/campus.dart';

export '../../models/campus.dart';

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
  
  static String get campusId {
    switch (_currentCampus) {
      case Campus.hyderabad:
        return 'hyderabad';
      case Campus.pilani:
        return 'pilani';
      case Campus.goa:
        return 'goa';
    }
  }

  static CollectionReference<Map<String, dynamic>> coursesMasterRef(FirebaseFirestore firestore) {
    return firestore.collection('campuses').doc(campusId).collection('courses_master');
  }

  static CollectionReference<Map<String, dynamic>> timetableRef(FirebaseFirestore firestore) {
    return firestore.collection('campuses').doc(campusId).collection('timetable');
  }

  static CollectionReference<Map<String, dynamic>> examSeatingRef(FirebaseFirestore firestore) {
    return firestore.collection('campuses').doc(campusId).collection('exam_seating');
  }

  static DocumentReference<Map<String, dynamic>> metadataDocRef(FirebaseFirestore firestore) {
    return firestore.collection('campuses').doc(campusId).collection('metadata').doc('current');
  }
  
  static Future<void> initializeCampus() async {
    final prefs = await SharedPreferences.getInstance();
    final campusIndex = prefs.getInt(_campusKey) ?? Campus.hyderabad.index;
    if (campusIndex >= 0 && campusIndex < Campus.values.length) {
      _currentCampus = Campus.values[campusIndex];
    } else {
      _currentCampus = Campus.hyderabad;
    }
    
    _campusChangeController.add(_currentCampus); // Notify initial state
  }
  
  static Future<void> setCampus(Campus campus) async {
    _currentCampus = campus;
    final prefs = await SharedPreferences.getInstance();
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
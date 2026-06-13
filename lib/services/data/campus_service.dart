import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';
import '../../models/campus.dart';

export '../../models/campus.dart';

class CampusService {
  
  static Campus _currentCampus = Campus.hyderabad;
  static final StreamController<Campus> _campusChangeController = StreamController<Campus>.broadcast();
  
  static Campus get currentCampus {
    return _currentCampus;
  }
  
  static Stream<Campus> get campusChangeStream => _campusChangeController.stream;
  
  static String get currentCampusCode => _currentCampus.code;
  static String get currentCampusDisplayName => _currentCampus.displayName;
  static String get campusId => _currentCampus.code;

  static CollectionReference<Map<String, dynamic>> coursesMasterRef(FirebaseFirestore firestore) {
    return firestore.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.coursesMaster);
  }

  static CollectionReference<Map<String, dynamic>> timetableRef(FirebaseFirestore firestore) {
    return firestore.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.timetable);
  }

  static CollectionReference<Map<String, dynamic>> examSeatingRef(FirebaseFirestore firestore) {
    return firestore.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.examSeating);
  }

  static DocumentReference<Map<String, dynamic>> metadataDocRef(FirebaseFirestore firestore) {
    return firestore.collection(FirestoreCollections.campuses).doc(campusId).collection(FirestoreCollections.metadata).doc(FirestoreCollections.current);
  }
  
  static Future<void> initializeCampus() async {
    final prefs = await SharedPreferences.getInstance();
    final campusIndex = prefs.getInt(StorageKeys.selectedCampus) ?? Campus.hyderabad.index;
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
    await prefs.setInt(StorageKeys.selectedCampus, campus.index);
    _campusChangeController.add(campus); // Notify listeners
  }
  
  static List<Campus> get allCampuses => Campus.values;
  
  static String getCampusDisplayName(Campus campus) => campus.displayName;
  static String getCampusCode(Campus campus) => campus.code;
}
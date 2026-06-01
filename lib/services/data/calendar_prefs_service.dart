import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_constants.dart';

class CalendarPrefsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _prefsRef(String uid) =>
      _firestore.collection(FirestoreCollections.users).doc(uid).collection(FirestoreCollections.calendarPrefs).doc(FirestoreCollections.data);

  Future<DocumentSnapshot<Map<String, dynamic>>> getPrefs(String uid) {
    return _prefsRef(uid).get();
  }

  Future<void> savePrefs(String uid, Map<String, dynamic> data) {
    return _prefsRef(uid).set(data);
  }
}

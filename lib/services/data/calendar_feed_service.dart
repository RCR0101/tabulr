import 'package:cloud_firestore/cloud_firestore.dart';

import '../../constants/app_constants.dart';

/// A timetable's live calendar link: `webcal://tabulr.net/cal/<token>.ics`,
/// served by the `calendarFeed` function. The token is the Firestore doc id
/// of `calendar_feeds/<token>`, so it is unguessable; turning the link off
/// deletes the doc and the URL stops working.
class CalendarFeedService {
  static const _host = 'tabulr.net/cal';

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(FirestoreCollections.calendarFeeds);

  static String webcalUrl(String token) => 'webcal://$_host/$token.ics';
  static String httpsUrl(String token) => 'https://$_host/$token.ics';

  /// Google Calendar's "add by URL" screen, prefilled.
  static String googleCalendarUrl(String token) =>
      'https://calendar.google.com/calendar/render?cid=${Uri.encodeComponent(webcalUrl(token))}';

  /// The existing link for this timetable, or a new one.
  Future<String> tokenFor({required String owner, required String timetableId}) async {
    final existing = await _col
        .where('owner', isEqualTo: owner)
        .where('timetableId', isEqualTo: timetableId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return existing.docs.first.id;
    final ref = _col.doc();
    await ref.set({
      'owner': owner,
      'timetableId': timetableId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> turnOff(String token) => _col.doc(token).delete();
}

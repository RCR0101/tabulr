import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/services/data/admin_data_service.dart';

/// Covers the courses_master editor's data layer: the catalogue is what every
/// screen resolves titles and credits through, and its bundle is what clients
/// actually read, so a write that misses the bundle is invisible-but-wrong.
void main() {
  late FakeFirebaseFirestore db;
  late AdminDataService service;

  Future<void> seedBundle(String campusId, List<Map<String, dynamic>> entries) {
    return db
        .collection('campuses')
        .doc(campusId)
        .collection('catalog')
        .doc('courses_master')
        .set({
      'version': '2026-01-01T00:00:00.000Z',
      'count': entries.length,
      'entriesJson': jsonEncode(entries),
    });
  }

  Future<List<Map<String, dynamic>>> readBundle(String campusId) async {
    final snap = await db
        .collection('campuses')
        .doc(campusId)
        .collection('catalog')
        .doc('courses_master')
        .get();
    return (jsonDecode(snap.data()!['entriesJson'] as String) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Map<String, dynamic> entry(String code,
          {String title = 'A Title', num credits = 3, String type = 'Normal'}) =>
      {
        'course_code': code,
        'title': title,
        'credits': credits,
        'type': type,
      };

  setUp(() {
    db = FakeFirebaseFirestore();
    service = AdminDataService();
    service.firestoreForTest = db;
    service.invalidateAll();
  });

  tearDown(() {
    // A singleton: leaving the fake attached would leak into other suites.
    service.firestoreForTest = null;
    service.invalidateAll();
  });

  group('fetchMasterCourses', () {
    test('reads the whole catalogue from the bundle, sorted by code', () async {
      await seedBundle('hyderabad',
          [entry('MATH F211'), entry('BIO F110'), entry('CS F211')]);

      final rows = await service.fetchMasterCourses('hyderabad');

      expect(rows.map((r) => r['course_code']),
          ['BIO F110', 'CS F211', 'MATH F211']);
      // The doc id every write keys on is derived here, not stored.
      expect(rows.first['docId'], 'BIO_F110');
    });

    test('reaches rows that have no timetable document', () async {
      // The whole reason this screen exists: fetchCourses iterates timetable
      // docs, so a catalogue-only course is invisible there.
      await seedBundle('hyderabad', [entry('CS F211'), entry('CS F407')]);
      await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('timetable')
          .doc('CS_F211')
          .set({'sections': []});

      final master = await service.fetchMasterCourses('hyderabad');
      final joined = await service.fetchCourses('hyderabad');

      expect(master.map((r) => r['course_code']), ['CS F211', 'CS F407']);
      expect(joined.map((r) => r['course_code']), ['CS F211']);
    });

    test('falls back to the collection when no bundle exists', () async {
      await db
          .collection('campuses')
          .doc('goa')
          .collection('courses_master')
          .doc('CS_F211')
          .set(entry('CS F211'));

      final rows = await service.fetchMasterCourses('goa');
      expect(rows.single['course_code'], 'CS F211');
    });

    test('matches code or title, case-insensitively', () async {
      await seedBundle('hyderabad', [
        entry('CS F211', title: 'Data Structures'),
        entry('BIO F110', title: 'Biological Laboratory'),
      ]);

      expect(
          (await service.fetchMasterCourses('hyderabad', query: 'bio'))
              .map((r) => r['course_code']),
          ['BIO F110']);
      expect(
          (await service.fetchMasterCourses('hyderabad', query: 'structures'))
              .map((r) => r['course_code']),
          ['CS F211']);
    });
  });

  group('saveMasterCourse', () {
    test('writes the row, patches the bundle, and bumps the cache marker',
        () async {
      await seedBundle('hyderabad', [entry('CS F211', title: 'Old')]);

      await service.saveMasterCourse(
        campusIds: ['hyderabad'],
        courseCode: 'CS F211',
        title: 'Data Structures and Algorithms',
        credits: 4,
        type: 'Normal',
      );

      final doc = await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('courses_master')
          .doc('CS_F211')
          .get();
      expect(doc.data()!['title'], 'Data Structures and Algorithms');
      expect(doc.data()!['credits'], 4);

      // The bundle is what clients read — a collection-only write is invisible.
      final bundle = await readBundle('hyderabad');
      expect(bundle.single['title'], 'Data Structures and Algorithms');

      // And without the marker they keep serving their 72h cache.
      final meta = await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('metadata')
          .doc('current')
          .get();
      expect(meta.data()!['lastUpdated'], isNotNull);
      expect(meta.data()!['version'], isNotNull);
    });

    test('credit hours are stored and reach the bundle', () async {
      // The catalogue could hold units only, so a course the booklet publishes
      // in contact hours had nowhere to put its number and read as 0 credits —
      // which drops it out of the CGPA denominator entirely.
      await seedBundle('hyderabad', [entry('CHEM U101', title: 'Old')]);

      await service.saveMasterCourse(
        campusIds: ['hyderabad'],
        courseCode: 'CHEM U101',
        title: 'Atomic Structure',
        credits: 0,
        creditHours: 7,
        type: 'Normal',
      );

      final doc = await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('courses_master')
          .doc('CHEM_U101')
          .get();
      expect(doc.data()!['credit_hours'], 7);

      final bundle = await readBundle('hyderabad');
      expect(bundle.single['credit_hours'], 7);
    });

    test('an edit that sets only the title keeps the hours', () async {
      // The editor writes both fields, but the bundle entry is composed from
      // the upsert — so a save that carried no hours used to blank them there
      // while the document still had them.
      await seedBundle('hyderabad',
          [{...entry('CHEM U101'), 'credit_hours': 7}]);

      await service.saveMasterCourse(
        campusIds: ['hyderabad'],
        courseCode: 'CHEM U101',
        title: 'Renamed',
        credits: 0,
        type: 'Normal',
      );

      final bundle = await readBundle('hyderabad');
      expect(bundle.single['title'], 'Renamed');
      expect(bundle.single['credit_hours'], 7);
    });

    test('never touches the timetable document', () async {
      // The distinction from saveCourse: editing the catalogue must not invent a
      // course offering with no sections.
      await seedBundle('hyderabad', [entry('CS F407')]);

      await service.saveMasterCourse(
        campusIds: ['hyderabad'],
        courseCode: 'CS F407',
        title: 'Artificial Intelligence',
        credits: 3,
        type: 'Normal',
      );

      final timetable = await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('timetable')
          .doc('CS_F407')
          .get();
      expect(timetable.exists, isFalse);
    });

    test('adds a row the bundle did not have', () async {
      await seedBundle('hyderabad', [entry('CS F211')]);

      await service.saveMasterCourse(
        campusIds: ['hyderabad'],
        courseCode: 'CS F469',
        title: 'Information Retrieval',
        credits: 3,
        type: 'Normal',
      );

      final bundle = await readBundle('hyderabad');
      // Re-sorted, so the new row lands in code order rather than at the end.
      expect(bundle.map((e) => e['course_code']), ['CS F211', 'CS F469']);
    });

    test('writes every campus asked for, and only those', () async {
      for (final campus in ['hyderabad', 'pilani', 'goa']) {
        await seedBundle(campus, [entry('BITS U104', credits: 0)]);
      }

      await service.saveMasterCourse(
        campusIds: ['hyderabad', 'pilani'],
        courseCode: 'BITS U104',
        title: 'Foundations of Measurement',
        credits: 2,
        type: 'Normal',
      );

      expect((await readBundle('hyderabad')).single['credits'], 2);
      expect((await readBundle('pilani')).single['credits'], 2);
      // Goa was not selected: its deliberate divergence survives.
      expect((await readBundle('goa')).single['credits'], 0);
    });
  });

  group('deleteMasterCourse', () {
    test('removes a hyphenated code from the bundle', () async {
      // The regression this exists for: the bundle entry used to be matched by
      // re-deriving the doc id as [^a-zA-Z0-9] -> _, giving BITS_F101_2 while
      // the real doc id is BITS_F101-2. They never matched, so deleting a
      // hyphenated course left it in the bundle and visible across the app.
      // BITS F101-2 and BITS K101-2 are both real Hyderabad courses.
      await seedBundle('hyderabad', [entry('BITS F101-2'), entry('CS F211')]);

      await service.deleteMasterCourse(
          campusIds: ['hyderabad'], courseCode: 'BITS F101-2');

      final bundle = await readBundle('hyderabad');
      expect(bundle.map((e) => e['course_code']), ['CS F211']);
    });

    test('removes the collection row but leaves the timetable alone', () async {
      await seedBundle('hyderabad', [entry('CS F211')]);
      await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('courses_master')
          .doc('CS_F211')
          .set(entry('CS F211'));
      await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('timetable')
          .doc('CS_F211')
          .set({'sections': []});

      await service.deleteMasterCourse(
          campusIds: ['hyderabad'], courseCode: 'CS F211');

      final master = await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('courses_master')
          .doc('CS_F211')
          .get();
      final timetable = await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('timetable')
          .doc('CS_F211')
          .get();
      expect(master.exists, isFalse);
      expect(timetable.exists, isTrue);
    });
  });

  group('findCourseCodeReferences', () {
    test('reports nothing for an unreferenced code', () async {
      expect(
          await service.findCourseCodeReferences('hyderabad', 'CS F999'), isEmpty);
    });

    test('finds the timetable, prerequisites, minors and branch plans',
        () async {
      await db
          .collection('campuses')
          .doc('hyderabad')
          .collection('timetable')
          .doc('CS_F211')
          .set({'sections': []});
      // A prerequisite OF another course, i.e. nested rather than the doc id.
      await db
          .collection('reference')
          .doc('prerequisites')
          .collection('courses')
          .doc('CS_F342')
          .set({
        'courseCode': 'CS F342',
        'groups': [
          {'options': [{'courseCode': 'CS F211'}]}
        ],
      });
      await db.collection('minors').doc('m1').set({
        'name': 'Computer Science',
        'groups': [
          {'courses': [{'code': 'CS F211'}]}
        ],
      });
      await db
          .collection('reference')
          .doc('branches')
          .collection('data')
          .doc('A7')
          .set({'semesters': {'2-1': ['CS F211']}});

      final refs =
          await service.findCourseCodeReferences('hyderabad', 'CS F211');

      expect(refs.length, 4, reason: refs.toString());
      expect(refs[0], contains('timetable'));
      expect(refs[1], contains('CS F342'));
      expect(refs[2], contains('Computer Science'));
      expect(refs[3], contains('A7'));
    });

    test('a prefix of another code is not a reference', () async {
      // Without a word boundary, "CS F21" matches "CS F211" and the confirmation
      // invents orphans that do not exist.
      await db.collection('minors').doc('m1').set({
        'name': 'Computer Science',
        'groups': [
          {'courses': [{'code': 'CS F211'}]}
        ],
      });

      expect(await service.findCourseCodeReferences('hyderabad', 'CS F21'),
          isEmpty);
      expect(await service.findCourseCodeReferences('hyderabad', 'CS F211'),
          isNotEmpty);
    });

    test('matches the underscored document-id spelling too', () async {
      // Reference data stores codes both ways depending on the collection.
      await db
          .collection('reference')
          .doc('branches')
          .collection('data')
          .doc('A7')
          .set({'semesters': {'2-1': ['CS_F211']}});

      expect(await service.findCourseCodeReferences('hyderabad', 'CS F211'),
          isNotEmpty);
    });

    test('ignores the branch _metadata document', () async {
      await db
          .collection('reference')
          .doc('branches')
          .collection('data')
          .doc('_metadata')
          .set({'lastUpdated': 'CS F211'});

      expect(await service.findCourseCodeReferences('hyderabad', 'CS F211'),
          isEmpty);
    });
  });
}

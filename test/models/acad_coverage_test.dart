import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/acad_coverage.dart';

void main() {
  final courses = [
    {'course_code': 'CS F211', 'title': 'Data Structures'},
    {'course_code': 'CS F212', 'title': 'DBMS'},
    {'course_code': 'BIO F110', 'title': 'Biology Lab'},
  ];
  final index = [
    {'code': 'CS F211', 'fileCount': 40, 'typeCounts': {'pyq': 12, 'notes': 28}},
    {'code': 'CS F212', 'fileCount': 5, 'typeCounts': {'notes': 5}},
    {'code': 'MATH F111', 'fileCount': 9, 'typeCounts': {'pyq': 9}},
  ];
  final requests = [
    {'course': 'CS F212', 'type': 'pyq', 'requestedBy': 'a@x', 'note': '2024 compre'},
    {'course': 'CS F212', 'type': 'solutions', 'requestedBy': 'a@x'},
    {'course': 'CS  F212', 'type': 'pyq', 'requestedBy': 'b@x'},
    {'course': 'ECON F211', 'type': 'notes', 'requestedBy': 'c@x'},
  ];

  test('most-asked first, then emptiest', () {
    final rows = buildCoverage(courses, index, requests);
    expect(rows.map((r) => r.code), ['CS F212', 'ECON F211', 'BIO F110', 'CS F211']);
    final dbms = rows.first;
    expect(dbms.title, 'DBMS');
    expect(dbms.requesters, 2);
    expect(dbms.requests, 3);
    expect(dbms.requestsByType, {'pyq': 2, 'solutions': 1});
    expect(dbms.pastPapers, 0);
    expect(dbms.notes, ['2024 compre']);
  });

  test('a requested course that is not running still shows', () {
    final econ = buildCoverage(courses, index, requests).firstWhere((r) => r.code == 'ECON F211');
    expect(econ.running, isFalse);
    expect(econ.isGap, isTrue);
  });

  test('courses that are not running and nobody asked for are left out', () {
    expect(buildCoverage(courses, index, requests).map((r) => r.code), isNot(contains('MATH F111')));
  });

  test('filters', () {
    final rows = buildCoverage(courses, index, requests);
    expect(filterCoverage(rows, CoverageFilter.gaps).map((r) => r.code), ['CS F212', 'ECON F211', 'BIO F110']);
    expect(filterCoverage(rows, CoverageFilter.noFiles).map((r) => r.code), ['BIO F110']);
    expect(filterCoverage(rows, CoverageFilter.noPastPapers).map((r) => r.code), ['CS F212', 'BIO F110']);
    expect(filterCoverage(rows, CoverageFilter.requested).map((r) => r.code), ['CS F212', 'ECON F211']);
  });
}

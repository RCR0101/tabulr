import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:timetable_maker/screens/exam_seating_screen.dart';
import 'package:timetable_maker/services/data/exam_seating_service.dart';

import '../helpers/preview_harness.dart';

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('flutter_keyboard_visibility'),
          MockStreamHandler.inline(onListen: (_, events) => events.success(0)),
        );
    await loadPreviewFont();
  });
  final exams = [
    ExamSeating(
      courseCode: 'CS F211',
      courseTitle: 'Data Structures and Algorithms',
      examDate: '09 March 27 - 09:30 AM to 11:00 AM',
      rooms: [
        ExamRoom(
          roomNo: 'C-101',
          idFrom: '2022A7PS0001H',
          idTo: '2022A7PS0999H',
        ),
      ],
    ),
    ExamSeating(
      courseCode: 'MATH F211',
      courseTitle: 'Mathematics III',
      examDate: '12 March 27 - 04:00 PM to 05:30 PM',
      rooms: [ExamRoom(roomNo: 'A-202', allStudents: true)],
    ),
  ];

  for (final size in [const Size(2400, 1500), const Size(780, 1688)]) {
    testWidgets(
      'exam seating ${size.width > 1000 ? 'desktop' : 'mobile'} preview',
      (tester) async {
        usePreviewSurface(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: previewTheme(Brightness.light),
            home: RepaintBoundary(
              child: ExamSeatingScreen(
                initialExams: exams,
                initialSelectedCourses: exams,
                initialStudentId: '2022A7PS0042H',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Find rooms'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          'exam_seating_${size.width > 1000 ? 'desktop' : 'mobile'}',
        );
      },
    );
  }
}

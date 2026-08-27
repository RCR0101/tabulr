import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/screens/exam_seating_screen.dart';
import 'package:timetable_maker/services/data/exam_seating_service.dart';

void main() {
  final exam = ExamSeating(
    courseCode: 'CS F211',
    courseTitle: 'Data Structures and Algorithms',
    examDate: '09 March 27 - 09:30 AM to 11:00 AM',
    rooms: [
      ExamRoom(roomNo: 'C-101', idFrom: '2022A7PS0001H', idTo: '2022A7PS0999H'),
    ],
  );

  for (final size in [const Size(1200, 800), const Size(390, 844)]) {
    testWidgets('exam dashboard works at ${size.width}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: ExamSeatingScreen(
            initialExams: [exam],
            initialSelectedCourses: [exam],
            initialStudentId: '2022A7PS0042H',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Find your seat'), findsOneWidget);
      expect(find.text('Your exam plan'), findsOneWidget);
      expect(find.text('CS F211'), findsOneWidget);
      await tester.tap(find.text('Find rooms'));
      await tester.pumpAndSettle();

      expect(find.text('Room C-101'), findsOneWidget);
      expect(find.text('Seats 2022A7PS0001H - 2022A7PS0999H'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/academic_record.dart';
import 'package:timetable_maker/models/cdc_slot.dart';
import 'package:timetable_maker/models/cgpa_data.dart';
import 'package:timetable_maker/models/course_type.dart';
import 'package:timetable_maker/services/core/degree_auditor.dart';

/// Builds a record from code -> grade. 'E' is the failing grade.
AcademicRecord _record(Map<String, String> grades) {
  final attempts = <String, CourseAttempt>{};
  grades.forEach((code, grade) {
    attempts[AcademicRecord.normalizeCode(code)] = (
      semester: '1-1',
      entry: CourseEntry(
        courseCode: code,
        courseTitle: code,
        credits: 3,
        courseType: CourseType.normal,
        grade: grade,
      ),
    );
  });
  return AcademicRecord(attempts: attempts, cgpa: 0);
}

void main() {
  group('DegreeAuditor', () {
    final cdcs = {
      '1-1': [const CdcSlot(['CS F111'])],
      '2-1': [const CdcSlot(['CS F211']), const CdcSlot(['MATH F211'])],
      // A choice slot: either satisfies the requirement.
      '3-1': [const CdcSlot(['CS F301', 'CS F303'])],
    };

    test('cleared / failed / pending are classified correctly', () {
      final audit = DegreeAuditor.audit(
        cdcsBySemester: cdcs,
        record: _record({
          'CS F111': 'A', // cleared
          'CS F211': 'E', // failed (needs retake)
          // MATH F211 not taken -> pending
          'CS F303': 'B', // clears the 3-1 choice via the second option
        }),
      );

      expect(audit.total, 4);
      expect(audit.cleared, 2);
      expect(audit.failed, 1);
      expect(audit.pending, 1);
      expect(audit.coreComplete, isFalse);

      final choice = audit.requirements.firstWhere((r) => r.semester == '3-1');
      expect(choice.status, CoreStatus.cleared);
      expect(choice.clearedBy, 'CS F303');

      expect(audit.failedRequirements.single.slot.options.first, 'CS F211');
      expect(audit.pendingRequirements.single.slot.options.first, 'MATH F211');
    });

    test('a passed option outranks a failed one in the same choice', () {
      // Failed CS F301 but passed CS F303 -> the choice is cleared, not failed.
      final audit = DegreeAuditor.audit(
        cdcsBySemester: {
          '3-1': [const CdcSlot(['CS F301', 'CS F303'])],
        },
        record: _record({'CS F301': 'E', 'CS F303': 'A'}),
      );
      expect(audit.cleared, 1);
      expect(audit.failed, 0);
    });

    test('all cleared -> coreComplete', () {
      final audit = DegreeAuditor.audit(
        cdcsBySemester: cdcs,
        record: _record({
          'CS F111': 'A',
          'CS F211': 'B',
          'MATH F211': 'C',
          'CS F301': 'A',
        }),
      );
      expect(audit.coreComplete, isTrue);
      expect(audit.fractionCleared, 1.0);
    });

    test('elective tallies count only passed pool courses', () {
      final audit = DegreeAuditor.audit(
        cdcsBySemester: const {},
        record: _record({'CS F441': 'A', 'CS F469': 'E', 'BITS F225': 'B'}),
        dels: const ['CS F441', 'CS F469', 'CS F415'], // one passed, one failed, one untaken
        huels: const ['BITS F225'],
      );
      expect(audit.clearedDels, 1);
      expect(audit.clearedHuels, 1);
    });
  });
}

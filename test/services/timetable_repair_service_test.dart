import 'package:flutter_test/flutter_test.dart';
import 'package:timetable_maker/models/course.dart';
import 'package:timetable_maker/services/core/clash_detector.dart';
import 'package:timetable_maker/services/core/timetable_repair_service.dart';
import '../helpers/test_data.dart';

void main() {
  test('repairs a closed section without moving unrelated courses', () {
    final target = makeCourse(
      courseCode: 'A F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [2]),
      ],
    );
    final other = makeCourse(
      courseCode: 'B F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.W], hours: [1]),
      ],
    );
    final selected = [
      makeSelectedSection(
        courseCode: target.courseCode,
        sectionId: 'L1',
        section: target.sections[0],
      ),
      makeSelectedSection(
        courseCode: other.courseCode,
        sectionId: 'L1',
        section: other.sections[0],
      ),
    ];

    final plans = TimetableRepairService.planSectionRepair(
      currentSections: selected,
      availableCourses: [target, other],
      courseCode: target.courseCode,
      unavailableSectionIds: {'L1'},
    );

    expect(plans, isNotEmpty);
    expect(plans.first.isDirect, isTrue);
    expect(
      plans.first.newSections
          .firstWhere((section) => section.courseCode == target.courseCode)
          .sectionId,
      'L2',
    );
    expect(plans.first.collateralChanges, isEmpty);
  });

  test('moves one conflicting course when a direct repair cannot fit', () {
    final target = makeCourse(
      courseCode: 'A F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [1]),
      ],
    );
    final blocker = makeCourse(
      courseCode: 'B F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [1]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.W], hours: [1]),
      ],
    );
    final selected = [
      makeSelectedSection(
        courseCode: target.courseCode,
        sectionId: 'L1',
        section: target.sections[0],
      ),
      makeSelectedSection(
        courseCode: blocker.courseCode,
        sectionId: 'L1',
        section: blocker.sections[0],
      ),
    ];

    final plans = TimetableRepairService.planSectionRepair(
      currentSections: selected,
      availableCourses: [target, blocker],
      courseCode: target.courseCode,
      unavailableSectionIds: {'L1'},
    );

    expect(plans, isNotEmpty);
    expect(plans.first.isDirect, isFalse);
    expect(plans.first.collateralChanges.single.courseCode, blocker.courseCode);
    expect(
      ClashDetector.detectClashes(plans.first.newSections, [target, blocker]),
      isEmpty,
    );
  });

  test('never moves a protected course', () {
    final target = makeCourse(
      courseCode: 'A F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.T], hours: [1]),
      ],
    );
    final blocker = makeCourse(
      courseCode: 'B F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [1]),
        makeSection(sectionId: 'L2', days: [DayOfWeek.W], hours: [1]),
      ],
    );
    final selected = [
      makeSelectedSection(
        courseCode: target.courseCode,
        sectionId: 'L1',
        section: target.sections[0],
      ),
      makeSelectedSection(
        courseCode: blocker.courseCode,
        sectionId: 'L1',
        section: blocker.sections[0],
      ),
    ];

    final plans = TimetableRepairService.planSectionRepair(
      currentSections: selected,
      availableCourses: [target, blocker],
      courseCode: target.courseCode,
      unavailableSectionIds: {'L1'},
      preferences: TimetableRepairPreferences(
        lockedCourseCodes: {blocker.courseCode},
      ),
    );

    expect(plans, isEmpty);
  });

  test('whole-course repair evaluates lecture and tutorial combinations', () {
    final source = makeCourse(
      courseCode: 'OLD F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.M], hours: [1]),
      ],
    );
    final replacement = makeCourse(
      courseCode: 'NEW F111',
      sections: [
        makeSection(sectionId: 'L1', days: [DayOfWeek.T], hours: [1]),
        makeSection(
          sectionId: 'T1',
          type: SectionType.T,
          days: [DayOfWeek.W],
          hours: [2],
        ),
      ],
    );
    final selected = [
      makeSelectedSection(
        courseCode: source.courseCode,
        sectionId: 'L1',
        section: source.sections.single,
      ),
    ];

    final plans = TimetableRepairService.planCourseReplacement(
      currentSections: selected,
      availableCourses: [source, replacement],
      sourceCourseCode: source.courseCode,
      replacementCourse: replacement,
      creditBasis: CreditBasis.units,
    );

    expect(plans, isNotEmpty);
    expect(
      plans.first.newSections.map((section) => section.courseCode).toSet(),
      {replacement.courseCode},
    );
    expect(
      plans.first.newSections.map((section) => section.sectionId).toSet(),
      {'L1', 'T1'},
    );
  });
}

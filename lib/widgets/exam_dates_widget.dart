import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';

class ExamDatesWidget extends StatelessWidget {
  final List<SelectedSection> selectedSections;
  final List<Course> courses;

  const ExamDatesWidget({
    super.key,
    required this.selectedSections,
    required this.courses,
  });

  @override
  Widget build(BuildContext context) {
    final examData = _getExamData();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.event, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Exam Schedule',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${examData.length} courses',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (examData.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No courses selected',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Table(
                  border: TableBorder.all(
                    color: const Color(0xFF30363D),
                    width: 1,
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(2.5),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2),
                  },
                  children: [
                    // Header row
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xFF21262D),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Course',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFFF0F6FC),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'MidSem Exam',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFFF0F6FC),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'EndSem Exam',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFFF0F6FC),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Data rows
                    ...examData.map((exam) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exam.courseCode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFFF0F6FC),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                exam.courseTitle,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF8B949E),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: exam.midSemText.isNotEmpty 
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      exam.midSemText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ),
                                  if (exam.midSemTime.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      exam.midSemTime,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF8B949E),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : const Text(
                                '-',
                                style: TextStyle(color: Color(0xFF656D76)),
                              ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: exam.endSemText.isNotEmpty 
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDA3633).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      exam.endSemText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDA3633),
                                      ),
                                    ),
                                  ),
                                  if (exam.endSemTime.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      exam.endSemTime,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF8B949E),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : const Text(
                                '-',
                                style: TextStyle(color: Color(0xFF656D76)),
                              ),
                        ),
                      ],
                    )).toList(),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  List<ExamData> _getExamData() {
    final examDataList = <ExamData>[];
    final processedCourses = <String>{};

    for (var selectedSection in selectedSections) {
      if (processedCourses.contains(selectedSection.courseCode)) {
        continue;
      }
      
      final course = courses.where(
        (c) => c.courseCode == selectedSection.courseCode,
      ).firstOrNull;
      
      if (course == null) {
        continue; // Skip if course not found instead of throwing exception
      }

      processedCourses.add(selectedSection.courseCode);

      final midSemText = course.midSemExam != null 
        ? '${course.midSemExam!.date.day}/${course.midSemExam!.date.month}'
        : '';
      
      final midSemTime = course.midSemExam != null 
        ? TimeSlotInfo.getTimeSlotName(course.midSemExam!.timeSlot)
        : '';

      final endSemText = course.endSemExam != null 
        ? '${course.endSemExam!.date.day}/${course.endSemExam!.date.month}'
        : '';
      
      final endSemTime = course.endSemExam != null 
        ? TimeSlotInfo.getTimeSlotName(course.endSemExam!.timeSlot)
        : '';

      examDataList.add(ExamData(
        courseCode: course.courseCode,
        courseTitle: course.courseTitle,
        midSemText: midSemText,
        midSemTime: midSemTime,
        endSemText: endSemText,
        endSemTime: endSemTime,
      ));
    }

    examDataList.sort((a, b) => a.courseCode.compareTo(b.courseCode));
    return examDataList;
  }
}

class ExamData {
  final String courseCode;
  final String courseTitle;
  final String midSemText;
  final String midSemTime;
  final String endSemText;
  final String endSemTime;

  ExamData({
    required this.courseCode,
    required this.courseTitle,
    required this.midSemText,
    required this.midSemTime,
    required this.endSemText,
    required this.endSemTime,
  });
}
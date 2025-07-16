import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';

enum SortColumn { course, midSem, endSem }
enum SortDirection { ascending, descending }

class ExamDatesWidget extends StatefulWidget {
  final List<SelectedSection> selectedSections;
  final List<Course> courses;

  const ExamDatesWidget({
    super.key,
    required this.selectedSections,
    required this.courses,
  });

  @override
  State<ExamDatesWidget> createState() => _ExamDatesWidgetState();
}

class _ExamDatesWidgetState extends State<ExamDatesWidget> {
  SortColumn _sortColumn = SortColumn.course;
  SortDirection _sortDirection = SortDirection.ascending;

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
                      children: [
                        _buildSortableHeader(
                          'Course',
                          SortColumn.course,
                        ),
                        _buildSortableHeader(
                          'MidSem Exam',
                          SortColumn.midSem,
                        ),
                        _buildSortableHeader(
                          'EndSem Exam',
                          SortColumn.endSem,
                        ),
                      ],
                    ),
                    // Small screen sorting buttons row
                    if (MediaQuery.of(context).size.width < 768)
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFF21262D),
                        ),
                        children: [
                          _buildMobileSortButton(SortColumn.course),
                          _buildMobileSortButton(SortColumn.midSem),
                          _buildMobileSortButton(SortColumn.endSem),
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
                    )),
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

    for (var selectedSection in widget.selectedSections) {
      if (processedCourses.contains(selectedSection.courseCode)) {
        continue;
      }
      
      final course = widget.courses.where(
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

    // Apply sorting
    _sortExamData(examDataList);
    return examDataList;
  }

  Widget _buildSortableHeader(String title, SortColumn column) {
    final isCurrentColumn = _sortColumn == column;
    final isAscending = _sortDirection == SortDirection.ascending;
    final isSmallScreen = MediaQuery.of(context).size.width < 768;
    
    // On small screens, headers are not clickable (sorting buttons are in separate row)
    if (isSmallScreen) {
      return _buildMobileHeader(title, isCurrentColumn, isAscending);
    }
    
    // On large screens, headers are clickable
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isCurrentColumn) {
            _sortDirection = isAscending 
              ? SortDirection.descending 
              : SortDirection.ascending;
          } else {
            _sortColumn = column;
            _sortDirection = SortDirection.ascending;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        child: _buildWebHeader(title, isCurrentColumn, isAscending),
      ),
    );
  }

  Widget _buildWebHeader(String title, bool isCurrentColumn, bool isAscending) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFFF0F6FC),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isCurrentColumn 
              ? const Color(0xFF58A6FF).withOpacity(0.1)
              : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_arrow_up,
                size: 20,
                color: isCurrentColumn && isAscending 
                  ? const Color(0xFF58A6FF) 
                  : const Color(0xFF8B949E),
              ),
              const SizedBox(height: 1),
              Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: isCurrentColumn && !isAscending 
                  ? const Color(0xFF58A6FF) 
                  : const Color(0xFF8B949E),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileHeader(String title, bool isCurrentColumn, bool isAscending) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Color(0xFFF0F6FC),
        ),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMobileSortButton(SortColumn column) {
    final isCurrentColumn = _sortColumn == column;
    final isAscending = _sortDirection == SortDirection.ascending;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isCurrentColumn) {
            _sortDirection = isAscending 
              ? SortDirection.descending 
              : SortDirection.ascending;
          } else {
            _sortColumn = column;
            _sortDirection = SortDirection.ascending;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Sort',
              style: TextStyle(
                fontSize: 12,
                color: isCurrentColumn 
                  ? const Color(0xFF58A6FF) 
                  : const Color(0xFF8B949E),
                fontWeight: isCurrentColumn ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isCurrentColumn 
                  ? const Color(0xFF58A6FF).withOpacity(0.1)
                  : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_arrow_up,
                    size: 16,
                    color: isCurrentColumn && isAscending 
                      ? const Color(0xFF58A6FF) 
                      : const Color(0xFF8B949E),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: isCurrentColumn && !isAscending 
                      ? const Color(0xFF58A6FF) 
                      : const Color(0xFF8B949E),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sortExamData(List<ExamData> examData) {
    examData.sort((a, b) {
      int compareResult;
      
      switch (_sortColumn) {
        case SortColumn.course:
          compareResult = a.courseCode.compareTo(b.courseCode);
          break;
        case SortColumn.midSem:
          compareResult = _compareDates(a.midSemText, b.midSemText);
          break;
        case SortColumn.endSem:
          compareResult = _compareDates(a.endSemText, b.endSemText);
          break;
      }
      
      return _sortDirection == SortDirection.ascending 
        ? compareResult 
        : -compareResult;
    });
  }

  int _compareDates(String dateA, String dateB) {
    // Handle empty dates (put them at the end)
    if (dateA.isEmpty && dateB.isEmpty) return 0;
    if (dateA.isEmpty) return 1;
    if (dateB.isEmpty) return -1;
    
    // Parse dates in format "dd/mm"
    try {
      final partsA = dateA.split('/');
      final partsB = dateB.split('/');
      
      if (partsA.length != 2 || partsB.length != 2) {
        return dateA.compareTo(dateB);
      }
      
      final dayA = int.parse(partsA[0]);
      final monthA = int.parse(partsA[1]);
      final dayB = int.parse(partsB[0]);
      final monthB = int.parse(partsB[1]);
      
      // Compare month first, then day
      if (monthA != monthB) {
        return monthA.compareTo(monthB);
      }
      return dayA.compareTo(dayB);
    } catch (e) {
      // Fallback to string comparison if parsing fails
      return dateA.compareTo(dateB);
    }
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
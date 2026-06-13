import 'package:flutter/material.dart';
import '../../models/all_course.dart';
import '../../services/parsers/performance_sheet_parser.dart';
import '../../services/ui/responsive_service.dart';
import '../../utils/grade_utils.dart' as grade_utils;

class PerformanceSheetPreviewDialog extends StatelessWidget {
  final ParsedPerformanceSheet parsed;
  final List<AllCourse> allCourses;

  const PerformanceSheetPreviewDialog({
    super.key,
    required this.parsed,
    required this.allCourses,
  });

  @override
  Widget build(BuildContext context) {
    final courseMap = <String, AllCourse>{};
    for (final course in allCourses) {
      courseMap[course.courseCode.toUpperCase()] = course;
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Import Preview'),
                if (parsed.studentName != null)
                  Text(
                    parsed.studentName!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: ResponsiveService.isMobile(context) ? MediaQuery.of(context).size.width * 0.85 : 400,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(label: 'Semesters', value: '${parsed.semesters.length}'),
                  _SummaryItem(label: 'Courses', value: '${parsed.totalCourses}'),
                  if (parsed.cgpa != null)
                    _SummaryItem(label: 'CGPA', value: parsed.cgpa!.toStringAsFixed(2)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined, color: Theme.of(context).colorScheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will override existing data for the imported semesters.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: parsed.semesters.length,
                itemBuilder: (context, index) {
                  final semester = parsed.semesters[index];
                  return ExpansionTile(
                    title: Text(semester.normalizedName),
                    subtitle: Text('${semester.courses.length} courses', style: Theme.of(context).textTheme.bodySmall),
                    children: semester.courses.map((course) {
                      final lookup = courseMap[course.courseCode.toUpperCase()];
                      final notFound = lookup == null;

                      return ListTile(
                        dense: true,
                        leading: notFound
                            ? Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error, size: 18)
                            : null,
                        title: Text(
                          course.courseCode,
                          style: TextStyle(color: notFound ? Theme.of(context).colorScheme.error : null),
                        ),
                        subtitle: Text(
                          lookup?.courseTitle ?? 'Course not found in database',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getGradeColor(course.grade, context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            course.grade,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
      ],
    );
  }

  Color _getGradeColor(String grade, BuildContext context) =>
      grade_utils.getGradeColor(grade, scheme: Theme.of(context).colorScheme);
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

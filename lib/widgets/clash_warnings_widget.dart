import 'package:flutter/material.dart';
import '../models/timetable.dart';
import '../utils/design_constants.dart';

class ClashWarningsWidget extends StatelessWidget {
  final List<ClashWarning> warnings;

  const ClashWarningsWidget({
    super.key,
    required this.warnings,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Clash Warnings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: warnings.length,
            itemBuilder: (context, index) {
              final warning = warnings[index];
              final isError = warning.severity == ClashSeverity.error;
              final statusColor = isError ? AppDesign.danger(context) : AppDesign.warning(context);
              return Card(
                color: statusColor.withValues(alpha: 0.1),
                child: ListTile(
                  leading: Icon(
                    isError ? Icons.error : Icons.warning,
                    color: statusColor,
                  ),
                  title: Text(warning.message),
                  subtitle: Text(
                    'Courses: ${warning.conflictingCourses.join(', ')}',
                  ),
                  trailing: Chip(
                    label: Text(
                      warning.type.toString().split('.').last,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: statusColor.withValues(alpha: 0.2),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
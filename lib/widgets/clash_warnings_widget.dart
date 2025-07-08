import 'package:flutter/material.dart';
import '../models/timetable.dart';

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
              return Card(
                color: warning.severity == ClashSeverity.error
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                child: ListTile(
                  leading: Icon(
                    warning.severity == ClashSeverity.error
                        ? Icons.error
                        : Icons.warning,
                    color: warning.severity == ClashSeverity.error
                        ? Colors.red
                        : Colors.orange,
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
                    backgroundColor: warning.severity == ClashSeverity.error
                        ? Colors.red.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
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
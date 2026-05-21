import 'package:flutter/material.dart';
import '../services/course_guide_service.dart';
import '../services/courses_master_service.dart';

class CourseGuideWidget extends StatefulWidget {
  const CourseGuideWidget({super.key});

  @override
  State<CourseGuideWidget> createState() => _CourseGuideWidgetState();
}

class _CourseGuideWidgetState extends State<CourseGuideWidget> {
  final CourseGuideService _courseGuideService = CourseGuideService();
  List<CourseGuideSemester> _semesters = [];
  CourseGuideMetadata? _metadata;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCourseGuide();
  }

  Future<void> _loadCourseGuide() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final semesters = await _courseGuideService.getAllSemesters();
      final metadata = await _courseGuideService.getMetadata();

      setState(() {
        _semesters = semesters;
        _metadata = metadata;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load course guide: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading Course Guide...'),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error Loading Course Guide',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadCourseGuide,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_semesters.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.book_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No Course Guide Available',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The course guide data is not yet available.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.menu_book,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Course Guide (for BPHC)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadCourseGuide,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                if (_metadata != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last updated: ${_formatDateTime(_metadata!.lastUpdated)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _semesters.length,
              itemBuilder: (context, index) {
                final semester = _semesters[index];
                return _buildSemesterCard(semester);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatSemesterName(String name, String id) {
    final raw = id.replaceAll('semester_', '');
    final parts = raw.split('_');
    if (parts.length == 2) {
      return 'Year ${parts[0]}  ·  Semester ${parts[1]}';
    }
    return name;
  }

  Widget _buildSemesterCard(CourseGuideSemester semester) {
    final scheme = Theme.of(context).colorScheme;
    final semLabel = semester.semesterId.replaceAll('semester_', '').replaceAll('_', '.');

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.15)),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            semLabel,
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          _formatSemesterName(semester.name, semester.semesterId),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          '${semester.groups.length} group${semester.groups.length != 1 ? 's' : ''}',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        children: semester.groups.map((group) => _buildGroupCard(group)).toList(),
      ),
    );
  }

  Widget _buildGroupCard(CourseGuideGroup group) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        child: ExpansionTile(
          leading: Icon(
            Icons.group,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          title: Text(
            'Branches: ${group.displayName}',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '${group.courses.length} courses',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              child: _buildCoursesTable(group.courses),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoursesTable(List<CourseGuideEntry> courses) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 80,
        ),
        child: Table(
          columnWidths: {
            0: const FixedColumnWidth(100),
            1: FixedColumnWidth(MediaQuery.of(context).size.width - 320),
            2: const FixedColumnWidth(60),
            3: const FixedColumnWidth(80),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              children: [
                _buildTableHeader('Code'),
                _buildTableHeader('Course Name'),
                _buildTableHeader('Cr'),
                _buildTableHeader('Type'),
              ],
            ),
            ...courses.map((course) {
              final resolvedName = course.name.isNotEmpty
                  ? course.name
                  : CoursesMasterService().getTitle(course.code);
              return TableRow(
                children: [
                  _buildTableCell(course.code, isCode: true),
                  _buildTableCell(resolvedName),
                  _buildTableCell(course.credits.toString(), isCenter: true),
                  _buildTableCell(course.type, isType: true),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isCode = false, bool isCenter = false, bool isType = false}) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: isCode ? 'monospace' : null,
          fontWeight: isCode ? FontWeight.w500 : null,
          color: isType ? Theme.of(context).colorScheme.tertiary : null,
        ),
        textAlign: isCenter ? TextAlign.center : TextAlign.start,
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
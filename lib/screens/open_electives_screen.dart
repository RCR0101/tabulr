import 'dart:async';
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable_selection_link.dart';
import '../services/data/campus_service.dart';
import '../services/data/course_data_service.dart';
import '../services/data/open_electives_service.dart';
import '../utils/design_constants.dart';
import '../widgets/common/app_search_field.dart';
import '../widgets/common/inline_error_card.dart';
import '../widgets/common/shimmer_loading.dart';
import '../widgets/elective_course_list.dart';

class OpenElectivesScreen extends StatefulWidget {
  /// Set when opened from the editor, which makes the results list writable —
  /// Add/Remove goes straight onto that timetable. Null elsewhere (the
  /// timetable list, the global command palette), leaving the screen read-only.
  final TimetableSelectionLink? selectionLink;

  const OpenElectivesScreen({super.key, this.selectionLink});

  @override
  State<OpenElectivesScreen> createState() => _OpenElectivesScreenState();
}

class _OpenElectivesScreenState extends State<OpenElectivesScreen> {
  final OpenElectivesService _openElectivesService = OpenElectivesService();
  final CourseDataService _courseDataService = CourseDataService();
  final TextEditingController _search = TextEditingController();

  List<Course> _openElectives = [];
  List<Course> _availableCourses = [];

  bool _isLoading = true;
  String _errorMessage = '';
  String _query = '';
  StreamSubscription<Campus>? _campusSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _campusSubscription =
        CampusService.campusChangeStream.listen((_) => _loadInitialData());
  }

  @override
  void dispose() {
    _campusSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // When linked to a timetable, browse that timetable's embedded catalog so
      // everything offered here is something it can actually accept.
      final courses = widget.selectionLink?.availableCourses ??
          await _courseDataService.fetchCourses();
      final openElectives =
          await _openElectivesService.getOpenElectives(courses);

      if (!mounted) return;
      setState(() {
        _availableCourses = courses;
        _openElectives = openElectives;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load open electives: $e';
        _isLoading = false;
      });
    }
  }

  List<Course> get _filtered {
    if (_query.isEmpty) return _openElectives;
    final q = _query.toLowerCase();
    return _openElectives
        .where((c) =>
            c.courseCode.toLowerCase().contains(q) ||
            c.courseTitle.toLowerCase().contains(q))
        .toList();
  }

  Widget _buildInfoNote(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppDesign.spacingMd, AppDesign.spacingMd, AppDesign.spacingMd, 0),
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.primary),
          const SizedBox(width: AppDesign.spacingSm),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                children: const [
                  TextSpan(
                    text: 'These are Open Electives (OPELs) — every offered '
                        'course outside the Discipline Elective (DEL) and '
                        'Humanities Elective (HUEL) pools.\n',
                  ),
                  TextSpan(
                    text: 'A DEL may also be counted as an OPEL once your DEL '
                        'requirement is fulfilled, and a HUEL once your HUEL '
                        'requirement is fulfilled.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'Open Electives'),
      body: _isLoading
          ? const CourseListSkeleton()
          : Column(
              children: [
                if (_errorMessage.isNotEmpty)
                  InlineErrorCard(message: _errorMessage),
                _buildInfoNote(context),
                Padding(
                  padding: const EdgeInsets.all(AppDesign.spacingMd),
                  child: Column(
                    children: [
                      AppSearchField(
                        controller: _search,
                        hint: 'Search open electives by code or name…',
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                      if (widget.selectionLink != null) ...[
                        const SizedBox(height: AppDesign.spacingSm),
                        ElectiveTimetableBanner(
                            selectionLink: widget.selectionLink),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ElectiveCourseList(
                    courses: _filtered,
                    catalog: _availableCourses,
                    selectionLink: widget.selectionLink,
                  ),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../services/core/timetable_generator_controller.dart';
import '../services/core/clash_detector.dart';
import '../services/ui/toast_service.dart';
import '../services/ui/responsive_service.dart';
import '../services/data/campus_service.dart';
import '../services/data/user_settings_service.dart';
import '../utils/design_constants.dart';
import 'common/app_dialog.dart';
import 'common/app_button.dart';
import 'generated_timetable_card.dart';

class TimetableGeneratorWidget extends StatefulWidget {
  final List<Course> availableCourses;
  final Function(List<ConstraintSelectedSection>) onTimetableSelected;

  const TimetableGeneratorWidget({
    super.key,
    required this.availableCourses,
    required this.onTimetableSelected,
  });

  @override
  State<TimetableGeneratorWidget> createState() => _TimetableGeneratorWidgetState();
}

class _TimetableGeneratorWidgetState extends State<TimetableGeneratorWidget>
    with SingleTickerProviderStateMixin {
  final TimetableGeneratorController _ctrl = TimetableGeneratorController();
  bool _advancedExpanded = false;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _ctrl.scoringWeights = UserSettingsService().scoringWeights;
    _ctrl.savedScoringWeights = _ctrl.scoringWeights;
    _ctrl.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _ctrl.removeListener(_onControllerChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);

    if (isMobile) {
      return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.settings), text: 'Configure'),
                  Tab(icon: Icon(Icons.view_list), text: 'Results'),
                ],
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Configuration Tab
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              children: [
                                _buildConfigurationPanel(),
                                const SizedBox(height: 16),
                                _buildConstraintsPanel(),
                                const SizedBox(height: 16),
                                _buildAdvancedWeightsPanel(),
                              ],
                            ),
                          ),
                        ),
                        _buildGenerateButton(),
                      ],
                    ),
                  ),
                  // Results Tab
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildResultsPanel(),
                  ),
                ],
              ),
            ),
          ],
        );
    }

    // Desktop layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel - Configuration
        Expanded(
          flex: 1,
          child: Column(
            children: [
              // Scrollable content area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      _buildConfigurationPanel(),
                      const SizedBox(height: 16),
                      _buildConstraintsPanel(),
                      const SizedBox(height: 16),
                      _buildAdvancedWeightsPanel(),
                    ],
                  ),
                ),
              ),
              _buildGenerateButton(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right panel - Results
        Expanded(
          flex: 2,
          child: _buildResultsPanel(),
        ),
      ],
    );
  }

  Widget _buildConfigurationPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.settings,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Course Selection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildCourseSelection(),
          ),
        ],
      ),
    );
  }

  Widget _buildConstraintsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Constraints & Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.view_list,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Generated Timetables',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_ctrl.generatedTimetables.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_ctrl.generatedTimetables.length} found',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _ctrl.generatedTimetables.isEmpty
                ? _buildEmptyResults()
                : _buildGeneratedTimetables(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _ctrl.isGenerating ? Icons.hourglass_top_rounded : Icons.table_chart_outlined,
              size: 48,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _ctrl.isGenerating ? 'Generating timetables...' : 'No timetables generated yet',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _ctrl.isGenerating
                ? 'This may take a few moments'
                : 'Select courses and click Generate to see results',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
          if (_ctrl.isGenerating) ...[
            const SizedBox(height: 20),
            CircularProgressIndicator(
              color: scheme.primary,
              strokeWidth: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseSelection() {
    final mandatoryCredits = _ctrl.mandatoryCourses.fold(0.0, (sum, code) {
      final c = widget.availableCourses.firstWhere((c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []));
      return sum + c.totalCredits;
    });
    final optionalCredits = _ctrl.optionalCourses.fold(0.0, (sum, code) {
      final c = widget.availableCourses.firstWhere((c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []));
      return sum + c.totalCredits;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mandatory Courses (${mandatoryCredits.toStringAsFixed(1)} credits):', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Must be included in every timetable', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        _buildCourseSearchField(_ctrl.mandatoryCourses, _ctrl.optionalCourses),
        const SizedBox(height: 8),
        _buildCourseBadges(_ctrl.mandatoryCourses, isMandatory: true),
        const SizedBox(height: 16),
        Text('Optional Courses (${optionalCredits.toStringAsFixed(1)} credits):', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Generator will fit as many as possible within credit limit', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        _buildCourseSearchField(_ctrl.optionalCourses, _ctrl.mandatoryCourses),
        const SizedBox(height: 8),
        _buildOptionalCoursesRanking(),
      ],
    );
  }

  Widget _buildCourseSearchField(List<String> targetList, List<String> otherList) {
    return TypeAheadField<Course>(
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            hintText: 'Search courses by code or name...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        );
      },
      suggestionsCallback: (pattern) {
        if (pattern.isEmpty) return <Course>[];

        return widget.availableCourses.where((course) {
          if (course.totalCredits == 0) return false;
          final searchLower = pattern.toLowerCase();
          return course.courseCode.toLowerCase().contains(searchLower) ||
                 course.courseTitle.toLowerCase().contains(searchLower);
        }).take(10).toList();
      },
      itemBuilder: (context, course) {
        final inTarget = targetList.contains(course.courseCode);
        final inOther = otherList.contains(course.courseCode);
        return ListTile(
          leading: Icon(
            inTarget || inOther ? Icons.check_circle : Icons.add_circle_outline,
            color: inTarget || inOther ? AppDesign.success(context) : AppDesign.info(context),
          ),
          title: Text(course.courseCode),
          subtitle: Text(
            course.courseTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('${course.totalCredits} credits'),
        );
      },
      onSelected: (course) {
        setState(() {
          if (!targetList.contains(course.courseCode) && !otherList.contains(course.courseCode)) {
            targetList.add(course.courseCode);
          }
        });
      },
      emptyBuilder: (context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No courses found'),
      ),
    );
  }

  Widget _buildCourseBadges(List<String> courseList, {required bool isMandatory}) {
    if (courseList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Center(
          child: Text(
            isMandatory ? 'No mandatory courses' : 'No optional courses',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    final badgeColor = isMandatory
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.tertiary;

    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: courseList.map((courseCode) {
            final course = widget.availableCourses.firstWhere(
              (c) => c.courseCode == courseCode,
              orElse: () => Course(courseCode: courseCode, courseTitle: 'Unknown', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []),
            );
            return Chip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.courseCode, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: badgeColor)),
                  Text(
                    course.courseTitle,
                    style: TextStyle(fontSize: ResponsiveService.clampedFontSize(context, 9), color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () {
                setState(() { courseList.remove(courseCode); });
              },
              backgroundColor: badgeColor.withValues(alpha: 0.1),
              deleteIconColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: badgeColor.withValues(alpha: 0.3), width: 1),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<List<String>> _buildClashClusters(List<String> courseCodes) {
    final courses = <String, Course>{};
    for (final code in courseCodes) {
      courses[code] = widget.availableCourses.firstWhere(
        (c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: 'Unknown', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []),
      );
    }

    final parent = <String, String>{};
    for (final code in courseCodes) {
      parent[code] = code;
    }
    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }
    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (int i = 0; i < courseCodes.length; i++) {
      for (int j = i + 1; j < courseCodes.length; j++) {
        if (_coursesClash(courses[courseCodes[i]]!, courses[courseCodes[j]]!)) {
          union(courseCodes[i], courseCodes[j]);
        }
      }
    }

    final groups = <String, List<String>>{};
    for (final code in courseCodes) {
      final root = find(code);
      (groups[root] ??= []).add(code);
    }
    return groups.values.toList();
  }

  bool _coursesClash(Course a, Course b) {
    for (final secA in a.sections) {
      for (final secB in b.sections) {
        if (ClashDetector.sectionsConflict(secA, secB)) return true;
      }
    }
    if (a.midSemExam != null && b.midSemExam != null) {
      if (ClashDetector.examDatesConflict(a.midSemExam!, b.midSemExam!)) return true;
    }
    if (a.endSemExam != null && b.endSemExam != null) {
      if (ClashDetector.examDatesConflict(a.endSemExam!, b.endSemExam!)) return true;
    }
    return false;
  }

  Widget _buildOptionalCoursesRanking() {
    if (_ctrl.optionalCourses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Center(
          child: Text(
            'No optional courses',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    final clusters = _buildClashClusters(_ctrl.optionalCourses);
    final accentColor = Theme.of(context).colorScheme.tertiary;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int ci = 0; ci < clusters.length; ci++) ...[
          if (ci > 0) const SizedBox(height: 8),
          _buildClashCluster(clusters[ci], accentColor, scheme),
        ],
      ],
    );
  }

  Widget _buildClashCluster(List<String> clusterCodes, Color accentColor, ColorScheme scheme) {
    final isClashGroup = clusterCodes.length > 1;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isClashGroup
              ? scheme.error.withValues(alpha: 0.3)
              : scheme.outline,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isClashGroup) ...[
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: scheme.error.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  'Timing conflict — drag to set priority',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.error.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: clusterCodes.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final globalOld = _ctrl.optionalCourses.indexOf(clusterCodes[oldIndex]);
                  final globalNew = _ctrl.optionalCourses.indexOf(clusterCodes[newIndex]);
                  final code = _ctrl.optionalCourses.removeAt(globalOld);
                  _ctrl.optionalCourses.insert(globalNew, code);
                });
              },
              itemBuilder: (context, index) {
                return _buildOptionalCourseRow(
                  key: ValueKey(clusterCodes[index]),
                  courseCode: clusterCodes[index],
                  accentColor: accentColor,
                  draggable: true,
                  dragIndex: index,
                );
              },
            ),
          ] else
            _buildOptionalCourseRow(
              key: ValueKey(clusterCodes[0]),
              courseCode: clusterCodes[0],
              accentColor: accentColor,
              draggable: false,
            ),
        ],
      ),
    );
  }

  Widget _buildOptionalCourseRow({
    required Key key,
    required String courseCode,
    required Color accentColor,
    required bool draggable,
    int? dragIndex,
  }) {
    final course = widget.availableCourses.firstWhere(
      (c) => c.courseCode == courseCode,
      orElse: () => Course(courseCode: courseCode, courseTitle: 'Unknown', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []),
    );
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (draggable)
            ReorderableDragStartListener(
              index: dragIndex!,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Icon(Icons.drag_handle, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            )
          else
            const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(course.courseCode, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: accentColor)),
                  Text(
                    course.courseTitle,
                    style: TextStyle(fontSize: ResponsiveService.clampedFontSize(context, 9), color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () { setState(() { _ctrl.optionalCourses.remove(courseCode); }); },
            icon: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.error),
            tooltip: 'Remove $courseCode',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildConstraints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Constraints & Preferences', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 10),

        // Schedule group
        _buildConstraintGroup(
          icon: Icons.schedule,
          title: 'Schedule',
          children: [
            _buildRowConstraint('Max hours/day', Container(
              width: 80,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _ctrl.maxHoursPerDay,
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                  items: List.generate(12, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('${i + 1}'),
                  )),
                  onChanged: (value) {
                    if (value != null) setState(() { _ctrl.maxHoursPerDay = value; });
                  },
                ),
              ),
            )),
            _buildCheckConstraint('Avoid back-to-back classes', _ctrl.avoidBackToBack, (v) => setState(() { _ctrl.avoidBackToBack = v ?? false; })),
            _buildCheckConstraint('Minimize gaps between classes', _ctrl.minimizeGaps, (v) => setState(() { _ctrl.minimizeGaps = v ?? false; })),
            _buildCheckConstraint('Protect lunch break (12–2 PM)', _ctrl.protectLunchBreak, (v) => setState(() { _ctrl.protectLunchBreak = v ?? false; })),
            _buildRowConstraint('Prefer classes in', Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<TimeOfDayPreference>(
                  value: _ctrl.timeOfDayPreference,
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                  items: const [
                    DropdownMenuItem(value: TimeOfDayPreference.none, child: Text('No preference')),
                    DropdownMenuItem(value: TimeOfDayPreference.morning, child: Text('Morning (before 12 PM)')),
                    DropdownMenuItem(value: TimeOfDayPreference.afternoon, child: Text('Afternoon (after 12 PM)')),
                  ],
                  onChanged: (value) { setState(() { _ctrl.timeOfDayPreference = value ?? TimeOfDayPreference.none; }); },
                ),
              ),
            )),
            const SizedBox(height: 12),
            _buildFreeDayRanking(),
            const SizedBox(height: 12),
            _buildTimeAvoidance(),
            const SizedBox(height: 12),
            _buildLabAvoidance(),
          ],
        ),
        const SizedBox(height: 10),

        // Instructors group
        _buildConstraintGroup(
          icon: Icons.person,
          title: 'Instructors',
          children: [
            _buildInstructorAvoidance(),
            const SizedBox(height: 12),
            _buildInstructorRanking(),
          ],
        ),
        const SizedBox(height: 10),

        // Exams group
        _buildConstraintGroup(
          icon: Icons.event,
          title: 'Exams',
          children: [
            _buildRowConstraint('Preferred midsem', Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<TimeSlot?>(
                  value: _ctrl.preferredMidsemSlot,
                  hint: const Text('Any', style: TextStyle(fontSize: 13)),
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                  items: [
                    const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any')),
                    ...TimeSlotInfo.getMidSemSlots().map((slot) => DropdownMenuItem(
                      value: slot,
                      child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.currentCampusCode)),
                    )),
                  ],
                  onChanged: (value) { setState(() { _ctrl.preferredMidsemSlot = value; }); },
                ),
              ),
            )),
            _buildRowConstraint('Preferred compre', Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<TimeSlot?>(
                  value: _ctrl.preferredCompreSlot,
                  hint: const Text('Any', style: TextStyle(fontSize: 13)),
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                  items: [
                    const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any')),
                    ...TimeSlotInfo.getEndSemSlots().map((slot) => DropdownMenuItem(
                      value: slot,
                      child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.currentCampusCode)),
                    )),
                  ],
                  onChanged: (value) { setState(() { _ctrl.preferredCompreSlot = value; }); },
                ),
              ),
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildConstraintGroup({required IconData icon, required String title, required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(width: 12),
            Expanded(child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4))),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckConstraint(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onChanged: onChanged,
    );
  }

  Widget _buildRowConstraint(String label, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }

  static const _dayNames = {
    DayOfWeek.M: 'Mon',
    DayOfWeek.T: 'Tue',
    DayOfWeek.W: 'Wed',
    DayOfWeek.Th: 'Thu',
    DayOfWeek.F: 'Fri',
    DayOfWeek.S: 'Sat',
  };

  Widget _buildFreeDayRanking() {
    final unranked = DayOfWeek.values
        .where((d) => !_ctrl.freeDayPreference.contains(d))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Free day preference:', style: TextStyle(fontSize: 14)),
              const Spacer(),
              if (_ctrl.freeDayPreference.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _ctrl.freeDayPreference.clear();
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap days in order of preference (most wanted free day first)',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          if (_ctrl.freeDayPreference.isNotEmpty) ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _ctrl.freeDayPreference.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final day = _ctrl.freeDayPreference.removeAt(oldIndex);
                  _ctrl.freeDayPreference.insert(newIndex, day);
                });
              },
              itemBuilder: (context, index) {
                final day = _ctrl.freeDayPreference[index];
                return Container(
                  key: ValueKey(day),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Icon(
                            Icons.drag_handle,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _dayNames[day]!,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _ctrl.freeDayPreference.remove(day);
                          });
                        },
                        icon: const Icon(Icons.close, size: 14),
                        tooltip: 'Remove ${_dayNames[day]}',
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
          ],
          if (unranked.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unranked.map((day) {
                return ActionChip(
                  label: Text(_dayNames[day]!, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    setState(() {
                      _ctrl.freeDayPreference.add(day);
                    });
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeAvoidance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Avoid time slots:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addTimeAvoidance,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (_ctrl.avoidTimes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _ctrl.avoidTimes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final avoidTime = entry.value;
                  return Chip(
                    label: Text(
                      '${avoidTime.day.name}: ${_formatAvoidTimeHours(avoidTime.hours)}',
                      style: TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _ctrl.avoidTimes.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    deleteIconColor: AppDesign.danger(context),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLabAvoidance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Avoid labs on:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addLabAvoidance,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (_ctrl.avoidLabs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _ctrl.avoidLabs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final avoidLab = entry.value;
                  return Chip(
                    label: Text(
                      '${avoidLab.day.name}: ${_formatAvoidTimeHours(avoidLab.hours)} (Labs)',
                      style: TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _ctrl.avoidLabs.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                    deleteIconColor: AppDesign.danger(context),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInstructorAvoidance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Avoid instructors:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton.icon(
              onPressed: _ctrl.mandatoryCourses.isNotEmpty ? _addInstructorAvoidance : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (_ctrl.avoidedInstructors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _ctrl.avoidedInstructors.asMap().entries.map((entry) {
                  final index = entry.key;
                  final instructor = entry.value;
                  return Chip(
                    label: Text(
                      instructor,
                      style: TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _ctrl.avoidedInstructors.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                    deleteIconColor: AppDesign.danger(context),
                  );
                }).toList(),
              ),
            ),
          ),
        ] else if (_ctrl.mandatoryCourses.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'Select courses first to see available instructors',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInstructorRanking() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Rank instructors:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton.icon(
              onPressed: _ctrl.mandatoryCourses.isNotEmpty ? _showInstructorRankingDialog : null,
              icon: const Icon(Icons.sort, size: 16),
              label: const Text('Rank', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (_ctrl.instructorRankings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.star,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Current Rankings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_ctrl.instructorRankings.length} course${_ctrl.instructorRankings.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _ctrl.instructorRankings.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.clear_all,
                          size: 14,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _ctrl.instructorRankings.entries.map((entry) {
                        final courseCode = entry.key;
                        final rankings = entry.value;
                        final totalRanked = rankings.lectureInstructors.length +
                                          rankings.practicalInstructors.length +
                                          rankings.tutorialInstructors.length;

                        return GestureDetector(
                          onTap: () => _showInstructorRankingDialog(),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      courseCode,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        totalRanked.toString(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (rankings.lectureInstructors.isNotEmpty)
                                      _buildSectionTypeBadge(context, 'L', rankings.lectureInstructors.length),
                                    if (rankings.practicalInstructors.isNotEmpty) ...[
                                      const SizedBox(width: 3),
                                      _buildSectionTypeBadge(context, 'P', rankings.practicalInstructors.length),
                                    ],
                                    if (rankings.tutorialInstructors.isNotEmpty) ...[
                                      const SizedBox(width: 3),
                                      _buildSectionTypeBadge(context, 'T', rankings.tutorialInstructors.length),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getTopInstructorSummary(rankings),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_ctrl.mandatoryCourses.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Text(
              'Select courses first to rank instructors',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTypeBadge(BuildContext context, String sectionType, int count) {
    final scheme = Theme.of(context).colorScheme;
    Color badgeColor;
    switch (sectionType) {
      case 'L':
        badgeColor = scheme.primary;
        break;
      case 'P':
        badgeColor = AppDesign.success(context);
        break;
      case 'T':
        badgeColor = AppDesign.warning(context);
        break;
      default:
        badgeColor = AppDesign.muted(context);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$sectionType:$count',
        style: TextStyle(
          fontSize: ResponsiveService.clampedFontSize(context, 9),
          fontWeight: FontWeight.bold,
          color: scheme.onPrimary,
        ),
      ),
    );
  }

  String _getTopInstructorSummary(InstructorRankings rankings) {
    final topInstructors = <String>[];

    if (rankings.lectureInstructors.isNotEmpty) {
      topInstructors.add('L: ${rankings.lectureInstructors.first}');
    }
    if (rankings.practicalInstructors.isNotEmpty) {
      topInstructors.add('P: ${rankings.practicalInstructors.first}');
    }
    if (rankings.tutorialInstructors.isNotEmpty) {
      topInstructors.add('T: ${rankings.tutorialInstructors.first}');
    }

    if (topInstructors.isEmpty) return 'No rankings set';
    return topInstructors.join(' • ');
  }

  String _formatAvoidTimeHours(List<int> hours) {
    if (hours.isEmpty) return '';
    if (hours.length == 1) {
      return TimeSlotInfo.getHourSlotName(hours.first);
    }

    // Sort hours and format as range
    final sortedHours = [...hours]..sort();
    return TimeSlotInfo.getHourRangeName(sortedHours);
  }

  Future<void> _addTimeAvoidance() async {
    final result = await showDialog<TimeAvoidance>(
      context: context,
      builder: (context) => const _TimeAvoidanceDialog(),
    );

    if (result != null && mounted) {
      setState(() {
        _ctrl.avoidTimes.add(result);
      });
    }
  }

  Future<void> _addLabAvoidance() async {
    final result = await showDialog<LabAvoidance>(
      context: context,
      builder: (context) => const _LabAvoidanceDialog(),
    );

    if (result != null && mounted) {
      setState(() {
        _ctrl.avoidLabs.add(result);
      });
    }
  }

  Future<void> _addInstructorAvoidance() async {
    // Get instructors organized by course and section type to avoid duplicates
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};
    final Set<String> seenInstructorsLower = <String>{};

    for (final courseCode in [..._ctrl.mandatoryCourses, ..._ctrl.optionalCourses]) {
      final course = widget.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => Course(
          courseCode: courseCode,
          courseTitle: 'Unknown',
          lectureCredits: 0,
          practicalCredits: 0,
          totalCredits: 0,
          sections: [],
        ),
      );

      final sectionTypeInstructors = <String, Set<String>>{
        'Lecture': <String>{},
        'Tutorial': <String>{},
        'Practical': <String>{},
      };

      // Track seen instructors per section type to avoid duplicates within each section type
      final sectionTypeSeenLower = <String, Set<String>>{
        'Lecture': <String>{},
        'Tutorial': <String>{},
        'Practical': <String>{},
      };

      for (final section in course.sections) {
        if (section.instructor.isNotEmpty) {
          // Determine section type
          String sectionType = 'Lecture'; // default
          if (section.type.toString().contains('SectionType.L')) {
            sectionType = 'Lecture';
          } else if (section.type.toString().contains('SectionType.T')) {
            sectionType = 'Tutorial';
          } else if (section.type.toString().contains('SectionType.P')) {
            sectionType = 'Practical';
          }

          // Split comma-separated instructors into individual instructors
          final instructorList = section.instructor.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
          for (final instructor in instructorList) {
            final instructorLower = instructor.toLowerCase();

            // Only add if we haven't seen this instructor in this section type before
            if (!sectionTypeSeenLower[sectionType]!.contains(instructorLower)) {
              sectionTypeSeenLower[sectionType]!.add(instructorLower);
              sectionTypeInstructors[sectionType]!.add(instructor);

              // Also track globally to avoid duplicates across courses
              seenInstructorsLower.add(instructorLower);
            }
          }
        }
      }

      // Convert sets to sorted lists and filter out empty section types
      final filteredSectionInstructors = <String, List<String>>{};
      for (final entry in sectionTypeInstructors.entries) {
        if (entry.value.isNotEmpty) {
          filteredSectionInstructors[entry.key] = entry.value.toList()..sort();
        }
      }

      if (filteredSectionInstructors.isNotEmpty) {
        courseSectionInstructors[courseCode] = filteredSectionInstructors;
      }
    }

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _InstructorAvoidanceDialog(
        courseSectionInstructors: courseSectionInstructors,
        currentlyAvoided: _ctrl.avoidedInstructors,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        for (final sectionSpecificKey in result) {
          // Extract the actual instructor name from the section-specific key
          // Format: "courseCode-sectionType-instructorName"
          final parts = sectionSpecificKey.split('-');
          if (parts.length >= 3) {
            // Join back in case instructor name had hyphens
            final instructor = parts.sublist(2).join('-');
            if (!_ctrl.avoidedInstructors.contains(instructor)) {
              _ctrl.avoidedInstructors.add(instructor);
            }
          }
        }
      });
    }
  }

  Future<void> _showInstructorRankingDialog() async {
    // Get instructors organized by course and section type
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};

    for (final courseCode in [..._ctrl.mandatoryCourses, ..._ctrl.optionalCourses]) {
      final course = widget.availableCourses.firstWhere(
        (c) => c.courseCode == courseCode,
        orElse: () => throw Exception('Course not found: $courseCode'),
      );

      courseSectionInstructors[courseCode] = {
        'L': [],
        'P': [],
        'T': [],
      };

      for (final section in course.sections) {
        final sectionTypeStr = section.type.toString().split('.').last;
        if (courseSectionInstructors[courseCode]!.containsKey(sectionTypeStr)) {
          final instructor = section.instructor.trim();
          if (instructor.isNotEmpty &&
              !courseSectionInstructors[courseCode]![sectionTypeStr]!.contains(instructor)) {
            courseSectionInstructors[courseCode]![sectionTypeStr]!.add(instructor);
          }
        }
      }
    }

    final result = await showDialog<Map<String, InstructorRankings>>(
      context: context,
      builder: (context) => _InstructorRankingDialog(
        courseSectionInstructors: courseSectionInstructors,
        currentRankings: Map.from(_ctrl.instructorRankings),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _ctrl.instructorRankings.clear();
        _ctrl.instructorRankings.addAll(result);
      });
    }
  }

  void _setScoringWeights(ScoringWeights weights) {
    setState(() { _ctrl.scoringWeights = weights; });
  }

  void _saveScoringWeights() {
    setState(() { _ctrl.savedScoringWeights = _ctrl.scoringWeights; });
    UserSettingsService().updateScoringWeights(_ctrl.scoringWeights);
  }

  Widget _buildAdvancedWeightsPanel() {
    final scheme = Theme.of(context).colorScheme;
    final isDefault = _ctrl.scoringWeights == const ScoringWeights();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() { _advancedExpanded = !_advancedExpanded; }),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: _advancedExpanded
                    ? const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))
                    : BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.science, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Advanced Scoring',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: scheme.onSurface),
                  ),
                  if (!isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Custom', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.primary)),
                    ),
                  ],
                  const Spacer(),
                  if (_advancedExpanded) ...[
                    if (_ctrl.scoringWeights != _ctrl.savedScoringWeights)
                      InkWell(
                        onTap: _saveScoringWeights,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text('Save', style: TextStyle(fontSize: 12, color: AppDesign.success(context), fontWeight: FontWeight.w600)),
                        ),
                      ),
                    if (!isDefault)
                      InkWell(
                        onTap: () { _setScoringWeights(const ScoringWeights()); _saveScoringWeights(); },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text('Reset', style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w500)),
                        ),
                      ),
                  ],
                  Icon(
                    _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          if (_advancedExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adjust how much each factor affects timetable ranking. Higher values = stronger effect on score.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 16),
                  _buildWeightSection(
                    title: 'Penalties',
                    subtitle: 'Negative factors that lower score',
                    color: AppDesign.danger(context),
                    icon: Icons.remove_circle_outline,
                    weights: [
                      _WeightEntry('Max hours/day exceeded', _ctrl.scoringWeights.maxHoursPerDayPenalty, 15, 0, 25,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(maxHoursPerDayPenalty: v))),
                      _WeightEntry('Avoid time conflicts', _ctrl.scoringWeights.avoidTimesPenalty, 15, 0, 25,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(avoidTimesPenalty: v))),
                      _WeightEntry('Lab time conflicts', _ctrl.scoringWeights.avoidLabsPenalty, 10, 0, 20,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(avoidLabsPenalty: v))),
                      _WeightEntry('Avoided instructors', _ctrl.scoringWeights.avoidedInstructorsPenalty, 15, 0, 25,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(avoidedInstructorsPenalty: v))),
                      _WeightEntry('Back-to-back classes', _ctrl.scoringWeights.backToBackPenalty, 8, 0, 15,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(backToBackPenalty: v))),
                      _WeightEntry('Gaps between classes', _ctrl.scoringWeights.gapsPenalty, 8, 0, 15,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(gapsPenalty: v))),
                      _WeightEntry('Lunch break violation', _ctrl.scoringWeights.lunchBreakPenalty, 5, 0, 10,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(lunchBreakPenalty: v))),
                      _WeightEntry('Time-of-day mismatch', _ctrl.scoringWeights.timeOfDayPenalty, 7, 0, 15,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(timeOfDayPenalty: v))),
                      _WeightEntry('Exam spread (close exams)', _ctrl.scoringWeights.examSpreadPenalty, 7, 0, 15,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(examSpreadPenalty: v))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildWeightSection(
                    title: 'Bonuses',
                    subtitle: 'Positive factors that raise score',
                    color: AppDesign.success(context),
                    icon: Icons.add_circle_outline,
                    weights: [
                      _WeightEntry('Preferred instructors', _ctrl.scoringWeights.preferredInstructorsBonus, 2, 0, 5,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(preferredInstructorsBonus: v))),
                      _WeightEntry('Instructor rankings', _ctrl.scoringWeights.instructorRankingsBonus, 2, 0, 5,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(instructorRankingsBonus: v))),
                      _WeightEntry('Free day / compact', _ctrl.scoringWeights.freeDayBonus, 3, 0, 8,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(freeDayBonus: v))),
                      _WeightEntry('Exam slot preference', _ctrl.scoringWeights.examSlotBonus, 2, 0, 5,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(examSlotBonus: v))),
                      _WeightEntry('Optional courses fit', _ctrl.scoringWeights.optionalCoursesBonus, 3, 0, 8,
                        (v) => _setScoringWeights(_ctrl.scoringWeights.copyWith(optionalCoursesBonus: v))),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWeightSection({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required List<_WeightEntry> weights,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const SizedBox(width: 8),
            Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 8),
        ...weights.map((w) => _buildWeightRow(w, color)),
      ],
    );
  }

  Widget _buildWeightRow(_WeightEntry entry, Color accentColor) {
    final scheme = Theme.of(context).colorScheme;
    final isDefault = entry.value == entry.defaultValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              entry.label,
              style: TextStyle(
                fontSize: 12,
                color: isDefault ? scheme.onSurface.withValues(alpha: 0.7) : scheme.onSurface,
                fontWeight: isDefault ? FontWeight.normal : FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: accentColor.withValues(alpha: 0.6),
                inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.3),
                thumbColor: accentColor,
              ),
              child: Slider(
                value: entry.value,
                min: entry.min,
                max: entry.max,
                divisions: (entry.max - entry.min).toInt(),
                onChanged: entry.onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              entry.value.toInt().toString(),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDefault ? scheme.onSurface.withValues(alpha: 0.5) : accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
    return Semantics(
      label: 'Generate Timetables',
      button: true,
      child: Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: _ctrl.mandatoryCourses.isNotEmpty && !_ctrl.isGenerating
            ? LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _ctrl.mandatoryCourses.isEmpty || _ctrl.isGenerating
            ? Theme.of(context).colorScheme.surface
            : null,
      ),
      child: FilledButton(
        onPressed: _ctrl.mandatoryCourses.isNotEmpty && !_ctrl.isGenerating ? _generateTimetables : null,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _ctrl.isGenerating
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Generating...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: _ctrl.mandatoryCourses.isNotEmpty
                        ? Theme.of(context).scaffoldBackgroundColor
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Generate Timetables',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _ctrl.mandatoryCourses.isNotEmpty
                          ? Theme.of(context).scaffoldBackgroundColor
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
      ),
    ),
    );
  }

  Future<void> _generateTimetables() async {
    final isMobile = ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);
    if (isMobile && _tabController != null) {
      _tabController!.animateTo(1);
    }

    try {
      final timetables = _ctrl.generate(widget.availableCourses);
      if (timetables.isEmpty) {
        _showNoTimetablesDialog();
      }
    } catch (e) {
      ToastService.showError('Error generating timetables: $e');
    }
  }

  Widget _buildGeneratedTimetables() {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.all(8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Generated Timetables (${_ctrl.generatedTimetables.length})',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _ctrl.generatedTimetables.length,
                itemBuilder: (context, index) {
                  final timetable = _ctrl.generatedTimetables[index];
                  return GeneratedTimetableCard(
                    timetable: timetable,
                    onSelect: () => widget.onTimetableSelected(timetable.sections),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoTimetablesDialog() {
    AppDialog.adaptive(
      context: context,
      title: 'No Valid Timetables Found',
      icon: Icons.warning_amber,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No conflict-free timetable combinations could be generated with your selected courses and constraints.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          const Text(
            'Try the following:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('• Remove some time constraints'),
          const Text('• Select fewer courses'),
          const Text('• Choose courses with more section options'),
          const Text('• Adjust your preferences'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All generated timetables are now conflict-free for better scheduling.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'OK',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _TimeAvoidanceDialog extends StatefulWidget {
  const _TimeAvoidanceDialog();

  @override
  State<_TimeAvoidanceDialog> createState() => _TimeAvoidanceDialogState();
}

class _TimeAvoidanceDialogState extends State<_TimeAvoidanceDialog> {
  DayOfWeek? _selectedDay;
  final List<int> _selectedHours = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Time to Avoid'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<DayOfWeek>(
              decoration: const InputDecoration(labelText: 'Day'),
              initialValue: _selectedDay,
              items: DayOfWeek.values.map((day) => DropdownMenuItem(
                value: day,
                child: Text(day.name),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDay = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Hours to avoid:'),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              width: double.infinity,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: 10,
                itemBuilder: (context, index) {
                  final hour = index + 1;
                  final isSelected = _selectedHours.contains(hour);
                  return FilterChip(
                    label: Text(
                      hour.toString(),
                      style: TextStyle(fontSize: 10),
                    ),
                    tooltip: TimeSlotInfo.getHourSlotName(hour),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedHours.add(hour);
                        } else {
                          _selectedHours.remove(hour);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedDay != null && _selectedHours.isNotEmpty
            ? () {
                final avoidTime = TimeAvoidance(
                  day: _selectedDay!,
                  hours: [..._selectedHours],
                );
                Navigator.pop(context, avoidTime);
              }
            : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _LabAvoidanceDialog extends StatefulWidget {
  const _LabAvoidanceDialog();

  @override
  State<_LabAvoidanceDialog> createState() => _LabAvoidanceDialogState();
}

class _LabAvoidanceDialogState extends State<_LabAvoidanceDialog> {
  DayOfWeek? _selectedDay;
  final List<int> _selectedHours = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Lab Avoidance'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<DayOfWeek>(
              decoration: const InputDecoration(labelText: 'Day'),
              initialValue: _selectedDay,
              items: DayOfWeek.values.map((day) => DropdownMenuItem(
                value: day,
                child: Text(day.name),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDay = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Hours to avoid labs:'),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              width: double.infinity,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: 10,
                itemBuilder: (context, index) {
                  final hour = index + 1;
                  final isSelected = _selectedHours.contains(hour);
                  return FilterChip(
                    label: Text(
                      hour.toString(),
                      style: TextStyle(fontSize: 10),
                    ),
                    tooltip: TimeSlotInfo.getHourSlotName(hour),
                    selected: isSelected,
                    selectedColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                    checkmarkColor: Theme.of(context).colorScheme.error,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedHours.add(hour);
                        } else {
                          _selectedHours.remove(hour);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedDay != null && _selectedHours.isNotEmpty
            ? () {
                final avoidLab = LabAvoidance(
                  day: _selectedDay!,
                  hours: [..._selectedHours],
                );
                Navigator.pop(context, avoidLab);
              }
            : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _InstructorAvoidanceDialog extends StatefulWidget {
  final Map<String, Map<String, List<String>>> courseSectionInstructors;
  final List<String> currentlyAvoided;

  const _InstructorAvoidanceDialog({
    required this.courseSectionInstructors,
    required this.currentlyAvoided,
  });

  @override
  State<_InstructorAvoidanceDialog> createState() => _InstructorAvoidanceDialogState();
}

class _InstructorAvoidanceDialogState extends State<_InstructorAvoidanceDialog> {
  final List<String> _selectedInstructors = [];
  final Set<String> _expandedCourses = <String>{};

  @override
  void initState() {
    super.initState();
    // Expand all courses by default for better visibility
    _expandedCourses.addAll(widget.courseSectionInstructors.keys);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Instructors to Avoid'),
      content: SizedBox(
        width: ResponsiveService.isMobile(context) ? double.infinity : 600,
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.currentlyAvoided.isNotEmpty) ...[
              Text(
                'Currently avoiding: ${widget.currentlyAvoided.join(", ")}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Select instructors by course:'),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: widget.courseSectionInstructors.isEmpty
                    ? const Center(
                        child: Text(
                          'No instructors found in selected courses',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: widget.courseSectionInstructors.keys.length,
                        itemBuilder: (context, index) {
                          final courseCode = widget.courseSectionInstructors.keys.elementAt(index);
                          final sectionInstructors = widget.courseSectionInstructors[courseCode]!;
                          final isExpanded = _expandedCourses.contains(courseCode);

                          // Count total instructors across all section types
                          final totalInstructors = sectionInstructors.values
                              .expand((instructors) => instructors)
                              .toSet()
                              .length;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text(
                                    courseCode,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '$totalInstructors instructor${totalInstructors == 1 ? '' : 's'} across ${sectionInstructors.keys.length} section type${sectionInstructors.keys.length == 1 ? '' : 's'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Icon(
                                    isExpanded ? Icons.expand_less : Icons.expand_more,
                                  ),
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedCourses.remove(courseCode);
                                      } else {
                                        _expandedCourses.add(courseCode);
                                      }
                                    });
                                  },
                                ),
                                if (isExpanded) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: sectionInstructors.entries.map((sectionEntry) {
                                        final sectionType = sectionEntry.key;
                                        final instructors = sectionEntry.value;

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$sectionType (${instructors.length})',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: instructors.map((instructor) {
                                                  // Create a unique key for section-specific selection
                                                  final sectionSpecificKey = '$courseCode-$sectionType-$instructor';
                                                  final isSelected = _selectedInstructors.contains(sectionSpecificKey);
                                                  final isAlreadyAvoided = widget.currentlyAvoided.contains(instructor);

                                                  return FilterChip(
                                                    label: Text(
                                                      instructor,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: isAlreadyAvoided
                                                            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)
                                                            : null,
                                                      ),
                                                    ),
                                                    selected: isSelected,
                                                    selectedColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                                                    checkmarkColor: Theme.of(context).colorScheme.error,
                                                    backgroundColor: isAlreadyAvoided
                                                        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.5)
                                                        : null,
                                                    onSelected: isAlreadyAvoided
                                                        ? null
                                                        : (selected) {
                                                            setState(() {
                                                              if (selected) {
                                                                _selectedInstructors.add(sectionSpecificKey);
                                                              } else {
                                                                _selectedInstructors.remove(sectionSpecificKey);
                                                              }
                                                            });
                                                          },
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (_selectedInstructors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected to avoid (${_selectedInstructors.length}):',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedInstructors.map((key) {
                        // Extract instructor name from section-specific key for display
                        final parts = key.split('-');
                        if (parts.length >= 3) {
                          final instructor = parts.sublist(2).join('-');
                          final courseCode = parts[0];
                          final sectionType = parts[1];
                          return '$instructor ($courseCode-$sectionType)';
                        }
                        return key;
                      }).join(", "),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedInstructors.isNotEmpty
              ? () => Navigator.pop(context, _selectedInstructors)
              : null,
          child: Text('Add ${_selectedInstructors.length} Instructor${_selectedInstructors.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

class _InstructorRankingDialog extends StatefulWidget {
  final Map<String, Map<String, List<String>>> courseSectionInstructors;
  final Map<String, InstructorRankings> currentRankings;

  const _InstructorRankingDialog({
    required this.courseSectionInstructors,
    required this.currentRankings,
  });

  @override
  State<_InstructorRankingDialog> createState() => _InstructorRankingDialogState();
}

class _InstructorRankingDialogState extends State<_InstructorRankingDialog>
    with TickerProviderStateMixin {
  late Map<String, InstructorRankings> _rankings;
  late TabController _tabController;
  late List<String> _courseList;

  @override
  void initState() {
    super.initState();
    _rankings = Map.from(widget.currentRankings);
    _courseList = widget.courseSectionInstructors.keys.toList()..sort();
    _tabController = TabController(length: _courseList.length, vsync: this);
    
    // Initialize empty rankings for courses that don't have any yet
    for (final courseCode in widget.courseSectionInstructors.keys) {
      if (!_rankings.containsKey(courseCode)) {
        _rankings[courseCode] = InstructorRankings();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rank Instructors by Preference'),
      content: SizedBox(
        width: ResponsiveService.isMobile(context) ? double.infinity : 650,
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            Text(
              'Drag to reorder instructors from most preferred (top) to least preferred (bottom)',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Tab bar for courses
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: Theme.of(context).colorScheme.primary,
                indicatorWeight: 2,
                tabs: _courseList.map((courseCode) {
                  return Tab(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        courseCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            // Tab view content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _courseList.map((courseCode) {
                  final instructorsByType = widget.courseSectionInstructors[courseCode]!;

                  return SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            courseCode,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (instructorsByType['L']!.isNotEmpty)
                            _buildSectionTypeRanking(courseCode, 'Lecture', 'L', instructorsByType['L']!),
                          if (instructorsByType['P']!.isNotEmpty)
                            _buildSectionTypeRanking(courseCode, 'Practical', 'P', instructorsByType['P']!),
                          if (instructorsByType['T']!.isNotEmpty)
                            _buildSectionTypeRanking(courseCode, 'Tutorial', 'T', instructorsByType['T']!),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _rankings),
          child: const Text('Save Rankings'),
        ),
      ],
    );
  }

  Widget _buildSectionTypeRanking(String courseCode, String typeName, String typeKey, List<String> availableInstructors) {
    final currentRankings = _rankings[courseCode]!;
    List<String> rankedInstructors;

    switch (typeKey) {
      case 'L':
        rankedInstructors = List.from(currentRankings.lectureInstructors);
        break;
      case 'P':
        rankedInstructors = List.from(currentRankings.practicalInstructors);
        break;
      case 'T':
        rankedInstructors = List.from(currentRankings.tutorialInstructors);
        break;
      default:
        rankedInstructors = [];
    }

    // Add any new instructors that aren't ranked yet
    for (final instructor in availableInstructors) {
      if (!rankedInstructors.contains(instructor)) {
        rankedInstructors.add(instructor);
      }
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    typeKey,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$typeName Instructors',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rankedInstructors.length} instructor${rankedInstructors.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rankedInstructors.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final instructor = rankedInstructors.removeAt(oldIndex);
                    rankedInstructors.insert(newIndex, instructor);

                    // Update the rankings
                    switch (typeKey) {
                      case 'L':
                        _rankings[courseCode] = _rankings[courseCode]!.copyWith(
                          lectureInstructors: rankedInstructors,
                        );
                        break;
                      case 'P':
                        _rankings[courseCode] = _rankings[courseCode]!.copyWith(
                          practicalInstructors: rankedInstructors,
                        );
                        break;
                      case 'T':
                        _rankings[courseCode] = _rankings[courseCode]!.copyWith(
                          tutorialInstructors: rankedInstructors,
                        );
                        break;
                    }
                  });
                },
                itemBuilder: (context, index) {
                  final instructor = rankedInstructors[index];
                  final position = index + 1;
                  final isTopRank = position <= 3;

                  return Container(
                    key: ValueKey('$courseCode-$typeKey-$instructor'),
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isTopRank
                        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                        : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: isTopRank
                        ? Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))
                        : null,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isTopRank
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            position.toString(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        instructor,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isTopRank ? FontWeight.w600 : FontWeight.normal,
                          color: isTopRank
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      subtitle: isTopRank ? Text(
                        position == 1 ? 'Most preferred' :
                        position == 2 ? '2nd preference' :
                        '3rd preference',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ) : null,
                      trailing: Icon(
                        Icons.drag_handle,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightEntry {
  final String label;
  final double value;
  final double defaultValue;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  _WeightEntry(this.label, this.value, this.defaultValue, this.min, this.max, this.onChanged);
}
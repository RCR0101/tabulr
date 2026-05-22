import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../models/course.dart';
import '../models/timetable_constraints.dart';
import '../services/timetable_generator.dart';
import '../services/toast_service.dart';
import '../services/responsive_service.dart';
import '../services/campus_service.dart';
import '../utils/design_constants.dart';
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
  final List<String> _mandatoryCourses = [];
  final List<String> _optionalCourses = [];
  final List<TimeAvoidance> _avoidTimes = [];
  final List<LabAvoidance> _avoidLabs = [];
  int _maxHoursPerDay = 8;
  final List<String> _preferredInstructors = [];
  final List<String> _avoidedInstructors = [];
  bool _avoidBackToBack = false;
  bool _minimizeGaps = false;
  bool _protectLunchBreak = false;
  TimeOfDayPreference _timeOfDayPreference = TimeOfDayPreference.none;
  final List<DayOfWeek> _freeDayPreference = [];
  TimeSlot? _preferredMidsemSlot;
  TimeSlot? _preferredCompreSlot;
  List<GeneratedTimetable> _generatedTimetables = [];
  bool _isGenerating = false;
  final Map<String, InstructorRankings> _instructorRankings = {};
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
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
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
                    ],
                  ),
                ),
              ),
              // Fixed generate button at bottom
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
                if (_generatedTimetables.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_generatedTimetables.length} found',
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
            child: _generatedTimetables.isEmpty
                ? _buildEmptyResults()
                : _buildGeneratedTimetables(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            _isGenerating ? 'Generating timetables...' : 'No timetables generated yet',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isGenerating 
                ? 'This may take a few moments'
                : 'Select courses and click Generate to see results',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          if (_isGenerating) ...[
            const SizedBox(height: 16),
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseSelection() {
    final mandatoryCredits = _mandatoryCourses.fold(0.0, (sum, code) {
      final c = widget.availableCourses.firstWhere((c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []));
      return sum + c.totalCredits;
    });
    final optionalCredits = _optionalCourses.fold(0.0, (sum, code) {
      final c = widget.availableCourses.firstWhere((c) => c.courseCode == code,
        orElse: () => Course(courseCode: code, courseTitle: '', lectureCredits: 0, practicalCredits: 0, totalCredits: 0, sections: []));
      return sum + c.totalCredits;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mandatory Courses (${mandatoryCredits.toStringAsFixed(1)} credits):', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Must be included in every timetable', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
        const SizedBox(height: 8),
        _buildCourseSearchField(_mandatoryCourses, _optionalCourses),
        const SizedBox(height: 8),
        _buildCourseBadges(_mandatoryCourses, isMandatory: true),
        const SizedBox(height: 16),
        Text('Optional Courses (${optionalCredits.toStringAsFixed(1)} credits):', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Generator will fit as many as possible within credit limit', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
        const SizedBox(height: 8),
        _buildCourseSearchField(_optionalCourses, _mandatoryCourses),
        const SizedBox(height: 8),
        _buildCourseBadges(_optionalCourses, isMandatory: false),
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
          color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Center(
          child: Text(
            isMandatory ? 'No mandatory courses' : 'No optional courses',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
        color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
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
                    style: TextStyle(fontSize: ResponsiveService.clampedFontSize(context, 9), color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () {
                setState(() { courseList.remove(courseCode); });
              },
              backgroundColor: badgeColor.withOpacity(0.1),
              deleteIconColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: badgeColor.withOpacity(0.3), width: 1),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildConstraints() {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Constraints & Preferences:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        // Schedule group
        _buildConstraintGroup(
          icon: Icons.schedule,
          title: 'Schedule',
          children: [
            _buildRowConstraint('Max hours/day', SizedBox(
              width: 60,
              child: TextField(
                controller: TextEditingController(text: _maxHoursPerDay.toString()),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()),
                onChanged: (value) {
                  final hours = int.tryParse(value);
                  if (hours != null && hours > 0 && hours <= 12) _maxHoursPerDay = hours;
                },
              ),
            )),
            _buildCheckConstraint('Avoid back-to-back classes', _avoidBackToBack, (v) => setState(() { _avoidBackToBack = v ?? false; })),
            _buildCheckConstraint('Minimize gaps between classes', _minimizeGaps, (v) => setState(() { _minimizeGaps = v ?? false; })),
            _buildCheckConstraint('Protect lunch break (12–2 PM)', _protectLunchBreak, (v) => setState(() { _protectLunchBreak = v ?? false; })),
            _buildRowConstraint('Prefer classes in', DropdownButton<TimeOfDayPreference>(
              value: _timeOfDayPreference,
              isExpanded: true,
              underline: const SizedBox(),
              isDense: true,
              style: TextStyle(fontSize: 14, color: scheme.onSurface),
              items: const [
                DropdownMenuItem(value: TimeOfDayPreference.none, child: Text('No preference', style: TextStyle(fontSize: 14))),
                DropdownMenuItem(value: TimeOfDayPreference.morning, child: Text('Morning', style: TextStyle(fontSize: 14))),
                DropdownMenuItem(value: TimeOfDayPreference.afternoon, child: Text('Afternoon', style: TextStyle(fontSize: 14))),
              ],
              onChanged: (value) { setState(() { _timeOfDayPreference = value ?? TimeOfDayPreference.none; }); },
            )),
            const SizedBox(height: 8),
            _buildFreeDayRanking(),
            const SizedBox(height: 8),
            _buildTimeAvoidance(),
            const SizedBox(height: 8),
            _buildLabAvoidance(),
          ],
        ),
        const SizedBox(height: 8),

        // Instructors group
        _buildConstraintGroup(
          icon: Icons.person,
          title: 'Instructors',
          children: [
            _buildInstructorAvoidance(),
            const SizedBox(height: 8),
            _buildInstructorRanking(),
          ],
        ),
        const SizedBox(height: 8),

        // Exams group
        _buildConstraintGroup(
          icon: Icons.event,
          title: 'Exams',
          children: [
            _buildRowConstraint('Preferred midsem', DropdownButton<TimeSlot?>(
              value: _preferredMidsemSlot,
              hint: const Text('Any', style: TextStyle(fontSize: 14)),
              isExpanded: true,
              underline: const SizedBox(),
              isDense: true,
              style: TextStyle(fontSize: 14, color: scheme.onSurface),
              items: [
                const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any', style: TextStyle(fontSize: 14))),
                ...TimeSlotInfo.getMidSemSlots().map((slot) => DropdownMenuItem(
                  value: slot,
                  child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.currentCampusCode), style: const TextStyle(fontSize: 14)),
                )),
              ],
              onChanged: (value) { setState(() { _preferredMidsemSlot = value; }); },
            )),
            _buildRowConstraint('Preferred compre', DropdownButton<TimeSlot?>(
              value: _preferredCompreSlot,
              hint: const Text('Any', style: TextStyle(fontSize: 14)),
              isExpanded: true,
              underline: const SizedBox(),
              isDense: true,
              style: TextStyle(fontSize: 14, color: scheme.onSurface),
              items: [
                const DropdownMenuItem<TimeSlot?>(value: null, child: Text('Any', style: TextStyle(fontSize: 14))),
                ...TimeSlotInfo.getEndSemSlots().map((slot) => DropdownMenuItem(
                  value: slot,
                  child: Text(TimeSlotInfo.getTimeSlotName(slot, campus: CampusService.currentCampusCode), style: const TextStyle(fontSize: 14)),
                )),
              ],
              onChanged: (value) { setState(() { _preferredCompreSlot = value; }); },
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildConstraintGroup({required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, size: 18),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        dense: true,
        children: children,
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(child: trailing),
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
        .where((d) => !_freeDayPreference.contains(d))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Free day preference:', style: TextStyle(fontSize: 14)),
              const Spacer(),
              if (_freeDayPreference.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _freeDayPreference.clear();
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
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          if (_freeDayPreference.isNotEmpty) ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _freeDayPreference.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final day = _freeDayPreference.removeAt(oldIndex);
                  _freeDayPreference.insert(newIndex, day);
                });
              },
              itemBuilder: (context, index) {
                final day = _freeDayPreference[index];
                return Container(
                  key: ValueKey(day),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
                            _freeDayPreference.remove(day);
                          });
                        },
                        icon: const Icon(Icons.close, size: 14),
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
                      _freeDayPreference.add(day);
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
            const Text('Avoid time slots:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _addTimeAvoidance,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_avoidTimes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _avoidTimes.asMap().entries.map((entry) {
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
                        _avoidTimes.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
            const Text('Avoid labs on:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _addLabAvoidance,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_avoidLabs.isNotEmpty) ...[ 
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _avoidLabs.asMap().entries.map((entry) {
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
                        _avoidLabs.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.1),
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
            const Text('Avoid instructors:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _mandatoryCourses.isNotEmpty ? _addInstructorAvoidance : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_avoidedInstructors.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 80),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _avoidedInstructors.asMap().entries.map((entry) {
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
                        _avoidedInstructors.removeAt(index);
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.1),
                    deleteIconColor: AppDesign.danger(context),
                  );
                }).toList(),
              ),
            ),
          ),
        ] else if (_mandatoryCourses.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
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
            const Text('Rank instructors:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton(
              onPressed: _mandatoryCourses.isNotEmpty ? _showInstructorRankingDialog : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Rank', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_instructorRankings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
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
                        '${_instructorRankings.length} course${_instructorRankings.length == 1 ? '' : 's'}',
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
                          _instructorRankings.clear();
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
                      children: _instructorRankings.entries.map((entry) {
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
                                  Theme.of(context).colorScheme.primaryContainer.withOpacity(0.7),
                                  Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
                                    color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
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
        ] else if (_mandatoryCourses.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.3),
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
        _avoidTimes.add(result);
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
        _avoidLabs.add(result);
      });
    }
  }

  Future<void> _addInstructorAvoidance() async {
    // Get instructors organized by course and section type to avoid duplicates
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};
    final Set<String> seenInstructorsLower = <String>{};
    
    for (final courseCode in [..._mandatoryCourses, ..._optionalCourses]) {
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
        currentlyAvoided: _avoidedInstructors,
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
            if (!_avoidedInstructors.contains(instructor)) {
              _avoidedInstructors.add(instructor);
            }
          }
        }
      });
    }
  }

  Future<void> _showInstructorRankingDialog() async {
    // Get instructors organized by course and section type
    final Map<String, Map<String, List<String>>> courseSectionInstructors = {};
    
    for (final courseCode in [..._mandatoryCourses, ..._optionalCourses]) {
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
        currentRankings: Map.from(_instructorRankings),
      ),
    );
    
    if (result != null && mounted) {
      setState(() {
        _instructorRankings.clear();
        _instructorRankings.addAll(result);
      });
    }
  }

  Widget _buildGenerateButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: _mandatoryCourses.isNotEmpty && !_isGenerating
            ? LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _mandatoryCourses.isEmpty || _isGenerating
            ? Theme.of(context).colorScheme.surface
            : null,
      ),
      child: ElevatedButton(
        onPressed: _mandatoryCourses.isNotEmpty && !_isGenerating ? _generateTimetables : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isGenerating
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
                    color: _mandatoryCourses.isNotEmpty 
                        ? Theme.of(context).scaffoldBackgroundColor 
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Generate Timetables',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _mandatoryCourses.isNotEmpty 
                          ? Theme.of(context).scaffoldBackgroundColor 
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _generateTimetables() async {
    setState(() {
      _isGenerating = true;
    });
    
    // Switch to results tab on mobile when starting generation
    final isMobile = ResponsiveService.isMobile(context) || ResponsiveService.isTablet(context);
    if (isMobile && _tabController != null) {
      _tabController!.animateTo(1);
    }

    try {
      final constraints = TimetableConstraints(
        mandatoryCourses: _mandatoryCourses,
        optionalCourses: _optionalCourses,
        avoidTimes: _avoidTimes,
        avoidLabs: _avoidLabs,
        maxHoursPerDay: _maxHoursPerDay,
        preferredInstructors: _preferredInstructors,
        avoidedInstructors: _avoidedInstructors,
        avoidBackToBackClasses: _avoidBackToBack,
        instructorRankings: _instructorRankings,
        freeDayPreference: _freeDayPreference,
        minimizeGaps: _minimizeGaps,
        timeOfDayPreference: _timeOfDayPreference,
        protectLunchBreak: _protectLunchBreak,
        preferredMidsemSlot: _preferredMidsemSlot,
        preferredCompreSlot: _preferredCompreSlot,
      );

      final timetables = TimetableGenerator.generateTimetables(
        widget.availableCourses,
        constraints,
        maxTimetables: 30,
      );

      setState(() {
        _generatedTimetables = timetables;
        _isGenerating = false;
      });

      // Show alert if no timetables were generated
      if (timetables.isEmpty) {
        _showNoTimetablesDialog();
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      
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
                'Generated Timetables (${_generatedTimetables.length})',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _generatedTimetables.length,
                itemBuilder: (context, index) {
                  final timetable = _generatedTimetables[index];
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text('No Valid Timetables Found'),
          ],
        ),
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
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
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
              value: _selectedDay,
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
            Container(
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
        ElevatedButton(
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
              value: _selectedDay,
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
            Container(
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
                    selectedColor: Theme.of(context).colorScheme.error.withOpacity(0.3),
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
        ElevatedButton(
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
        width: 600,
        height: 500,
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
                                                            ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                                                            : null,
                                                      ),
                                                    ),
                                                    selected: isSelected,
                                                    selectedColor: Theme.of(context).colorScheme.error.withOpacity(0.3),
                                                    checkmarkColor: Theme.of(context).colorScheme.error,
                                                    backgroundColor: isAlreadyAvoided 
                                                        ? Theme.of(context).colorScheme.surface.withOpacity(0.5)
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
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
        ElevatedButton(
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
        width: 650,
        height: 550,
        child: Column(
          children: [
            Text(
              'Drag to reorder instructors from most preferred (top) to least preferred (bottom)',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Tab bar for courses
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
        ElevatedButton(
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
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
              ),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rankedInstructors.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
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
                        ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                        : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: isTopRank 
                        ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3))
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
                            : Theme.of(context).colorScheme.outline.withOpacity(0.6),
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
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
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
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
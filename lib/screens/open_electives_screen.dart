import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/course.dart';
import '../models/timetable_selection_link.dart';
import '../services/data/campus_service.dart';
import '../services/data/course_data_service.dart';
import '../services/data/discipline_electives_service.dart';
import '../services/data/open_electives_service.dart';
import '../services/data/profile_service.dart';
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
  final DisciplineElectivesService _branchListService =
      DisciplineElectivesService();
  final CourseDataService _courseDataService = CourseDataService();
  final TextEditingController _search = TextEditingController();

  List<BranchInfo> _availableBranches = [];
  BranchInfo? _selectedPrimaryBranch;
  BranchInfo? _selectedSecondaryBranch;

  List<Course> _openElectives = [];
  List<Course> _availableCourses = [];

  bool _isLoading = true;
  bool _isSearching = false;
  bool _hasSearched = false;
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

      final branches = await _branchListService
          .getAvailableBranches()
          .timeout(AppDurations.shortNetworkTimeout);

      // When linked to a timetable, browse that timetable's embedded catalog so
      // everything offered here is something it can actually accept.
      final courses = widget.selectionLink?.availableCourses ??
          await _courseDataService.fetchCourses();

      if (!mounted) return;
      setState(() {
        _availableBranches = branches;
        _availableCourses = courses;
        _isLoading = false;
        _prefillFromProfile(branches);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  /// Pre-selects the user's saved branches so the screen opens ready to search,
  /// without overwriting a choice already made.
  void _prefillFromProfile(List<BranchInfo> branches) {
    final profile = ProfileService().cached;
    BranchInfo? byCode(String? code) {
      if (code == null) return null;
      for (final b in branches) {
        if (b.code == code) return b;
      }
      return null;
    }

    _selectedPrimaryBranch ??= byCode(profile.primaryBranch);
    final secondary = byCode(profile.secondaryBranch);
    if (_selectedSecondaryBranch == null &&
        secondary != _selectedPrimaryBranch) {
      _selectedSecondaryBranch = secondary;
    }
  }

  Future<void> _viewOpenElectives() async {
    if (_selectedPrimaryBranch == null) {
      setState(() => _errorMessage = 'Please select a primary branch');
      return;
    }

    try {
      setState(() {
        _isSearching = true;
        _errorMessage = '';
        _openElectives = [];
      });

      final codes = [
        _selectedPrimaryBranch!.code,
        if (_selectedSecondaryBranch != null) _selectedSecondaryBranch!.code,
      ];
      final openElectives = await _openElectivesService
          .getOpenElectives(_availableCourses, codes)
          .timeout(AppDurations.networkTimeout);

      if (!mounted) return;
      setState(() {
        _openElectives = openElectives;
        _isSearching = false;
        _hasSearched = true;
      });

      if (openElectives.isEmpty) {
        setState(() => _errorMessage =
            'No open electives found for the selected branch(es).');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Unable to load open electives at this time. Please try again later.';
        _isSearching = false;
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

  Widget _buildBranchSelector(BuildContext context) {
    final subtitleColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open Electives (OPEL)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Every offered course outside the core (CDC), Discipline Elective '
              '(DEL) and Humanities Elective (HUEL) requirements of your '
              'branch. A DEL may also be counted as an OPEL once your DEL '
              'requirement is fulfilled, and a HUEL once your HUEL requirement '
              'is fulfilled.',
              style: TextStyle(fontSize: 13, height: 1.4, color: subtitleColor),
            ),
            const SizedBox(height: 16),

            // Primary branch (required)
            const Text('Primary Branch *',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            DropdownButtonFormField<BranchInfo>(
              initialValue: _selectedPrimaryBranch,
              decoration: const InputDecoration(
                labelText: 'Primary Branch',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              hint: _availableBranches.isEmpty
                  ? const Text('Loading branches...')
                  : const Text('Select primary branch'),
              items: _availableBranches
                  .map((b) =>
                      DropdownMenuItem(value: b, child: Text(b.name)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPrimaryBranch = value;
                  if (_selectedSecondaryBranch == value) {
                    _selectedSecondaryBranch = null;
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Secondary branch (optional)
            Row(
              children: [
                const Text('Secondary Branch (Optional)',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (_selectedSecondaryBranch != null)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _selectedSecondaryBranch = null),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<BranchInfo>(
              initialValue: _selectedSecondaryBranch,
              decoration: const InputDecoration(
                labelText: 'Secondary Branch',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              hint: const Text('Select secondary branch'),
              items: _availableBranches
                  .where((b) => b != _selectedPrimaryBranch)
                  .map((b) =>
                      DropdownMenuItem(value: b, child: Text(b.name)))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedSecondaryBranch = value),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (_selectedPrimaryBranch == null || _isSearching)
                        ? null
                        : _viewOpenElectives,
                child: _isSearching
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('View Open Electives'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection(BuildContext context) {
    final results = _filtered;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Open Electives',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _query.isEmpty
                      ? 'Found ${results.length} open electives for '
                          '${_selectedPrimaryBranch?.name ?? ''}'
                          '${_selectedSecondaryBranch != null ? ' and ${_selectedSecondaryBranch!.name}' : ''}'
                      : 'Found ${results.length} matching "$_query"',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                if (widget.selectionLink != null) ...[
                  const SizedBox(height: 4),
                  ElectiveTimetableBanner(selectionLink: widget.selectionLink),
                ],
                const SizedBox(height: 12),
                AppSearchField(
                  controller: _search,
                  hint: 'Search open electives by code or name…',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 400,
            child: ElectiveCourseList(
              courses: results,
              catalog: _availableCourses,
              selectionLink: widget.selectionLink,
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
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (_errorMessage.isNotEmpty)
                    InlineErrorCard(message: _errorMessage),
                  _buildBranchSelector(context),
                  if (_hasSearched && _openElectives.isNotEmpty)
                    _buildResultsSection(context),
                ],
              ),
            ),
    );
  }
}

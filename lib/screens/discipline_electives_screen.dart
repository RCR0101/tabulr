import 'dart:async';
import 'package:flutter/material.dart';
import '../services/discipline_electives_service.dart';
import '../services/course_data_service.dart';
import '../services/campus_service.dart';
import '../services/responsive_service.dart';
import '../models/course.dart';
import '../widgets/course_list_widget.dart';
import '../widgets/common/loading_state.dart';
import '../widgets/common/inline_error_card.dart';

class DisciplineElectivesScreen extends StatefulWidget {
  const DisciplineElectivesScreen({super.key});

  @override
  State<DisciplineElectivesScreen> createState() =>
      _DisciplineElectivesScreenState();
}

class _DisciplineElectivesScreenState extends State<DisciplineElectivesScreen> {
  final DisciplineElectivesService _disciplineElectivesService =
      DisciplineElectivesService();
  final CourseDataService _courseDataService = CourseDataService();

  List<BranchInfo> _availableBranches = [];
  List<DisciplineElective> _disciplineElectives = [];
  List<Course> _availableCourses = [];

  BranchInfo? _selectedPrimaryBranch;
  BranchInfo? _selectedSecondaryBranch;
  String? _selectedSemester;

  bool _isLoading = true;
  bool _isSearching = false;
  String _errorMessage = '';
  StreamSubscription<Campus>? _campusSubscription;

  // Semester options from 2-1 to 4-2
  final List<String> _semesterOptions = [
    '2-1',
    '2-2',
    '3-1',
    '3-2',
    '4-1',
    '4-2',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    // Listen for campus changes
    _campusSubscription = CampusService.campusChangeStream.listen((_) {
      print('Campus changed, reloading disciplinary electives data...');
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _campusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // Load available branches
      print('Loading available branches...');
      final branches = await _disciplineElectivesService
          .getAvailableBranches()
          .timeout(Duration(seconds: 15));
      print(
        'Loaded ${branches.length} branches: ${branches.map((b) => b.name).join(', ')}',
      );

      // Load courses for current campus
      print('Loading courses for current campus...');
      final courses = await _courseDataService.fetchCourses();
      print(
        'Loaded ${courses.length} courses for ${CampusService.getCampusDisplayName(CampusService.currentCampus)} campus',
      );

      setState(() {
        _availableBranches = branches;
        _availableCourses = courses;
        _isLoading = false;
      });
    } catch (e) {
      print('Error in _loadInitialData: $e');
      setState(() {
        _errorMessage = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _viewAllDisciplineElectives() async {
    if (_selectedPrimaryBranch == null) {
      setState(() {
        _errorMessage = 'Please select primary branch';
      });
      return;
    }

    try {
      setState(() {
        _isSearching = true;
        _errorMessage = '';
        _disciplineElectives = [];
      });

      print('Fetching all discipline electives without clash filtering');

      final electives = await _disciplineElectivesService
          .getAllDisciplineElectives(
            _selectedPrimaryBranch!.code,
            _selectedSecondaryBranch?.code,
            _availableCourses,
          );

      setState(() {
        _disciplineElectives = electives;
        _isSearching = false;
      });

      if (electives.isEmpty) {
        setState(() {
          _errorMessage =
              'No discipline electives found for the selected branch(es).';
        });
      }
    } catch (e) {
      print('Error in _viewAllDisciplineElectives: $e');
      setState(() {
        _errorMessage =
            'Unable to load discipline electives at this time. Please try again later.';
        _isSearching = false;
      });
    }
  }

  Future<void> _searchDisciplineElectives() async {
    if (_selectedPrimaryBranch == null || _selectedSemester == null) {
      setState(() {
        _errorMessage = 'Please select primary branch and semester';
      });
      return;
    }

    try {
      setState(() {
        _isSearching = true;
        _errorMessage = '';
        _disciplineElectives = [];
      });

      print(
        'Searching electives for: ${_selectedPrimaryBranch!.name} ${_selectedSemester!}${_selectedSecondaryBranch != null ? ' and ${_selectedSecondaryBranch!.name} ${_selectedSemester!}' : ''}',
      );

      final electives = await _disciplineElectivesService
          .getFilteredDisciplineElectivesWithClashDetection(
            _selectedPrimaryBranch!.code,
            _selectedSecondaryBranch?.code,
            _selectedSemester!,
            _selectedSemester,
            _availableCourses,
          )
          .timeout(Duration(seconds: 20));

      print('Found ${electives.length} electives');

      setState(() {
        _disciplineElectives = electives;
        _isSearching = false;
      });

      if (electives.isEmpty) {
        setState(() {
          _errorMessage =
              'No discipline electives found for the selected branch(es) and semester(s) that are available and don\'t clash with core courses.';
        });
      }
    } catch (e) {
      print('Error in _searchDisciplineElectives: $e');
      setState(() {
        _errorMessage =
            'Unable to load discipline electives at this time. Please try again later.';
        _isSearching = false;
      });
    }
  }

  void _clearSecondarySelections() {
    setState(() {
      _selectedSecondaryBranch = null;
    });
  }

  Widget _buildBranchSelector() {
    final isMobile = ResponsiveService.isMobile(context);
    final titleFontSize = ResponsiveService.getAdaptiveFontSize(context, 18);
    final labelFontSize = ResponsiveService.getAdaptiveFontSize(context, 14);
    final subtitleFontSize = ResponsiveService.getAdaptiveFontSize(context, 12);
    final iconSize = ResponsiveService.getAdaptiveIconSize(context, 16);
    final progressSize = ResponsiveService.getAdaptiveIconSize(context, 20);
    final touchTarget = ResponsiveService.getTouchTargetSize(context);
    final subtitleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    final titleText = Text(
      isMobile ? 'Select Branches & Semesters' : 'Select Branch(es) and Semester(s)',
      style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
    );
    final subtitleText = Text(
      '${_availableBranches.length} branches loaded',
      style: TextStyle(fontSize: subtitleFontSize, color: subtitleColor),
    );

    // Shared dropdown builder for branch selectors
    Widget buildBranchDropdown({
      required BranchInfo? value,
      required String label,
      required String hint,
      required List<BranchInfo> branches,
      required ValueChanged<BranchInfo?> onChanged,
    }) {
      final dropdown = DropdownButtonFormField<BranchInfo>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,

          contentPadding: ResponsiveService.getAdaptivePadding(
            context,
            const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          ),
        ),
        items: branches.isEmpty
            ? []
            : branches.map((branch) {
                return DropdownMenuItem<BranchInfo>(
                  value: branch,
                  child: Text(
                    branch.name,
                    style: TextStyle(fontSize: labelFontSize),
                  ),
                );
              }).toList(),
        onChanged: (BranchInfo? newValue) {
          ResponsiveService.triggerSelectionFeedback(context);
          onChanged(newValue);
        },
        isExpanded: true,
        hint: branches.isEmpty ? const Text('Loading branches...') : Text(hint),
      );
      // On mobile the dropdown fills the width naturally; on tablet/desktop
      // wrap it in a Row > Expanded so it behaves the same as before.
      if (isMobile) return dropdown;
      return Row(children: [Expanded(child: dropdown)]);
    }

    return Card(
      margin: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      child: Padding(
        padding: ResponsiveService.getAdaptivePadding(
          context,
          const EdgeInsets.all(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: title + branch count
            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleText,
                  SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 4)),
                  subtitleText,
                ],
              )
            else
              Row(
                children: [titleText, const Spacer(), subtitleText],
              ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),

            // Semester Selection
            Text(
              'Semester *',
              style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            DropdownButtonFormField<String>(
              initialValue: _selectedSemester,
              decoration: InputDecoration(
                labelText: 'Semester',
      
                contentPadding: ResponsiveService.getAdaptivePadding(
                  context,
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
              ),
              items: _semesterOptions.map((semester) {
                return DropdownMenuItem<String>(
                  value: semester,
                  child: Text(semester),
                );
              }).toList(),
              onChanged: (String? newValue) {
                ResponsiveService.triggerSelectionFeedback(context);
                setState(() {
                  _selectedSemester = newValue;
                });
              },
              isExpanded: true,
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),

            // Primary Branch Selection
            Text(
              'Primary Branch *',
              style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
            buildBranchDropdown(
              value: _selectedPrimaryBranch,
              label: 'Primary Branch',
              hint: 'Select primary branch',
              branches: _availableBranches,
              onChanged: (newValue) {
                setState(() {
                  _selectedPrimaryBranch = newValue;
                  if (_selectedSecondaryBranch == newValue) {
                    _selectedSecondaryBranch = null;
                  }
                });
              },
            ),

            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 16)),

            // Secondary Branch label + clear button
            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Secondary Branch (Optional)',
                    style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w500),
                  ),
                  if (_selectedSecondaryBranch != null) ...[
                    SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          ResponsiveService.triggerSelectionFeedback(context);
                          _clearSecondarySelections();
                        },
                        icon: Icon(Icons.clear, size: iconSize),
                        label: const Text('Clear'),
                        style: TextButton.styleFrom(
                          padding: ResponsiveService.getAdaptivePadding(
                            context,
                            const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          minimumSize: Size(0, touchTarget),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              Row(
                children: [
                  Text(
                    'Secondary Branch (Optional)',
                    style: TextStyle(fontSize: labelFontSize, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  if (_selectedSecondaryBranch != null)
                    TextButton.icon(
                      onPressed: () {
                        ResponsiveService.triggerSelectionFeedback(context);
                        _clearSecondarySelections();
                      },
                      icon: Icon(Icons.clear, size: iconSize),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size(0, touchTarget),
                      ),
                    ),
                ],
              ),
            SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 8)),

            // Secondary Branch dropdown
            buildBranchDropdown(
              value: _selectedSecondaryBranch,
              label: 'Secondary Branch',
              hint: 'Select secondary branch',
              branches: _availableBranches
                  .where((branch) => branch != _selectedPrimaryBranch)
                  .toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedSecondaryBranch = newValue;
                });
              },
            ),

            const SizedBox(height: 16),

            // Search Buttons
            _buildSearchButtons(
              isMobile: isMobile,
              touchTarget: touchTarget,
              progressSize: progressSize,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButtons({
    required bool isMobile,
    required double touchTarget,
    required double progressSize,
  }) {
    final searchButton = ElevatedButton(
      onPressed: (_selectedPrimaryBranch == null ||
              _selectedSemester == null ||
              _isSearching)
          ? null
          : () {
              ResponsiveService.triggerMediumFeedback(context);
              _searchDisciplineElectives();
            },
      style: ElevatedButton.styleFrom(
        minimumSize: Size(isMobile ? double.infinity : 0, touchTarget),
      ),
      child: _isSearching
          ? SizedBox(
              height: progressSize,
              width: progressSize,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Search (No Clashes)'),
    );

    final viewAllButton = OutlinedButton(
      onPressed: (_selectedPrimaryBranch == null || _isSearching)
          ? null
          : () {
              ResponsiveService.triggerLightFeedback(context);
              _viewAllDisciplineElectives();
            },
      style: OutlinedButton.styleFrom(
        minimumSize: Size(isMobile ? double.infinity : 0, touchTarget),
      ),
      child: const Text('View All'),
    );

    if (isMobile) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: searchButton),
          SizedBox(height: ResponsiveService.getAdaptiveSpacing(context, 12)),
          SizedBox(width: double.infinity, child: viewAllButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: searchButton),
        SizedBox(width: ResponsiveService.getAdaptiveSpacing(context, 8)),
        Expanded(flex: 2, child: viewAllButton),
      ],
    );
  }

  Widget _buildResultsSection() {
    if (_disciplineElectives.isEmpty) {
      return const SizedBox.shrink();
    }

    // Convert discipline electives to courses for display
    final courses =
        _disciplineElectives
            .map((elective) {
              final course = _disciplineElectivesService.getCourseDetails(
                elective.courseCode,
                _availableCourses,
              );
              return course;
            })
            .where((course) => course != null)
            .cast<Course>()
            .toList();

    return Card(
      margin: ResponsiveService.getAdaptivePadding(
        context,
        const EdgeInsets.all(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: ResponsiveService.getAdaptivePadding(
              context,
              const EdgeInsets.all(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discipline Electives',
                  style: TextStyle(
                    fontSize: ResponsiveService.getAdaptiveFontSize(
                      context,
                      18,
                    ),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(
                  height: ResponsiveService.getAdaptiveSpacing(context, 8),
                ),
                Text(
                  'Found ${_disciplineElectives.length} discipline electives for ${_selectedPrimaryBranch?.name} ${_selectedSemester ?? ''}${_selectedSecondaryBranch != null ? ' and ${_selectedSecondaryBranch?.name} ${_selectedSemester ?? ''}' : ''}',
                  style: TextStyle(
                    fontSize: ResponsiveService.getAdaptiveFontSize(
                      context,
                      14,
                    ),
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                if (_disciplineElectives.length != courses.length) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Note: ${_disciplineElectives.length - courses.length} electives are not available in current semester',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (courses.isNotEmpty) ...[
            const Divider(height: 1),
            SizedBox(
              height: ResponsiveService.getValue(
                context,
                mobile: 300,
                tablet: 350,
                desktop: 400,
              ),
              child: CourseListWidget(
                courses: courses,
                selectedSections: const [],
                onSectionToggle: (courseCode, sectionId, isSelected) {
                  // Read-only mode - no section toggles allowed
                },
              ),
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No discipline electives are available in the current semester.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discipline Electives'),
      ),
      body:
          _isLoading
              ? const LoadingStateWidget()
              : SingleChildScrollView(
                child: Column(
                  children: [
                    if (_errorMessage.isNotEmpty)
                      InlineErrorCard(message: _errorMessage),
                    _buildBranchSelector(),
                    _buildResultsSection(),
                  ],
                ),
              ),
    );
  }
}

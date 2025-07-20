import 'dart:async';
import 'package:flutter/material.dart';
import '../services/discipline_electives_service.dart';
import '../services/course_data_service.dart';
import '../services/campus_service.dart';
import '../models/course.dart';
import '../widgets/course_list_widget.dart';

class DisciplineElectivesScreen extends StatefulWidget {
  const DisciplineElectivesScreen({super.key});

  @override
  State<DisciplineElectivesScreen> createState() => _DisciplineElectivesScreenState();
}

class _DisciplineElectivesScreenState extends State<DisciplineElectivesScreen> {
  final DisciplineElectivesService _disciplineElectivesService = DisciplineElectivesService();
  final CourseDataService _courseDataService = CourseDataService();
  
  List<BranchInfo> _availableBranches = [];
  List<DisciplineElective> _disciplineElectives = [];
  List<Course> _availableCourses = [];
  
  BranchInfo? _selectedPrimaryBranch;
  BranchInfo? _selectedSecondaryBranch;
  
  bool _isLoading = true;
  bool _isSearching = false;
  String _errorMessage = '';
  StreamSubscription<Campus>? _campusSubscription;

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
      final branches = await _disciplineElectivesService.getAvailableBranches()
          .timeout(Duration(seconds: 15));
      print('Loaded ${branches.length} branches: ${branches.map((b) => b.name).join(', ')}');
      
      // Load courses for current campus
      print('Loading courses for current campus...');
      final courses = await _courseDataService.fetchCourses();
      print('Loaded ${courses.length} courses for ${CampusService.getCampusDisplayName(CampusService.currentCampus)} campus');
      
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

  Future<void> _searchDisciplineElectives() async {
    if (_selectedPrimaryBranch == null) {
      setState(() {
        _errorMessage = 'Please select a primary branch';
      });
      return;
    }

    try {
      setState(() {
        _isSearching = true;
        _errorMessage = '';
        _disciplineElectives = [];
      });

      print('Searching electives for: ${_selectedPrimaryBranch!.name}${_selectedSecondaryBranch != null ? ' and ${_selectedSecondaryBranch!.name}' : ''}');

      final electives = await _disciplineElectivesService.getFilteredDisciplineElectives(
        _selectedPrimaryBranch!.name,
        _selectedSecondaryBranch?.name,
        _availableCourses,
      ).timeout(Duration(seconds: 20));

      print('Found ${electives.length} electives');

      setState(() {
        _disciplineElectives = electives;
        _isSearching = false;
      });

      if (electives.isEmpty) {
        setState(() {
          _errorMessage = 'No discipline electives found for the selected branch(es) that are available in the current semester.';
        });
      }
    } catch (e) {
      print('Error in _searchDisciplineElectives: $e');
      setState(() {
        _errorMessage = 'Unable to load discipline electives at this time. Please try again later.';
        _isSearching = false;
      });
    }
  }

  void _clearSecondaryBranch() {
    setState(() {
      _selectedSecondaryBranch = null;
    });
  }



  Widget _buildBranchSelector() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Select Branch(es)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_availableBranches.length} branches loaded',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Primary Branch Selector
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<BranchInfo>(
                    value: _selectedPrimaryBranch,
                    decoration: const InputDecoration(
                      labelText: 'Primary Branch *',
                      border: OutlineInputBorder(),
                    ),
                    items: _availableBranches.isEmpty ? [] : _availableBranches.map((branch) {
                      return DropdownMenuItem<BranchInfo>(
                        value: branch,
                        child: Text(
                          branch.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (BranchInfo? newValue) {
                      setState(() {
                        _selectedPrimaryBranch = newValue;
                        // Clear secondary branch if it's same as primary
                        if (_selectedSecondaryBranch == newValue) {
                          _selectedSecondaryBranch = null;
                        }
                      });
                    },
                    isExpanded: true,
                    hint: _availableBranches.isEmpty 
                        ? const Text('Loading branches...')
                        : const Text('Select primary branch'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Secondary Branch Selector
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<BranchInfo>(
                    value: _selectedSecondaryBranch,
                    decoration: const InputDecoration(
                      labelText: 'Secondary Branch (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: _availableBranches.where((branch) {
                      return branch != _selectedPrimaryBranch;
                    }).map((branch) {
                      return DropdownMenuItem<BranchInfo>(
                        value: branch,
                        child: Text(
                          branch.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (BranchInfo? newValue) {
                      setState(() {
                        _selectedSecondaryBranch = newValue;
                      });
                    },
                    isExpanded: true,
                    hint: const Text('Select secondary branch'),
                  ),
                ),
                if (_selectedSecondaryBranch != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSecondaryBranch,
                    tooltip: 'Clear secondary branch',
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Search Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedPrimaryBranch == null || _isSearching
                    ? null
                    : _searchDisciplineElectives,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isSearching
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Search Discipline Electives'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_disciplineElectives.isEmpty) {
      return const SizedBox.shrink();
    }

    // Convert discipline electives to courses for display
    final courses = _disciplineElectives.map((elective) {
      final course = _disciplineElectivesService.getCourseDetails(
        elective.courseCode,
        _availableCourses,
      );
      return course;
    }).where((course) => course != null).cast<Course>().toList();

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
                  'Discipline Electives',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Found ${_disciplineElectives.length} discipline electives for ${_selectedPrimaryBranch?.name}${_selectedSecondaryBranch != null ? ' and ${_selectedSecondaryBranch?.name}' : ''}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
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
              height: 400,
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
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                ),
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
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (_errorMessage.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.all(16),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _buildBranchSelector(),
                  _buildResultsSection(),
                ],
              ),
            ),
    );
  }
}
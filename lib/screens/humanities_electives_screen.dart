import 'dart:async';
import 'package:flutter/material.dart';
import '../services/humanities_electives_service.dart';
import '../services/course_data_service.dart';
import '../services/campus_service.dart';
import '../models/course.dart';
import '../widgets/course_list_widget.dart';

class HumanitiesElectivesScreen extends StatefulWidget {
  const HumanitiesElectivesScreen({super.key});

  @override
  State<HumanitiesElectivesScreen> createState() => _HumanitiesElectivesScreenState();
}

class _HumanitiesElectivesScreenState extends State<HumanitiesElectivesScreen> {
  final HumanitiesElectivesService _humanitiesElectivesService = HumanitiesElectivesService();
  final CourseDataService _courseDataService = CourseDataService();
  
  List<Course> _huelCourses = [];
  List<Course> _availableCourses = [];
  
  String? _selectedPrimarySemester;
  String? _selectedPrimaryBranch;
  String? _selectedSecondarySemester;
  String? _selectedSecondaryBranch;
  
  bool _isLoading = true;
  bool _isSearching = false;
  String _errorMessage = '';
  StreamSubscription<Campus>? _campusSubscription;

  // Semester options from 2-1 to 4-2
  final List<String> _semesterOptions = [
    '2-1', '2-2', '3-1', '3-2', '4-1', '4-2'
  ];

  // Branch options (common engineering branches)
  final List<String> _branchOptions = [
    'A1', 'A2', 'A3', 'A4', 'A5', 'A7', 'A8', 'AA', 'AB', 'AD',
    'B1', 'B2', 'B3', 'B4', 'B5',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    
    // Listen for campus changes
    _campusSubscription = CampusService.campusChangeStream.listen((_) {
      print('Campus changed, reloading humanities electives data...');
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
      
      // Load courses for current campus
      print('Loading courses for current campus...');
      final courses = await _courseDataService.fetchCourses();
      print('Loaded ${courses.length} courses for ${CampusService.getCampusDisplayName(CampusService.currentCampus)} campus');
      
      setState(() {
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

  Future<void> _searchHumanitiesElectives() async {
    if (_selectedPrimarySemester == null || _selectedPrimaryBranch == null) {
      setState(() {
        _errorMessage = 'Please select primary semester and branch';
      });
      return;
    }

    try {
      setState(() {
        _isSearching = true;
        _errorMessage = '';
        _huelCourses = [];
      });

      print('Searching HUEL courses for: ${_selectedPrimaryBranch!} ${_selectedPrimarySemester!}${_selectedSecondaryBranch != null && _selectedSecondarySemester != null ? ' and ${_selectedSecondaryBranch!} ${_selectedSecondarySemester!}' : ''}');

      final huelCourses = await _humanitiesElectivesService.getFilteredHumanitiesElectives(
        _selectedPrimarySemester!,
        _selectedPrimaryBranch!,
        _selectedSecondarySemester,
        _selectedSecondaryBranch,
        _availableCourses,
      ).timeout(Duration(seconds: 20));

      print('Found ${huelCourses.length} HUEL courses');

      setState(() {
        _huelCourses = huelCourses;
        _isSearching = false;
      });

      if (huelCourses.isEmpty) {
        setState(() {
          _errorMessage = 'No humanities electives found for the selected branch(es) and semester(s) that are available and don\'t clash with core courses.';
        });
      }
    } catch (e) {
      print('Error in _searchHumanitiesElectives: $e');
      setState(() {
        _errorMessage = 'Unable to load humanities electives at this time. Please try again later.';
        _isSearching = false;
      });
    }
  }

  void _clearSecondarySelections() {
    setState(() {
      _selectedSecondaryBranch = null;
      _selectedSecondarySemester = null;
    });
  }

  Widget _buildInputForm() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Find Humanities Electives (HUEL)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Primary Selection
            const Text(
              'Primary Branch and Semester *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedPrimaryBranch,
                    decoration: const InputDecoration(
                      labelText: 'Primary Branch',
                      border: OutlineInputBorder(),
                    ),
                    items: _branchOptions.map((branch) {
                      return DropdownMenuItem<String>(
                        value: branch,
                        child: Text(branch),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedPrimaryBranch = newValue;
                      });
                    },
                    isExpanded: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedPrimarySemester,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(),
                    ),
                    items: _semesterOptions.map((semester) {
                      return DropdownMenuItem<String>(
                        value: semester,
                        child: Text(semester),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedPrimarySemester = newValue;
                      });
                    },
                    isExpanded: true,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Secondary Selection (Optional)
            Row(
              children: [
                const Text(
                  'Secondary Branch and Semester (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (_selectedSecondaryBranch != null || _selectedSecondarySemester != null)
                  TextButton.icon(
                    onPressed: _clearSecondarySelections,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSecondaryBranch,
                    decoration: const InputDecoration(
                      labelText: 'Secondary Branch',
                      border: OutlineInputBorder(),
                    ),
                    items: _branchOptions.where((branch) {
                      return branch != _selectedPrimaryBranch;
                    }).map((branch) {
                      return DropdownMenuItem<String>(
                        value: branch,
                        child: Text(branch),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedSecondaryBranch = newValue;
                      });
                    },
                    isExpanded: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSecondarySemester,
                    decoration: const InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(),
                    ),
                    items: _semesterOptions.where((semester) {
                      return semester != _selectedPrimarySemester;
                    }).map((semester) {
                      return DropdownMenuItem<String>(
                        value: semester,
                        child: Text(semester),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedSecondarySemester = newValue;
                      });
                    },
                    isExpanded: true,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Search Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selectedPrimaryBranch == null || _selectedPrimarySemester == null || _isSearching)
                    ? null
                    : _searchHumanitiesElectives,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isSearching
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Search Humanities Electives'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_huelCourses.isEmpty) {
      return const SizedBox.shrink();
    }

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
                  'Humanities Electives (HUEL)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Found ${_huelCourses.length} humanities electives for ${_selectedPrimaryBranch!} ${_selectedPrimarySemester!}${_selectedSecondaryBranch != null && _selectedSecondarySemester != null ? ' and ${_selectedSecondaryBranch!} ${_selectedSecondarySemester!}' : ''}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'These courses don\'t clash with your core curriculum',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 400,
            child: CourseListWidget(
              courses: _huelCourses,
              selectedSections: const [],
              onSectionToggle: (courseCode, sectionId, isSelected) {
                // Read-only mode - no section toggles allowed
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Humanities Electives'),
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
                  _buildInputForm(),
                  _buildResultsSection(),
                ],
              ),
            ),
    );
  }
}
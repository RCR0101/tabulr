import 'dart:async';
import 'package:flutter/material.dart';
import '../services/humanities_electives_service.dart';
import '../services/course_data_service.dart';
import '../services/campus_service.dart';
import '../services/secure_logger.dart';
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
  
  String? _selectedSemester;
  String? _selectedPrimaryBranch;
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
      final courses = await _courseDataService.fetchCourses();
      
      setState(() {
        _availableCourses = courses;
        _isLoading = false;
      });
    } catch (e) {
      SecureLogger.error('HUMANITIES', 'Failed to load initial data', e);
      setState(() {
        _errorMessage = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _viewAllHumanitiesElectives() async {
    try {
      setState(() {
        _isSearching = true;
        _errorMessage = '';
        _huelCourses = [];
      });

      
      final huelCourses = await _humanitiesElectivesService.getAllHumanitiesElectives(
        _availableCourses,
      );

      setState(() {
        _huelCourses = huelCourses;
        _isSearching = false;
      });

      if (huelCourses.isEmpty) {
        setState(() {
          _errorMessage = 'No humanities electives found in the current semester.';
        });
      }
    } catch (e) {
      SecureLogger.error('HUMANITIES', 'Failed to load all humanities electives', e);
      setState(() {
        _errorMessage = 'Unable to load humanities electives at this time. Please try again later.';
        _isSearching = false;
      });
    }
  }

  Future<void> _searchHumanitiesElectives() async {
    if (_selectedSemester == null || _selectedPrimaryBranch == null) {
      setState(() {
        _errorMessage = 'Please select semester and primary branch';
      });
      return;
    }

    try {
      setState(() {
        _isSearching = true;
        _errorMessage = '';
        _huelCourses = [];
      });


      final huelCourses = await _humanitiesElectivesService.getFilteredHumanitiesElectives(
        _selectedSemester!,
        _selectedPrimaryBranch!,
        _selectedSemester,
        _selectedSecondaryBranch,
        _availableCourses,
      ).timeout(Duration(seconds: 20));


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
      SecureLogger.error('HUMANITIES', 'Failed to search humanities electives', e);
      setState(() {
        _errorMessage = 'Unable to load humanities electives at this time. Please try again later.';
        _isSearching = false;
      });
    }
  }

  void _clearSecondarySelections() {
    setState(() {
      _selectedSecondaryBranch = null;
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
            
            // Semester Selection
            const Text(
              'Semester *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedSemester,
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
                  _selectedSemester = newValue;
                });
              },
              isExpanded: true,
            ),
            const SizedBox(height: 16),
            
            // Primary Branch Selection
            const Text(
              'Primary Branch *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
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
            
            const SizedBox(height: 16),
            
            // Secondary Branch Selection (Optional)
            Row(
              children: [
                const Text(
                  'Secondary Branch (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (_selectedSecondaryBranch != null)
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
            DropdownButtonFormField<String>(
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
            
            const SizedBox(height: 16),
            
            // Search Buttons
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: (_selectedPrimaryBranch == null || _selectedSemester == null || _isSearching)
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
                        : const Text('Search (No Clashes)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: _isSearching ? null : _viewAllHumanitiesElectives,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('View All'),
                  ),
                ),
              ],
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
                  'Found ${_huelCourses.length} humanities electives for ${_selectedPrimaryBranch!} ${_selectedSemester!}${_selectedSecondaryBranch != null ? ' and ${_selectedSecondaryBranch!} ${_selectedSemester!}' : ''}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
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
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/timetable.dart';
import '../services/timetable_service.dart';
import '../services/course_utils.dart';
import '../services/export_service.dart';
import '../services/auth_service.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/courses_tab_widget.dart';
import '../widgets/timetable_widget.dart';
import '../widgets/clash_warnings_widget.dart';
import '../widgets/search_filter_widget.dart';
import 'generator_screen.dart';
import 'timetables_screen.dart';
import '../models/timetable.dart' as timetable;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class HomeScreenWithTimetable extends StatefulWidget {
  final Timetable timetable;
  
  const HomeScreenWithTimetable({super.key, required this.timetable});

  @override
  State<HomeScreenWithTimetable> createState() => _HomeScreenWithTimetableState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TimetableService _timetableService = TimetableService();
  final AuthService _authService = AuthService();
  final GlobalKey _timetableKey = GlobalKey();
  Timetable? _timetable;
  List<Course> _filteredCourses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTimetable();
  }

  Future<void> _loadTimetable() async {
    try {
      final timetable = await _timetableService.loadTimetable();
      
      setState(() {
        _timetable = timetable;
        _filteredCourses = timetable.availableCourses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      // Show more helpful error message for missing course data
      String errorMessage = 'Error loading timetable: $e';
      if (e.toString().contains('No course data available')) {
        errorMessage = 'Course data is not available. Please contact the administrator to upload the latest timetable data.';
      }
      
      _showErrorDialog(errorMessage);
    }
  }

  void _onSearchChanged(String query, Map<String, dynamic> filters) {
    if (_timetable == null) return;
    
    setState(() {
      var courses = _timetable!.availableCourses;
      
      // Apply text search
      courses = CourseUtils.searchCourses(courses, query);
      
      // Apply instructor filter
      if (filters['instructor'] != null && filters['instructor'].toString().isNotEmpty) {
        courses = CourseUtils.filterByInstructor(courses, filters['instructor']);
      }
      
      // Apply credits filter
      courses = CourseUtils.filterByCredits(courses, filters['minCredits'], filters['maxCredits']);
      
      // Apply days filter
      if (filters['days'] != null && (filters['days'] as List<DayOfWeek>).isNotEmpty) {
        courses = CourseUtils.filterByDays(courses, filters['days']);
      }
      
      // Apply exam date filters
      if (filters['midSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(courses, filters['midSemDate'], true);
      }
      
      if (filters['endSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(courses, filters['endSemDate'], false);
      }
      
      _filteredCourses = courses;
    });
  }

  Future<void> _addSection(String courseCode, String sectionId) async {
    if (_timetable == null) return;

    try {
      final success = await _timetableService.addSection(courseCode, sectionId, _timetable!);
      if (success) {
        setState(() {});
      } else {
        final course = _timetable!.availableCourses.firstWhere((c) => c.courseCode == courseCode);
        final section = course.sections.firstWhere((s) => s.sectionId == sectionId);
        
        // Check specific reason for failure
        final existingSameType = _timetable!.selectedSections.where(
          (s) => s.courseCode == courseCode && s.section.type == section.type
        );
        
        if (existingSameType.isNotEmpty) {
          _showErrorDialog('You can only select one ${section.type.name} section per course.\nAlready selected: ${existingSameType.first.sectionId}');
        } else {
          _showErrorDialog('Cannot add section due to time conflicts or exam clashes');
        }
      }
    } catch (e) {
      _showErrorDialog('Error adding section: $e');
    }
  }

  Future<void> _removeSection(String courseCode, String sectionId) async {
    if (_timetable == null) return;

    try {
      await _timetableService.removeSection(courseCode, sectionId, _timetable!);
      setState(() {});
    } catch (e) {
      _showErrorDialog('Error removing section: $e');
    }
  }

  Future<void> _clearTimetable() async {
    if (_timetable == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Timetable'),
        content: const Text('Are you sure you want to remove all selected courses from your timetable?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        _timetable!.selectedSections.clear();
        _timetable!.clashWarnings.clear();
        setState(() {});
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timetable cleared successfully')),
        );
      } catch (e) {
        _showErrorDialog('Error clearing timetable: $e');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToICS() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToICS(
        _timetable!.selectedSections,
        _timetable!.availableCourses,
      );
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('Timetable exported to: $filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _exportToPNG() async {
    if (_timetable == null || _timetable!.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    // Show dialog to choose export location
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export PNG'),
        content: const Text('Choose export location:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Default Location'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose Location'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      String? customPath;
      
      if (result) {
        // Let user choose custom location
        final selectedDirectory = await FilePicker.platform.getDirectoryPath();
        if (selectedDirectory != null) {
          customPath = '$selectedDirectory/timetable.png';
        } else {
          return; // User cancelled
        }
      }

      final filePath = await ExportService.exportToPNG(_timetableKey, customPath: customPath);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('Timetable exported to: $filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _openGenerator() async {
    final result = await Navigator.push<List<timetable.SelectedSection>>(
      context,
      MaterialPageRoute(
        builder: (context) => const GeneratorScreen(),
      ),
    );

    if (result != null && _timetable != null) {
      try {
        // Clear current selections
        _timetable!.selectedSections.clear();
        
        // Add new selections from generator
        for (final section in result) {
          await _timetableService.addSection(
            section.courseCode,
            section.sectionId,
            _timetable!,
          );
        }
        
        setState(() {});
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Generated timetable applied successfully!')),
        );
      } catch (e) {
        _showErrorDialog('Error applying generated timetable: $e');
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _authService.signOut();
        // Navigation will be handled by AuthWrapper
      } catch (e) {
        _showErrorDialog('Error signing out: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_timetable == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tabulr')),
        body: const Center(
          child: Text('Failed to load timetable'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabulr'),
        centerTitle: true,
        actions: [
          if (_timetable?.selectedSections.isNotEmpty == true)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearTimetable,
              tooltip: 'Clear Timetable',
            ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _exportToICS,
            tooltip: 'Export to ICS',
          ),
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _exportToPNG,
            tooltip: 'Export to PNG',
          ),
          // User info and logout
          if (_authService.isAuthenticated)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') {
                  _logout();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _authService.userName ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _authService.userEmail ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const Divider(),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Sign Out'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: _authService.userPhotoUrl != null
                          ? NetworkImage(_authService.userPhotoUrl!)
                          : null,
                      child: _authService.userPhotoUrl == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Guest',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: Column(
              children: [
                SearchFilterWidget(
                  onSearchChanged: _onSearchChanged,
                ),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: CoursesTabWidget(
                      courses: _filteredCourses,
                      selectedSections: _timetable!.selectedSections,
                      onSectionToggle: (courseCode, sectionId, isSelected) {
                        if (isSelected) {
                          _removeSection(courseCode, sectionId);
                        } else {
                          _addSection(courseCode, sectionId);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                if (_timetable!.clashWarnings.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.all(8),
                    child: ClashWarningsWidget(
                      warnings: _timetable!.clashWarnings,
                    ),
                  ),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: RepaintBoundary(
                        key: _timetableKey,
                        child: TimetableWidget(
                          timetableSlots: _timetableService.generateTimetableSlots(_timetable!.selectedSections, _timetable!.availableCourses),
                          incompleteSelectionWarnings: _timetableService.getIncompleteSelectionWarnings(_timetable!.selectedSections, _timetable!.availableCourses),
                          onClear: _clearTimetable,
                          onRemoveSection: _removeSection,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openGenerator,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('TT Generator'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

class _HomeScreenWithTimetableState extends State<HomeScreenWithTimetable> {
  final TimetableService _timetableService = TimetableService();
  final AuthService _authService = AuthService();
  final GlobalKey _timetableKey = GlobalKey();
  late Timetable _timetable;
  List<Course> _filteredCourses = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _timetable = widget.timetable;
    _filteredCourses = _timetable.availableCourses;
  }

  void _onSearchChanged(String query, Map<String, dynamic> filters) {
    setState(() {
      var courses = _timetable.availableCourses;
      
      // Apply text search
      courses = CourseUtils.searchCourses(courses, query);
      
      // Apply instructor filter
      if (filters['instructor'] != null && filters['instructor'].toString().isNotEmpty) {
        courses = CourseUtils.filterByInstructor(courses, filters['instructor']);
      }
      
      // Apply credits filter
      courses = CourseUtils.filterByCredits(courses, filters['minCredits'], filters['maxCredits']);
      
      // Apply days filter
      if (filters['days'] != null && (filters['days'] as List<DayOfWeek>).isNotEmpty) {
        courses = CourseUtils.filterByDays(courses, filters['days']);
      }
      
      // Apply exam date filters
      if (filters['midSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(courses, filters['midSemDate'], true);
      }
      
      if (filters['endSemDate'] != null) {
        courses = CourseUtils.filterByExamDate(courses, filters['endSemDate'], false);
      }
      
      _filteredCourses = courses;
    });
  }

  Future<void> _addSection(String courseCode, String sectionId) async {
    try {
      final success = await _timetableService.addSection(courseCode, sectionId, _timetable);
      if (success) {
        setState(() {});
        await _timetableService.saveTimetable(_timetable);
      } else {
        final course = _timetable.availableCourses.firstWhere((c) => c.courseCode == courseCode);
        final section = course.sections.firstWhere((s) => s.sectionId == sectionId);
        
        // Check specific reason for failure
        final existingSameType = _timetable.selectedSections.where(
          (s) => s.courseCode == courseCode && s.section.type == section.type
        );
        
        if (existingSameType.isNotEmpty) {
          _showErrorDialog('You can only select one ${section.type.name} section per course.\nAlready selected: ${existingSameType.first.sectionId}');
        } else {
          _showErrorDialog('Cannot add section due to time conflicts or exam clashes');
        }
      }
    } catch (e) {
      _showErrorDialog('Error adding section: $e');
    }
  }

  Future<void> _removeSection(String courseCode, String sectionId) async {
    try {
      await _timetableService.removeSection(courseCode, sectionId, _timetable);
      setState(() {});
      await _timetableService.saveTimetable(_timetable);
    } catch (e) {
      _showErrorDialog('Error removing section: $e');
    }
  }

  Future<void> _clearTimetable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Timetable'),
        content: const Text('Are you sure you want to remove all selected courses from your timetable?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        _timetable.selectedSections.clear();
        _timetable.clashWarnings.clear();
        setState(() {});
        await _timetableService.saveTimetable(_timetable);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timetable cleared successfully')),
        );
      } catch (e) {
        _showErrorDialog('Error clearing timetable: $e');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToICS() async {
    if (_timetable.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    try {
      final filePath = await ExportService.exportToICS(
        _timetable.selectedSections,
        _timetable.availableCourses,
      );
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('Timetable exported to: $filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _exportToPNG() async {
    if (_timetable.selectedSections.isEmpty) {
      _showErrorDialog('No sections selected to export');
      return;
    }

    // Show dialog to choose export location
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export PNG'),
        content: const Text('Choose export location:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Default Location'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose Location'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      String? customPath;
      
      if (result) {
        // Let user choose custom location
        final selectedDirectory = await FilePicker.platform.getDirectoryPath();
        if (selectedDirectory != null) {
          customPath = '$selectedDirectory/timetable.png';
        } else {
          return; // User cancelled
        }
      }

      final filePath = await ExportService.exportToPNG(_timetableKey, customPath: customPath);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Successful'),
          content: Text('Timetable exported to: $filePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorDialog('Export failed: $e');
    }
  }

  Future<void> _openGenerator() async {
    final result = await Navigator.push<List<timetable.SelectedSection>>(
      context,
      MaterialPageRoute(
        builder: (context) => const GeneratorScreen(),
      ),
    );

    if (result != null) {
      try {
        // Clear current selections
        _timetable.selectedSections.clear();
        
        // Add new selections from generator
        for (final section in result) {
          await _timetableService.addSection(
            section.courseCode,
            section.sectionId,
            _timetable,
          );
        }
        
        setState(() {});
        await _timetableService.saveTimetable(_timetable);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Generated timetable applied successfully!')),
        );
      } catch (e) {
        _showErrorDialog('Error applying generated timetable: $e');
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _authService.signOut();
        // Navigation will be handled by AuthWrapper
      } catch (e) {
        _showErrorDialog('Error signing out: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_timetable.name),
        centerTitle: true,
        actions: [
          if (_timetable.selectedSections.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearTimetable,
              tooltip: 'Clear Timetable',
            ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _exportToICS,
            tooltip: 'Export to ICS',
          ),
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _exportToPNG,
            tooltip: 'Export to PNG',
          ),
          // User info and logout
          if (_authService.isAuthenticated)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') {
                  _logout();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _authService.userName ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _authService.userEmail ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const Divider(),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Sign Out'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: _authService.userPhotoUrl != null
                          ? NetworkImage(_authService.userPhotoUrl!)
                          : null,
                      child: _authService.userPhotoUrl == null
                          ? const Icon(Icons.person, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Guest',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: Column(
              children: [
                SearchFilterWidget(
                  onSearchChanged: _onSearchChanged,
                ),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: CoursesTabWidget(
                      courses: _filteredCourses,
                      selectedSections: _timetable.selectedSections,
                      onSectionToggle: (courseCode, sectionId, isSelected) {
                        if (isSelected) {
                          _removeSection(courseCode, sectionId);
                        } else {
                          _addSection(courseCode, sectionId);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                if (_timetable.clashWarnings.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.all(8),
                    child: ClashWarningsWidget(
                      warnings: _timetable.clashWarnings,
                    ),
                  ),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: RepaintBoundary(
                        key: _timetableKey,
                        child: TimetableWidget(
                          timetableSlots: _timetableService.generateTimetableSlots(_timetable.selectedSections, _timetable.availableCourses),
                          incompleteSelectionWarnings: _timetableService.getIncompleteSelectionWarnings(_timetable.selectedSections, _timetable.availableCourses),
                          onClear: _clearTimetable,
                          onRemoveSection: _removeSection,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openGenerator,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('TT Generator'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}
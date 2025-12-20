import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../services/cgpa_service.dart';
import '../services/all_courses_service.dart';
import '../services/auth_service.dart';
import '../models/cgpa_data.dart';
import '../models/all_course.dart';

class CGPACalculatorScreen extends StatefulWidget {
  const CGPACalculatorScreen({super.key});

  @override
  State<CGPACalculatorScreen> createState() => _CGPACalculatorScreenState();
}

class _CGPACalculatorScreenState extends State<CGPACalculatorScreen>
    with SingleTickerProviderStateMixin {
  final CGPAService _cgpaService = CGPAService();
  final AllCoursesService _coursesService = AllCoursesService();
  final AuthService _authService = AuthService();

  late TabController _tabController;
  List<String> _semesters = [];
  CGPAData _cgpaData = CGPAData();
  List<AllCourse> _allCourses = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _semesters = List.from(CGPAService.defaultSemesters);
    _tabController = TabController(length: _semesters.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load courses and CGPA data in parallel
    final results = await Future.wait([
      _coursesService.fetchAllCourses(),
      _cgpaService.loadAllCGPAData(),
    ]);

    setState(() {
      _allCourses = results[0] as List<AllCourse>;
      _cgpaData = results[1] as CGPAData;
      _isLoading = false;
    });
  }

  Future<void> _saveSemester(String semesterName) async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    final semesterData = _cgpaData.semesters[semesterName];
    if (semesterData != null) {
      final success = await _cgpaService.saveSemesterData(
        semesterName,
        semesterData,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Semester saved successfully!'
                  : 'Failed to save semester',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }

    setState(() => _isSaving = false);
  }

  void _addCourseToSemester(String semesterName, AllCourse course) {
    setState(() {
      final semester =
          _cgpaData.semesters[semesterName] ??
          SemesterData(semesterName: semesterName);
      final courseEntry = CourseEntry(
        courseCode: course.courseCode,
        courseTitle: course.courseTitle,
        credits: course.credits,
        courseType: course.type,
      );

      semester.courses.add(courseEntry);
      _cgpaData.semesters[semesterName] = semester;
    });
  }

  void _removeCourseFromSemester(String semesterName, int index) {
    setState(() {
      final semester = _cgpaData.semesters[semesterName];
      if (semester != null) {
        semester.courses.removeAt(index);
        _cgpaData.semesters[semesterName] = semester;
      }
    });
  }

  void _updateGrade(String semesterName, int courseIndex, String? grade) {
    setState(() {
      final semester = _cgpaData.semesters[semesterName];
      if (semester != null && courseIndex < semester.courses.length) {
        semester.courses[courseIndex] = semester.courses[courseIndex].copyWith(
          grade: grade,
        );
        _cgpaData.semesters[semesterName] = semester;
      }
    });
  }

  void _addCustomSemester() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Custom Semester'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Semester Name',
                hintText: 'e.g., 5-2, ST 4',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (controller.text.isNotEmpty &&
                      !_semesters.contains(controller.text)) {
                    setState(() {
                      _semesters.add(controller.text);
                      _tabController.dispose();
                      _tabController = TabController(
                        length: _semesters.length,
                        vsync: this,
                      );
                    });
                  }
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authService.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('CGPA Calculator'), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Please sign in to use the CGPA Calculator',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('CGPA Calculator'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CGPA Calculator'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _semesters.map((sem) => Tab(text: sem)).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Custom Semester',
            onPressed: _addCustomSemester,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Data',
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCGPASummary(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children:
                  _semesters.map((sem) => _buildSemesterView(sem)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCGPASummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryCard('Overall CGPA', _cgpaData.cgpa.toStringAsFixed(2)),
          _buildSummaryCard(
            'Total Credits',
            _cgpaData.semesters.values
                .fold<double>(0.0, (sum, sem) => sum + sem.totalCredits)
                .toStringAsFixed(1),
          ),
          _buildSummaryCard('Semesters', _cgpaData.semesters.length.toString()),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }

  Widget _buildSemesterView(String semesterName) {
    final semester = _cgpaData.semesters[semesterName];
    final courses = semester?.courses ?? [];

    return Column(
      children: [
        // Semester stats
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'SGPA',
                semester?.sgpa.toStringAsFixed(2) ?? '0.00',
              ),
              _buildStatItem(
                'Credits',
                semester?.totalCredits.toStringAsFixed(1) ?? '0.0',
              ),
              _buildStatItem('Courses', courses.length.toString()),
            ],
          ),
        ),

        // Course list
        Expanded(
          child:
              courses.isEmpty
                  ? Center(
                    child: Text(
                      'No courses added yet.\nTap the + button to add courses.',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                    ),
                  )
                  : ListView.builder(
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      return _buildCourseCard(
                        semesterName,
                        index,
                        courses[index],
                      );
                    },
                  ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showAddCourseDialog(semesterName),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Course'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _isSaving ? null : () => _saveSemester(semesterName),
                  icon:
                      _isSaving
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save),
                  label: const Text('Save Semester'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildCourseCard(String semesterName, int index, CourseEntry course) {
    final gradeOptions =
        course.courseType == 'ATC'
            ? CGPAService.atcGrades
            : CGPAService.normalGrades;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.courseCode,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        course.courseTitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed:
                      () => _removeCourseFromSemester(semesterName, index),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Chip(
                  label: Text('${course.credits} Credits'),
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(course.courseType),
                  backgroundColor:
                      course.courseType == 'ATC'
                          ? Colors.orange.shade100
                          : Colors.blue.shade100,
                ),
                const Spacer(),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                    value: course.grade,
                    decoration: const InputDecoration(
                      labelText: 'Grade',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items:
                        gradeOptions.map((grade) {
                          return DropdownMenuItem(
                            value: grade,
                            child: Text(grade),
                          );
                        }).toList(),
                    onChanged:
                        (value) => _updateGrade(semesterName, index, value),
                  ),
                ),
              ],
            ),
            if (course.grade != null && course.courseType == 'Normal')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Grade Points: ${course.gradePoints.toStringAsFixed(1)} × ${course.credits} = ${course.totalGradePoints.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddCourseDialog(String semesterName) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            child: SizedBox(
              width: 600,
              height: 500,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Add Course to $semesterName',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TypeAheadField<AllCourse>(
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Search Course',
                              hintText: 'Enter course code or title',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.search),
                            ),
                          );
                        },
                        suggestionsCallback: (pattern) {
                          return _coursesService.searchCourses(
                            _allCourses,
                            pattern,
                          );
                        },
                        itemBuilder: (context, course) {
                          return ListTile(
                            title: Text(course.courseCode),
                            subtitle: Text(course.courseTitle),
                            trailing: Chip(
                              label: Text(course.type),
                              backgroundColor:
                                  course.type == 'ATC'
                                      ? Colors.orange.shade100
                                      : Colors.blue.shade100,
                            ),
                          );
                        },
                        onSelected: (course) {
                          _addCourseToSemester(semesterName, course);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

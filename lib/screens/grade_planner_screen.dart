import 'package:flutter/material.dart';
import '../models/cgpa_data.dart';
import '../services/responsive_service.dart';

class GradePlannerScreen extends StatefulWidget {
  final CGPAData cgpaData;

  const GradePlannerScreen({super.key, required this.cgpaData});

  @override
  State<GradePlannerScreen> createState() => _GradePlannerScreenState();
}

class _GradePlannerScreenState extends State<GradePlannerScreen> {
  String? _selectedSemester;
  List<CourseEntry> _rankedCourses = [];
  final TextEditingController _targetCGPAController = TextEditingController();
  List<GradeResult> _results = [];
  bool _isCalculating = false;

  // Grade system
  static const grades = ['A', 'A-', 'B', 'B-', 'C', 'C-', 'D', 'D-', 'E'];
  static const gradePoints = [10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0];

  List<String> get _semestersWithCourses {
    return widget.cgpaData.semesters.entries
        .where((e) => e.value.courses.isNotEmpty)
        .map((e) => e.key)
        .toList();
  }

  // Calculate CGPA excluding selected semester
  double get _currentCGPA {
    if (_selectedSemester == null) return widget.cgpaData.cgpa;

    double totalGradePoints = 0.0;
    double totalCredits = 0.0;

    for (final entry in widget.cgpaData.semesters.entries) {
      if (entry.key != _selectedSemester) {
        totalGradePoints += entry.value.totalGradePoints;
        totalCredits += entry.value.totalCredits;
      }
    }

    return totalCredits > 0 ? totalGradePoints / totalCredits : 0.0;
  }

  double get _priorCredits {
    double total = 0.0;
    for (final entry in widget.cgpaData.semesters.entries) {
      if (entry.key != _selectedSemester) {
        total += entry.value.totalCredits;
      }
    }
    return total;
  }

  double get _priorGradePoints {
    double total = 0.0;
    for (final entry in widget.cgpaData.semesters.entries) {
      if (entry.key != _selectedSemester) {
        total += entry.value.totalGradePoints;
      }
    }
    return total;
  }

  void _onSemesterChanged(String? semester) {
    setState(() {
      _selectedSemester = semester;
      _results = [];
      if (semester != null) {
        final semesterData = widget.cgpaData.semesters[semester];
        if (semesterData != null) {
          // Only include Normal courses (not ATC)
          _rankedCourses = semesterData.courses
              .where((c) => c.courseType == 'Normal')
              .map((c) => c.copyWith())
              .toList();
        }
      } else {
        _rankedCourses = [];
      }
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _rankedCourses.removeAt(oldIndex);
      _rankedCourses.insert(newIndex, item);
    });
  }

  void _calculateGrades() {
    final targetText = _targetCGPAController.text.trim();
    if (targetText.isEmpty) {
      _showError('Please enter a target CGPA');
      return;
    }

    final targetCGPA = double.tryParse(targetText);
    if (targetCGPA == null || targetCGPA < 0 || targetCGPA > 10) {
      _showError('Target CGPA must be between 0 and 10');
      return;
    }

    if (_rankedCourses.isEmpty) {
      _showError('No courses to calculate grades for');
      return;
    }

    setState(() => _isCalculating = true);

    // Run calculation
    final results = _findOptimalGrades(
      priorCredits: _priorCredits,
      priorGradePoints: _priorGradePoints,
      rankedCourses: _rankedCourses,
      targetCGPA: targetCGPA,
    );

    setState(() {
      _results = results;
      _isCalculating = false;
    });
  }

  List<GradeResult> _findOptimalGrades({
    required double priorCredits,
    required double priorGradePoints,
    required List<CourseEntry> rankedCourses,
    required double targetCGPA,
  }) {
    final courseCount = rankedCourses.length;
    final List<GradeResult> allResults = [];

    // Calculate semester credits
    final semesterCredits = rankedCourses.fold<double>(
      0.0,
      (sum, c) => sum + c.credits,
    );
    final totalCredits = priorCredits + semesterCredits;

    if (courseCount <= 6) {
      // Brute force for small course counts
      _generateAllCombinations(
        rankedCourses: rankedCourses,
        currentIndex: 0,
        currentGrades: [],
        priorCredits: priorCredits,
        priorGradePoints: priorGradePoints,
        totalCredits: totalCredits,
        targetCGPA: targetCGPA,
        results: allResults,
      );
    } else {
      // For larger course counts, use a smarter approach
      // Generate combinations that respect ranking priority
      _generateRankedCombinations(
        rankedCourses: rankedCourses,
        priorCredits: priorCredits,
        priorGradePoints: priorGradePoints,
        totalCredits: totalCredits,
        targetCGPA: targetCGPA,
        results: allResults,
      );
    }

    // Sort by distance from target, then by total grade points (prefer better grades)
    allResults.sort((a, b) {
      final distCompare = a.distanceFromTarget.compareTo(b.distanceFromTarget);
      if (distCompare != 0) return distCompare;
      // Prefer higher CGPA when distance is equal
      return b.resultingCGPA.compareTo(a.resultingCGPA);
    });

    // Return top 10 unique results
    final uniqueResults = <String, GradeResult>{};
    for (final result in allResults) {
      final key = result.courseGrades.values.join(',');
      if (!uniqueResults.containsKey(key)) {
        uniqueResults[key] = result;
      }
      if (uniqueResults.length >= 10) break;
    }

    return uniqueResults.values.toList();
  }

  void _generateAllCombinations({
    required List<CourseEntry> rankedCourses,
    required int currentIndex,
    required List<int> currentGrades,
    required double priorCredits,
    required double priorGradePoints,
    required double totalCredits,
    required double targetCGPA,
    required List<GradeResult> results,
  }) {
    if (currentIndex == rankedCourses.length) {
      // Calculate CGPA for this combination
      double semesterGradePoints = 0.0;
      for (int i = 0; i < rankedCourses.length; i++) {
        semesterGradePoints +=
            rankedCourses[i].credits * gradePoints[currentGrades[i]];
      }

      final resultingCGPA =
          (priorGradePoints + semesterGradePoints) / totalCredits;
      final distance = (resultingCGPA - targetCGPA).abs();

      // Check if this combination respects ranking
      // Higher ranked courses should have equal or better grades
      bool respectsRanking = true;
      for (int i = 0; i < currentGrades.length - 1; i++) {
        if (currentGrades[i] > currentGrades[i + 1]) {
          // Lower grade index = better grade
          // If higher ranked course has worse grade, it doesn't respect ranking
          respectsRanking = false;
          break;
        }
      }

      final courseGrades = <String, String>{};
      for (int i = 0; i < rankedCourses.length; i++) {
        courseGrades[rankedCourses[i].courseCode] = grades[currentGrades[i]];
      }

      results.add(GradeResult(
        courseGrades: courseGrades,
        resultingCGPA: resultingCGPA,
        distanceFromTarget: distance,
        respectsRanking: respectsRanking,
      ));
      return;
    }

    // Try all grades for current course
    for (int g = 0; g < grades.length; g++) {
      _generateAllCombinations(
        rankedCourses: rankedCourses,
        currentIndex: currentIndex + 1,
        currentGrades: [...currentGrades, g],
        priorCredits: priorCredits,
        priorGradePoints: priorGradePoints,
        totalCredits: totalCredits,
        targetCGPA: targetCGPA,
        results: results,
      );
    }
  }

  void _generateRankedCombinations({
    required List<CourseEntry> rankedCourses,
    required double priorCredits,
    required double priorGradePoints,
    required double totalCredits,
    required double targetCGPA,
    required List<GradeResult> results,
  }) {
    // For larger course counts, generate combinations that respect ranking
    // Start from uniform grades and explore variations
    for (int baseGrade = 0; baseGrade < grades.length; baseGrade++) {
      // All same grade
      final uniformGrades = List.filled(rankedCourses.length, baseGrade);
      _addResultFromGrades(
        rankedCourses: rankedCourses,
        gradeIndices: uniformGrades,
        priorGradePoints: priorGradePoints,
        totalCredits: totalCredits,
        targetCGPA: targetCGPA,
        results: results,
      );

      // Variations: higher ranked get better grades
      for (int split = 1; split < rankedCourses.length; split++) {
        for (int betterGrade = 0; betterGrade < baseGrade; betterGrade++) {
          final variedGrades = List.generate(rankedCourses.length, (i) {
            return i < split ? betterGrade : baseGrade;
          });
          _addResultFromGrades(
            rankedCourses: rankedCourses,
            gradeIndices: variedGrades,
            priorGradePoints: priorGradePoints,
            totalCredits: totalCredits,
            targetCGPA: targetCGPA,
            results: results,
          );
        }
      }

      // Gradual decline pattern
      for (int step = 1; step <= 2; step++) {
        final declineGrades = List.generate(rankedCourses.length, (i) {
          final grade = baseGrade + (i * step ~/ rankedCourses.length);
          return grade.clamp(0, grades.length - 1);
        });
        _addResultFromGrades(
          rankedCourses: rankedCourses,
          gradeIndices: declineGrades,
          priorGradePoints: priorGradePoints,
          totalCredits: totalCredits,
          targetCGPA: targetCGPA,
          results: results,
        );
      }
    }
  }

  void _addResultFromGrades({
    required List<CourseEntry> rankedCourses,
    required List<int> gradeIndices,
    required double priorGradePoints,
    required double totalCredits,
    required double targetCGPA,
    required List<GradeResult> results,
  }) {
    double semesterGradePoints = 0.0;
    for (int i = 0; i < rankedCourses.length; i++) {
      semesterGradePoints +=
          rankedCourses[i].credits * gradePoints[gradeIndices[i]];
    }

    final resultingCGPA =
        (priorGradePoints + semesterGradePoints) / totalCredits;
    final distance = (resultingCGPA - targetCGPA).abs();

    bool respectsRanking = true;
    for (int i = 0; i < gradeIndices.length - 1; i++) {
      if (gradeIndices[i] > gradeIndices[i + 1]) {
        respectsRanking = false;
        break;
      }
    }

    final courseGrades = <String, String>{};
    for (int i = 0; i < rankedCourses.length; i++) {
      courseGrades[rankedCourses[i].courseCode] = grades[gradeIndices[i]];
    }

    results.add(GradeResult(
      courseGrades: courseGrades,
      resultingCGPA: resultingCGPA,
      distanceFromTarget: distance,
      respectsRanking: respectsRanking,
    ));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return Colors.teal;
      case 'A-':
        return Colors.cyan;
      case 'B':
        return Colors.blue;
      case 'B-':
        return Colors.lightBlue;
      case 'C':
        return Colors.amber;
      case 'C-':
        return Colors.orange;
      case 'D':
        return Colors.deepOrange;
      case 'D-':
        return Colors.red;
      case 'E':
        return Colors.red.shade900;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _targetCGPAController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grade Planner'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _semestersWithCourses.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: !isMobile && _selectedSemester != null
                      // Desktop layout - side by side
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left side - All inputs and controls
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildSemesterSelector(),
                                  const SizedBox(height: 16),
                                  _buildCurrentCGPACard(),
                                  const SizedBox(height: 16),
                                  _buildCourseRankingSection(),
                                  const SizedBox(height: 16),
                                  _buildTargetInput(),
                                  const SizedBox(height: 24),
                                  _buildCalculateButton(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Right side - Results card
                            Expanded(
                              flex: 2,
                              child: _buildResultsCard(),
                            ),
                          ],
                        )
                      // Mobile layout or no semester selected - stacked
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSemesterSelector(),
                            const SizedBox(height: 16),
                            if (_selectedSemester != null) ...[
                              _buildCurrentCGPACard(),
                              const SizedBox(height: 16),
                              _buildCourseRankingSection(),
                              const SizedBox(height: 16),
                              _buildTargetInput(),
                              const SizedBox(height: 24),
                              _buildCalculateButton(),
                              if (_results.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                _buildResultsCard(),
                              ],
                            ],
                          ],
                        ),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Semesters with Courses',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add courses to your semesters in the CGPA Calculator first.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemesterSelector() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Semester to Plan',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedSemester,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              hint: const Text('Choose a semester'),
              items: _semestersWithCourses.map((semester) {
                final courseCount =
                    widget.cgpaData.semesters[semester]?.courses.length ?? 0;
                return DropdownMenuItem(
                  value: semester,
                  child: Text('$semester ($courseCount courses)'),
                );
              }).toList(),
              onChanged: _onSemesterChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentCGPACard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current CGPA',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '(excluding $_selectedSemester)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
          Text(
            _currentCGPA.toStringAsFixed(2),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseRankingSection() {
    if (_rankedCourses.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No Normal courses in this semester.\nATC courses are not included in CGPA.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.drag_indicator_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rank Courses by Priority',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Drag to reorder. Higher = more important for good grades.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 12),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _rankedCourses.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final course = _rankedCourses[index];
                return _buildCourseRankItem(course, index);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseRankItem(CourseEntry course, int index) {
    return Container(
      key: ValueKey(course.courseCode),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          course.courseCode,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          course.courseTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${course.credits.toStringAsFixed(0)} credits',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle_rounded,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetInput() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target CGPA',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetCGPAController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Enter target CGPA (e.g., 8.5)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.flag_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalculateButton() {
    return FilledButton.icon(
      onPressed: _isCalculating || _rankedCourses.isEmpty
          ? null
          : _calculateGrades,
      icon: _isCalculating
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.calculate_rounded),
      label: Text(_isCalculating ? 'Calculating...' : 'Find Grade Combinations'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 900),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lightbulb_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _results.isEmpty
                          ? 'Grade Combinations'
                          : 'Top ${_results.length} Combinations',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            if (_results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calculate_outlined,
                      size: 48,
                      color: colorScheme.outline.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Results Yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter a target CGPA and tap Calculate to see the best grade combinations.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.outline.withValues(alpha: 0.8),
                          ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      return _buildResultItem(_results[index], index);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(GradeResult result, int index) {
    final targetCGPA = double.tryParse(_targetCGPAController.text.trim()) ?? 0;
    // Round to 4 decimal places for comparison to avoid floating point precision issues
    final roundedResultCGPA = (result.resultingCGPA * 10000).round() / 10000;
    final roundedTargetCGPA = (targetCGPA * 10000).round() / 10000;
    final isTargetAchieved = roundedResultCGPA >= roundedTargetCGPA;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isTargetAchieved
              ? Colors.green.withValues(alpha: 0.5)
              : colorScheme.outline.withValues(alpha: 0.2),
          width: isTargetAchieved ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                if (isTargetAchieved)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Target Achieved',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'CGPA',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                    Text(
                      result.resultingCGPA.toStringAsFixed(4),
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isTargetAchieved
                                    ? Colors.green
                                    : colorScheme.onSurface,
                              ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _rankedCourses.map((course) {
                final grade = result.courseGrades[course.courseCode] ?? '?';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getGradeColor(grade).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getGradeColor(grade).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        course.courseCode,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getGradeColor(grade),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          grade,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            if (!result.respectsRanking) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Lower priority courses have better grades',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class GradeResult {
  final Map<String, String> courseGrades;
  final double resultingCGPA;
  final double distanceFromTarget;
  final bool respectsRanking;

  GradeResult({
    required this.courseGrades,
    required this.resultingCGPA,
    required this.distanceFromTarget,
    required this.respectsRanking,
  });
}

import 'package:flutter/material.dart';
import '../models/cgpa_data.dart';
import '../models/course_type.dart';
import '../services/ui/responsive_service.dart';
import '../services/ui/toast_service.dart';
import '../utils/design_constants.dart';
import '../constants/app_constants.dart';
import '../utils/grade_utils.dart' as grade_utils;

class CGBoosterScreen extends StatefulWidget {
  final CGPAData cgpaData;

  const CGBoosterScreen({super.key, required this.cgpaData});

  @override
  State<CGBoosterScreen> createState() => _CGBoosterScreenState();
}

class _CGBoosterScreenState extends State<CGBoosterScreen> {
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _maxCreditsController = TextEditingController();
  List<_RepeatCandidate> _candidates = [];
  List<_BoostResult> _results = [];
  bool _isCalculating = false;

  static final _grades = GradeConstants.normal;
  static final _gradePoints = GradeConstants.points;

  double get _currentCGPA => widget.cgpaData.cgpa;
  double get _totalCredits => widget.cgpaData.effectiveTotalCredits;
  double get _totalGradePoints => widget.cgpaData.effectiveTotalGradePoints;

  Color _gradeColor(String grade) => grade_utils.getGradeColor(grade, scheme: Theme.of(context).colorScheme);

  @override
  void initState() {
    super.initState();
    _buildCandidates();
  }

  @override
  void dispose() {
    _targetController.dispose();
    _maxCreditsController.dispose();
    super.dispose();
  }

  void _buildCandidates() {
    final latest = <String, _CandidateInfo>{};
    for (final entry in widget.cgpaData.semesters.entries) {
      for (final course in entry.value.courses) {
        if (course.courseType != CourseType.normal ||
            course.grade == null ||
            course.grade!.isEmpty) {
          continue;
        }
        latest[course.courseCode] = _CandidateInfo(
          entry: course,
          semester: entry.key,
        );
      }
    }

    _candidates = latest.values
        .where((c) => c.entry.gradePoints < 10.0 && c.entry.gradePoints > 0.0)
        .map((c) => _RepeatCandidate(
              courseCode: c.entry.courseCode,
              courseTitle: c.entry.courseTitle,
              credits: c.entry.credits,
              currentGrade: c.entry.grade!,
              currentGradePoints: c.entry.gradePoints,
              semester: c.semester,
              selected: true,
            ))
        .toList()
      ..sort((a, b) => a.currentGradePoints.compareTo(b.currentGradePoints));
  }

  void _calculate() {
    final targetText = _targetController.text.trim();
    if (targetText.isEmpty) {
      ToastService.showError('Enter a target CG');
      return;
    }
    final targetCG = double.tryParse(targetText);
    if (targetCG == null || targetCG <= 0 || targetCG > 10) {
      ToastService.showError('Target CG must be between 0 and 10');
      return;
    }
    if (targetCG <= _currentCGPA) {
      ToastService.showInfo('Your current CG already meets the target');
      return;
    }

    final maxCreditsText = _maxCreditsController.text.trim();
    final maxCredits = maxCreditsText.isEmpty
        ? double.infinity
        : (double.tryParse(maxCreditsText) ?? double.infinity);

    final selected = _candidates.where((c) => c.selected).toList();
    if (selected.isEmpty) {
      ToastService.showError('Select at least one course to repeat');
      return;
    }

    setState(() => _isCalculating = true);

    final results = _findRepeatCombinations(
      targetCG: targetCG,
      maxCredits: maxCredits,
      candidates: selected,
    );

    setState(() {
      _results = results;
      _isCalculating = false;
    });
  }

  List<_BoostResult> _findRepeatCombinations({
    required double targetCG,
    required double maxCredits,
    required List<_RepeatCandidate> candidates,
  }) {
    final results = <_BoostResult>[];
    final n = candidates.length;

    // Required total grade points to hit target
    final requiredTotalGP = targetCG * _totalCredits;

    // Generate subsets up to size 8 to keep it tractable
    final maxSubsetSize = n.clamp(0, 8);

    for (int mask = 1; mask < (1 << maxSubsetSize); mask++) {
      final subset = <_RepeatCandidate>[];
      double subsetCredits = 0;
      for (int i = 0; i < maxSubsetSize; i++) {
        if (mask & (1 << i) != 0) {
          subset.add(candidates[i]);
          subsetCredits += candidates[i].credits;
        }
      }
      if (subsetCredits > maxCredits) continue;

      // Calculate the grade points freed up by removing old grades
      double oldGP = 0;
      for (final c in subset) {
        oldGP += c.credits * c.currentGradePoints;
      }
      final baseGP = _totalGradePoints - oldGP;

      // For each course in the subset, find the minimum new grade needed
      // Try assigning the best possible grades starting from A
      final newGrades = _assignMinGrades(
        subset: subset,
        baseGP: baseGP,
        requiredTotalGP: requiredTotalGP,
      );

      if (newGrades == null) continue;

      // Verify all new grades are strictly better than old ones
      bool allBetter = true;
      for (int i = 0; i < subset.length; i++) {
        final newGP = _gradeToPoints(newGrades[i]);
        if (newGP <= subset[i].currentGradePoints) {
          allBetter = false;
          break;
        }
      }
      if (!allBetter) continue;

      double newTotalGP = baseGP;
      for (int i = 0; i < subset.length; i++) {
        newTotalGP += subset[i].credits * _gradeToPoints(newGrades[i]);
      }
      final resultingCG = newTotalGP / _totalCredits;

      if (resultingCG < targetCG - 0.005) continue;

      final courseChanges = <_CourseChange>[];
      for (int i = 0; i < subset.length; i++) {
        courseChanges.add(_CourseChange(
          courseCode: subset[i].courseCode,
          courseTitle: subset[i].courseTitle,
          credits: subset[i].credits,
          oldGrade: subset[i].currentGrade,
          newGrade: newGrades[i],
        ));
      }

      results.add(_BoostResult(
        changes: courseChanges,
        resultingCG: resultingCG,
        totalRepeatCredits: subsetCredits,
      ));
    }

    // Sort: fewest credits first, then fewest courses, then closest to target
    results.sort((a, b) {
      final creditCmp = a.totalRepeatCredits.compareTo(b.totalRepeatCredits);
      if (creditCmp != 0) return creditCmp;
      final countCmp = a.changes.length.compareTo(b.changes.length);
      if (countCmp != 0) return countCmp;
      return (a.resultingCG - targetCG).abs().compareTo(
            (b.resultingCG - targetCG).abs(),
          );
    });

    // Deduplicate by course set
    final seen = <String>{};
    final unique = <_BoostResult>[];
    for (final r in results) {
      final key = r.changes.map((c) => '${c.courseCode}:${c.newGrade}').join('|');
      if (seen.add(key)) unique.add(r);
      if (unique.length >= 10) break;
    }

    return unique;
  }

  // Assign minimum grades to each course in subset to reach the target.
  // Strategy: give each course the lowest grade that still improves, then
  // bump from worst-graded upward until target is met.
  List<String>? _assignMinGrades({
    required List<_RepeatCandidate> subset,
    required double baseGP,
    required double requiredTotalGP,
  }) {
    // Start each course at the minimum improvement grade
    final gradeIndices = <int>[];
    for (final c in subset) {
      final currentIdx = _gradePoints.indexWhere((gp) => gp == c.currentGradePoints);
      final minBetterIdx = currentIdx >= 1 ? currentIdx - 1 : -1;
      if (minBetterIdx < 0) return null;
      gradeIndices.add(minBetterIdx);
    }

    // Check if achievable even with all A's
    double maxGP = baseGP;
    for (final c in subset) {
      maxGP += c.credits * 10.0;
    }
    if (maxGP < requiredTotalGP) return null;

    // Iteratively improve the worst grade until target is met
    for (int iter = 0; iter < 100; iter++) {
      double currentGP = baseGP;
      for (int i = 0; i < subset.length; i++) {
        currentGP += subset[i].credits * _gradePoints[gradeIndices[i]];
      }
      if (currentGP >= requiredTotalGP) {
        return gradeIndices.map((i) => _grades[i]).toList();
      }

      // Find the course with the worst new grade and bump it
      int worstIdx = -1;
      int worstGrade = -1;
      for (int i = 0; i < gradeIndices.length; i++) {
        if (gradeIndices[i] > 0 && gradeIndices[i] > worstGrade) {
          worstGrade = gradeIndices[i];
          worstIdx = i;
        }
      }
      if (worstIdx == -1) return null;
      gradeIndices[worstIdx]--;
    }

    return null;
  }

  double _gradeToPoints(String grade) => GradeConstants.pointsFor(grade);

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveService.isMobile(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('CG Booster')),
      body: _candidates.isEmpty
          ? _buildEmptyState(scheme)
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCurrentCGCard(scheme),
                      const SizedBox(height: 16),
                      _buildInputSection(scheme),
                      const SizedBox(height: 16),
                      _buildCandidatesList(scheme),
                      const SizedBox(height: 16),
                      _buildCalculateButton(scheme),
                      if (_results.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildResults(scheme),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined, size: 64, color: scheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No graded courses found',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Text(
            'Import your grades in the CGPA calculator first.',
            style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCGCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDesign.cardDecoration(context),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current CG', style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6))),
              Text(
                _currentCGPA.toStringAsFixed(2),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: scheme.primary),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Credits', style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6))),
              Text(
                _totalCredits.toStringAsFixed(0),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Configuration', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: AppDesign.inputDecoration(context, label: 'Target CG', hint: 'e.g. 8.0'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxCreditsController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: AppDesign.inputDecoration(context, label: 'Max credits to repeat', hint: 'optional'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCandidatesList(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Courses eligible for repeat',
                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
              ),
              TextButton(
                onPressed: () {
                  final allSelected = _candidates.every((c) => c.selected);
                  setState(() {
                    for (final c in _candidates) {
                      c.selected = !allSelected;
                    }
                  });
                },
                child: Text(_candidates.every((c) => c.selected) ? 'Deselect all' : 'Select all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._candidates.map((c) => _buildCandidateRow(c, scheme)),
        ],
      ),
    );
  }

  Widget _buildCandidateRow(_RepeatCandidate candidate, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: AppDesign.borderRadiusSm,
        onTap: () => setState(() => candidate.selected = !candidate.selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: candidate.selected,
                  onChanged: (v) => setState(() => candidate.selected = v ?? false),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  candidate.courseCode,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: candidate.selected ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  candidate.courseTitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: candidate.selected ? scheme.onSurface.withValues(alpha: 0.7) : scheme.onSurface.withValues(alpha: 0.3),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${candidate.credits.toStringAsFixed(0)} cr',
                  style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
                  textAlign: TextAlign.center,
                ),
              ),
              Container(
                width: 36,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _gradeColor(candidate.currentGrade).withValues(alpha: 0.15),
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Text(
                  candidate.currentGrade,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _gradeColor(candidate.currentGrade),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculateButton(ColorScheme scheme) {
    return FilledButton.icon(
      onPressed: _isCalculating ? null : _calculate,
      icon: _isCalculating
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.bolt),
      label: Text(_isCalculating ? 'Calculating...' : 'Find combinations'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_results.length} combination${_results.length != 1 ? 's' : ''} found',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: scheme.onSurface),
        ),
        const SizedBox(height: 12),
        ..._results.asMap().entries.map((e) => _buildResultCard(e.key, e.value, scheme)),
      ],
    );
  }

  Widget _buildResultCard(int index, _BoostResult result, ColorScheme scheme) {
    final cgDelta = result.resultingCG - _currentCGPA;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppDesign.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'CG: ${result.resultingCG.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: scheme.onSurface),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: AppDesign.borderRadiusSm,
                ),
                child: Text(
                  '+${cgDelta.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                ),
              ),
              const Spacer(),
              Text(
                '${result.totalRepeatCredits.toStringAsFixed(0)} credits',
                style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...result.changes.map((change) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${change.courseCode} (${change.credits.toStringAsFixed(0)} cr)',
                        style: TextStyle(fontSize: 13, color: scheme.onSurface),
                      ),
                    ),
                    Container(
                      width: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _gradeColor(change.oldGrade).withValues(alpha: 0.1),
                        borderRadius: AppDesign.borderRadiusSm,
                      ),
                      child: Text(
                        change.oldGrade,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _gradeColor(change.oldGrade),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, size: 14, color: scheme.onSurface.withValues(alpha: 0.4)),
                    ),
                    Container(
                      width: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _gradeColor(change.newGrade).withValues(alpha: 0.15),
                        borderRadius: AppDesign.borderRadiusSm,
                      ),
                      child: Text(
                        change.newGrade,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _gradeColor(change.newGrade),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _CandidateInfo {
  final CourseEntry entry;
  final String semester;
  _CandidateInfo({required this.entry, required this.semester});
}

class _RepeatCandidate {
  final String courseCode;
  final String courseTitle;
  final double credits;
  final String currentGrade;
  final double currentGradePoints;
  final String semester;
  bool selected;

  _RepeatCandidate({
    required this.courseCode,
    required this.courseTitle,
    required this.credits,
    required this.currentGrade,
    required this.currentGradePoints,
    required this.semester,
    this.selected = true,
  });
}

class _BoostResult {
  final List<_CourseChange> changes;
  final double resultingCG;
  final double totalRepeatCredits;

  _BoostResult({
    required this.changes,
    required this.resultingCG,
    required this.totalRepeatCredits,
  });
}

class _CourseChange {
  final String courseCode;
  final String courseTitle;
  final double credits;
  final String oldGrade;
  final String newGrade;

  _CourseChange({
    required this.courseCode,
    required this.courseTitle,
    required this.credits,
    required this.oldGrade,
    required this.newGrade,
  });
}

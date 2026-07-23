import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/cgpa_data.dart';
import '../utils/design_constants.dart';
import '../widgets/charts/cgpa_trajectory_chart.dart';

/// Visualises the CGPA data the student already entered: SGPA-per-semester bars
/// with the cumulative CGPA line, a target "what SGPA do I need next" readout,
/// and a distribution of the grades held.
class CgpaTrajectoryScreen extends StatefulWidget {
  const CgpaTrajectoryScreen({super.key, required this.cgpaData});

  final CGPAData cgpaData;

  @override
  State<CgpaTrajectoryScreen> createState() => _CgpaTrajectoryScreenState();
}

class _CgpaTrajectoryScreenState extends State<CgpaTrajectoryScreen> {
  final _targetCtrl = TextEditingController();
  final _creditsCtrl = TextEditingController();

  double? _target;

  @override
  void initState() {
    super.initState();
    // Seed the next-semester credit load with the most recent semester's, or a
    // sensible default, so the readout means something before the user edits.
    final points = widget.cgpaData.trajectory();
    final seed = points.isNotEmpty ? points.last.credits : 20.0;
    _creditsCtrl.text = seed % 1 == 0 ? seed.toInt().toString() : seed.toString();
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    _creditsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = widget.cgpaData.trajectory();
    final cgpa = widget.cgpaData.cgpa;

    return Scaffold(
      appBar: AppDesign.appBar(context, title: 'CGPA Trajectory'),
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        children: [
          _headerCard(context, scheme, cgpa, points),
          const SizedBox(height: AppDesign.spacingMd),
          _card(
            context,
            title: 'SGPA per semester · cumulative CGPA',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CgpaTrajectoryChart(points: points, targetCgpa: _target),
                const SizedBox(height: 8),
                _legend(context, scheme),
              ],
            ),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          _card(
            context,
            title: 'What do I need?',
            child: _whatIf(context, scheme),
          ),
          const SizedBox(height: AppDesign.spacingMd),
          _card(
            context,
            title: 'Grades held',
            child: _distribution(context, scheme),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(BuildContext context, ColorScheme scheme, double cgpa,
      List<CgpaTrajectoryPoint> points) {
    final trend = points.length >= 2
        ? points.last.cumulativeCgpa - points[points.length - 2].cumulativeCgpa
        : 0.0;
    final up = trend >= 0;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerHigh],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current CGPA',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6))),
              Text(cgpa.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700, color: scheme.onSurface)),
            ],
          ),
          const Spacer(),
          if (points.length >= 2)
            Row(
              children: [
                Icon(up ? Icons.trending_up : Icons.trending_down,
                    color: up ? scheme.primary : scheme.error, size: 18),
                const SizedBox(width: 4),
                Text('${up ? '+' : ''}${trend.toStringAsFixed(2)} last sem',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: up ? scheme.primary : scheme.error,
                        fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _whatIf(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    AppDesign.inputDecoration(context, hint: 'Target CGPA'),
                onChanged: (_) => setState(
                    () => _target = double.tryParse(_targetCtrl.text.trim())),
              ),
            ),
            const SizedBox(width: AppDesign.spacingSm),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _creditsCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    AppDesign.inputDecoration(context, hint: 'Credits'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _requiredReadout(context, scheme),
      ],
    );
  }

  Widget _requiredReadout(BuildContext context, ColorScheme scheme) {
    final target = double.tryParse(_targetCtrl.text.trim());
    final credits = double.tryParse(_creditsCtrl.text.trim()) ?? 0;
    if (target == null || target <= 0 || credits <= 0) {
      return Text(
        'Enter a target CGPA and next-semester credits to see the SGPA you\'d need.',
        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
      );
    }
    final needed =
        widget.cgpaData.requiredSgpa(targetCgpa: target, nextCredits: credits);

    final (String msg, Color color, IconData icon) = needed <= 0
        ? ('You\'re already at or above ${target.toStringAsFixed(2)} — any passing semester keeps it.',
            scheme.primary, Icons.check_circle_outline)
        : needed > 10
            ? ('Out of reach in one semester — a perfect 10.0 over $credits credits still falls short of ${target.toStringAsFixed(2)}.',
                scheme.error, Icons.error_outline)
            : ('Score ${needed.toStringAsFixed(2)} SGPA over $credits credits to reach ${target.toStringAsFixed(2)}.',
                scheme.secondary, Icons.flag_outlined);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    color: scheme.onSurface, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _distribution(BuildContext context, ColorScheme scheme) {
    final dist = widget.cgpaData.gradeDistribution();
    if (dist.isEmpty) {
      return Text('No letter grades entered yet.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)));
    }
    final grades = GradeConstants.gradePoints.keys
        .where((g) => (dist[g] ?? 0) > 0)
        .toList();
    final maxCount = dist.values.fold(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        for (final g in grades)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                    width: 26,
                    child: Text(g,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600))),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final w = (c.maxWidth * (dist[g]! / maxCount)).clamp(6.0, c.maxWidth);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 16,
                        width: w,
                        decoration: BoxDecoration(
                          color: _gradeColor(scheme, g),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Text('${dist[g]}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ),
      ],
    );
  }

  Color _gradeColor(ColorScheme scheme, String grade) {
    final pts = GradeConstants.pointsFor(grade);
    if (pts >= 9) return scheme.primary;
    if (pts >= 7) return scheme.secondary;
    if (pts >= 5) return Color.lerp(scheme.secondary, scheme.error, 0.5)!;
    return scheme.error;
  }

  Widget _legend(BuildContext context, ColorScheme scheme) {
    Widget item(Color c, String label, {bool line = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 14,
                height: line ? 3 : 10,
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6))),
          ],
        );
    return Wrap(spacing: 16, runSpacing: 6, children: [
      item(scheme.primary.withValues(alpha: 0.5), 'SGPA (bar)'),
      item(scheme.tertiary, 'CGPA (line)', line: true),
    ]);
  }

  Widget _card(BuildContext context, {required String title, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spacingMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

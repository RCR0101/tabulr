import 'package:flutter/material.dart';
import '../../services/core/timetable_ranker.dart';
import '../common/app_tappable.dart';

/// How much each intent axis counts when ordering results, feeding the ranker's
/// TOPSIS weights. Five Low/Normal/High segmented controls, one per axis.
class RankingImportancePanel extends StatelessWidget {
  const RankingImportancePanel({
    super.key,
    required this.importance,
    required this.onChanged,
    required this.onReset,
  });

  final Map<RankAxis, AxisImportance> importance;
  final void Function(RankAxis axis, AxisImportance value) onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anyChanged =
        importance.values.any((v) => v != AxisImportance.normal);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Ranking importance',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (anyChanged)
                TextButton(
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'How much each factor matters when ordering the best options',
            style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          for (final axis in RankAxis.values)
            _ImportanceRow(
              axis: axis,
              value: importance[axis] ?? AxisImportance.normal,
              onChanged: (v) => onChanged(axis, v),
            ),
        ],
      ),
    );
  }
}

class _ImportanceRow extends StatelessWidget {
  const _ImportanceRow({
    required this.axis,
    required this.value,
    required this.onChanged,
  });

  final RankAxis axis;
  final AxisImportance value;
  final ValueChanged<AxisImportance> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = AxisImportance.values;
    final scheme = Theme.of(context).colorScheme;
    final idx = values.indexOf(value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(axis.label, style: const TextStyle(fontSize: 13))),
          Container(
            width: 156,
            height: 30,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(9),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final segWidth = c.maxWidth / values.length;
                return Stack(
                  children: [
                    // Sliding selection pill — animates between segments.
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment:
                          Alignment(-1 + 2 * (idx / (values.length - 1)), 0),
                      child: Container(
                        width: segWidth,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < values.length; i++)
                          Expanded(
                            child: AppTappable(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onChanged(values[i]),
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: i == idx
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: i == idx
                                        ? scheme.onPrimary
                                        : scheme.onSurface
                                            .withValues(alpha: 0.7),
                                  ),
                                  child: Text(values[i].label),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

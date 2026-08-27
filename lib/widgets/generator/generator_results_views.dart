import 'package:flutter/material.dart';
import '../../services/core/timetable_generator_controller.dart';
import '../../services/core/timetable_ranker.dart';
import '../../utils/design_constants.dart';

class GenerateButton extends StatelessWidget {
  const GenerateButton({
    super.key,
    required this.enabled,
    required this.isGenerating,
    required this.onGenerate,
  });

  final bool enabled;
  final bool isGenerating;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = enabled && !isGenerating;
    final foreground = enabled
        ? theme.scaffoldBackgroundColor
        : theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Semantics(
      label: 'Generate Timetables',
      button: true,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: active
              ? LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: active ? null : theme.colorScheme.surface,
        ),
        child: FilledButton(
          onPressed: active ? onGenerate : null,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isGenerating
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Generating...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, color: foreground, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Generate Timetables',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Shown in the results panel before anything has been generated, while
/// generating, or when hard constraints filtered every option away.
class EmptyResults extends StatelessWidget {
  const EmptyResults({
    super.key,
    required this.isGenerating,
    required this.result,
    this.relaxations = const [],
    this.onRelax,
  });

  final bool isGenerating;

  /// Non-null once a generate has run. An empty `ranked` with non-empty
  /// `unmetIntents` is the "your required constraints left nothing" case.
  final RankingResult? result;
  final List<ConstraintRelaxation> relaxations;
  final ValueChanged<ConstraintRelaxation>? onRelax;

  bool get _blockedByHardConstraints =>
      !isGenerating &&
      result != null &&
      result!.ranked.isEmpty &&
      result!.unmetIntents.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_blockedByHardConstraints) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: AppDesign.warning(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your required constraints left no options',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...result!.unmetIntents.map((n) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $n',
                        style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface.withValues(alpha: 0.85))),
                  )),
              const SizedBox(height: 12),
              Text(
                relaxations.isEmpty
                    ? 'Loosen one required constraint to return to best-effort ranking.'
                    : 'Try one change at a time. Your preference stays active for ranking.',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
              if (onRelax != null && relaxations.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final relaxation in relaxations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => onRelax!(relaxation),
                        icon: const Icon(Icons.lock_open_outlined, size: 17),
                        label: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(relaxation.label),
                              Text(
                                relaxation.detail,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGenerating
                  ? Icons.hourglass_top_rounded
                  : Icons.table_chart_outlined,
              size: 48,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isGenerating
                ? 'Generating timetables...'
                : 'No timetables generated yet',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isGenerating
                ? 'This may take a few moments'
                : 'Select courses and click Generate to see results',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
          if (isGenerating) ...[
            const SizedBox(height: 20),
            CircularProgressIndicator(color: scheme.primary, strokeWidth: 3),
          ],
        ],
      ),
    );
  }
}

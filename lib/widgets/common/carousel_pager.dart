import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

/// Position in a horizontally swiped list: `‹ 3/20 ›`.
///
/// A count rather than a dot per page — twenty dots is a smear that tells you
/// neither where you are nor how many are left, and the two screens using this
/// both went past the handful of options dots were drawn for.
class CarouselPager extends StatelessWidget {
  const CarouselPager({
    super.key,
    required this.page,
    required this.count,
    required this.onGoTo,
  });

  /// Zero-based, displayed one-based.
  final int page;
  final int count;
  final ValueChanged<int> onGoTo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page == 0 ? null : () => onGoTo(page - 1),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous',
          ),
          Text(
            '${page + 1}/$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              // Tabular figures so the row does not shift as the number widens
              // from 9 to 10.
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurface.withValues(alpha: AppDesign.opacityHigh),
            ),
          ),
          IconButton(
            onPressed: page >= count - 1 ? null : () => onGoTo(page + 1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next',
          ),
        ],
      ),
    );
  }
}

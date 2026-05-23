import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

class InlineErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;

  const InlineErrorCard({
    super.key,
    required this.message,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(AppDesign.spacingMd),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spacingMd),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error),
            const SizedBox(width: AppDesign.spacingSm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDismiss,
                tooltip: 'Dismiss error',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }
}

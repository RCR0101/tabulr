import 'package:flutter/material.dart';
import '../../utils/design_constants.dart';

/// A standardized modal loading overlay.
///
/// Shows a non-dismissible centered spinner (with an optional [message]) on top
/// of the current route. Dismiss it with [hide], or any `Navigator.pop` on the
/// same context. Use instead of ad-hoc `showDialog(... CircularProgressIndicator)`
/// overlays so loading states look consistent app-wide.
class AppLoadingOverlay {
  AppLoadingOverlay._();

  /// Shows the overlay. Pair every call with a matching [hide].
  static void show(BuildContext context, {String? message}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppDesign.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (message != null) ...[
                    const SizedBox(height: AppDesign.spacingMd),
                    Text(message, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Dismisses an overlay previously shown with [show].
  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }
}

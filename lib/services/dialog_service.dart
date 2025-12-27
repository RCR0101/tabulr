import 'package:flutter/material.dart';

/// Service for managing common dialog patterns throughout the app
class DialogService {
  /// Show a simple error dialog with an OK button
  static Future<void> showErrorDialog({
    required BuildContext context,
    required String title,
    required String message,
    String? actionText,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(actionText ?? 'OK'),
            ),
          ],
        );
      },
    );
  }

  /// Show a confirmation dialog with Yes/No options
  static Future<bool> showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelText ?? 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: isDestructive
                  ? TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              child: Text(confirmText ?? 'Confirm'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  /// Show a success dialog with an OK button
  static Future<void> showSuccessDialog({
    required BuildContext context,
    required String title,
    required String message,
    String? actionText,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(actionText ?? 'OK'),
            ),
          ],
        );
      },
    );
  }

  /// Show a loading dialog that can be dismissed programmatically
  static Future<T?> showLoadingDialog<T>({
    required BuildContext context,
    required String message,
    required Future<T> future,
  }) async {
    // Show the dialog
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );

    try {
      // Wait for the future to complete
      final result = await future;
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      return result;
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      rethrow;
    }
  }

  /// Show an info dialog with optional actions
  static Future<void> showInfoDialog({
    required BuildContext context,
    required String title,
    required String message,
    List<Widget>? actions,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: actions ??
              [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
        );
      },
    );
  }

  /// Show a choice dialog with multiple options
  static Future<String?> showChoiceDialog({
    required BuildContext context,
    required String title,
    required String message,
    required List<String> choices,
    String? cancelText,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isNotEmpty) ...[
                Text(message),
                const SizedBox(height: 16),
              ],
              ...choices.map((choice) => 
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(choice),
                    child: Text(choice, textAlign: TextAlign.left),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (cancelText != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(cancelText),
              ),
          ],
        );
      },
    );
  }

  /// Show a custom dialog with a builder function
  static Future<T?> showCustomDialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
  }) async {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  /// Show a bottom sheet dialog for mobile-friendly options
  static Future<T?> showBottomSheet<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool isScrollControlled = false,
  }) async {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: builder,
    );
  }
}
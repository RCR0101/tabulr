import 'package:flutter/material.dart';
import '../utils/error_messages.dart';
import 'common/app_dialog.dart';
import 'common/app_button.dart';

class ErrorDialog {
  /// Shows [message] in a standard error dialog.
  ///
  /// By default [message] is treated as a raw error and run through
  /// [getUserFriendlyError], which maps known failure signatures (network,
  /// permission, …) to plain language. Pass `translate: false` when the caller
  /// has already built a user-ready message — otherwise the translator, finding
  /// no known signature, would flatten it to the generic "Something went wrong".
  static void show(BuildContext context, String message,
      {bool translate = true}) {
    final userMessage = translate ? getUserFriendlyError(message) : message;
    AppDialog.adaptive(
      context: context,
      title: 'Error',
      icon: Icons.error_outline,
      iconColor: Theme.of(context).colorScheme.error,
      content: Text(userMessage),
      actions: [
        AppButton(
          label: 'OK',
          variant: AppButtonVariant.primary,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

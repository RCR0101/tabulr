import 'package:flutter/material.dart';
import '../utils/error_messages.dart';
import 'common/app_dialog.dart';
import 'common/app_button.dart';

class ErrorDialog {
  static void show(BuildContext context, String message) {
    final userMessage = getUserFriendlyError(message);
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

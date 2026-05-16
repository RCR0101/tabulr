import 'package:flutter/material.dart';
import '../utils/error_messages.dart';

class ErrorDialog {
  static void show(BuildContext context, String message) {
    final userMessage = getUserFriendlyError(message);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(userMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

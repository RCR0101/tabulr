import 'package:flutter/material.dart';
import '../../widgets/common/app_toast.dart' as toast;

class ToastService {
  static final ToastService _instance = ToastService._internal();
  factory ToastService() => _instance;
  ToastService._internal();

  static void init(BuildContext context) {
    toast.AppToast.init(context);
  }

  static void showSuccess(String message) {
    toast.AppToast.showSuccess(message);
  }

  /// Pass [actionLabel] + [onAction] to attach a button (e.g. "Override").
  /// Actionable toasts stay on screen longer so there is time to press it.
  static void showError(String message, {String? actionLabel, VoidCallback? onAction}) {
    toast.AppToast.showError(message, actionLabel: actionLabel, onAction: onAction);
  }

  static void showInfo(String message) {
    toast.AppToast.showInfo(message);
  }

  static void showWarning(String message, {String? actionLabel, VoidCallback? onAction}) {
    toast.AppToast.showWarning(message, actionLabel: actionLabel, onAction: onAction);
  }

  static void cancel() {
    toast.AppToast.dismiss();
  }
}

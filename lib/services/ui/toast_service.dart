import 'package:flutter/material.dart';
import '../../widgets/common/app_toast.dart' as toast;

enum ToastType {
  success,
  error,
  info,
  warning,
}

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

  static void showError(String message) {
    toast.AppToast.showError(message);
  }

  static void showInfo(String message) {
    toast.AppToast.showInfo(message);
  }

  static void showWarning(String message) {
    toast.AppToast.showWarning(message);
  }

  static void cancel() {
    toast.AppToast.dismiss();
  }
}

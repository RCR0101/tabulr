import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

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

  static void showSuccess(String message) {
    _showToast(
      message: message,
      type: ToastType.success,
    );
  }

  static void showError(String message) {
    _showToast(
      message: message,
      type: ToastType.error,
    );
  }

  static void showInfo(String message) {
    _showToast(
      message: message,
      type: ToastType.info,
    );
  }

  static void showWarning(String message) {
    _showToast(
      message: message,
      type: ToastType.warning,
    );
  }

  static void _showToast({
    required String message,
    required ToastType type,
  }) {
    final (Color backgroundColor, String webBgColor) = switch (type) {
      ToastType.success => (const Color(0xFF065F46), "#065F46"),
      ToastType.error => (const Color(0xFF991B1B), "#991B1B"),
      ToastType.warning => (const Color(0xFF92400E), "#92400E"),
      ToastType.info => (const Color(0xFF1E40AF), "#1E40AF"),
    };

    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 3,
      backgroundColor: backgroundColor,
      textColor: Colors.white,
      fontSize: 16.0,
      webBgColor: webBgColor,
      webPosition: "center",
      webShowClose: true,
    );
  }


  static void cancel() {
    Fluttertoast.cancel();
  }
}
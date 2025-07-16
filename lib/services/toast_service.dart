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
    Color backgroundColor;
    Color textColor = Colors.white;

    // Dark theme with colored accent
    switch (type) {
      case ToastType.success:
        backgroundColor = const Color(0xFF1F2937); // Dark gray with success accent
        break;
      case ToastType.error:
        backgroundColor = const Color(0xFF1F2937); // Dark gray with error accent
        break;
      case ToastType.warning:
        backgroundColor = const Color(0xFF1F2937); // Dark gray with warning accent
        break;
      case ToastType.info:
        backgroundColor = const Color(0xFF1F2937); // Dark gray with info accent
        break;
    }

    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 3,
      backgroundColor: backgroundColor,
      textColor: textColor,
      fontSize: 16.0,
      webBgColor: "#1F2937",
      webPosition: "center",
      webShowClose: true,
    );
  }


  static void cancel() {
    Fluttertoast.cancel();
  }
}
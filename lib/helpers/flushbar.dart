import 'package:flutter/material.dart';
import 'package:another_flushbar/flushbar.dart';

class AppFlushbar {
  AppFlushbar._();

  /// Show a success message
  static void showSuccess(
    BuildContext context,
    String message, {
    String title = 'Success',
    Duration duration = const Duration(seconds: 3),
  }) {
    _showFlushbar(
      context,
      title: title,
      message: message,
      icon: const Icon(Icons.check_circle, color: Colors.white),
      backgroundColor: Colors.green,
      duration: duration,
    );
  }

  /// Show an error message
  static void showError(
    BuildContext context,
    String message, {
    String title = 'Error',
    Duration duration = const Duration(seconds: 3),
  }) {
    _showFlushbar(
      context,
      title: title,
      message: message,
      icon: const Icon(Icons.error, color: Colors.white),
      backgroundColor: Colors.red,
      duration: duration,
    );
  }

  /// Show an informational message
  static void showInfo(
    BuildContext context,
    String message, {
    String title = 'Info',
    Duration duration = const Duration(seconds: 3),
  }) {
    _showFlushbar(
      context,
      title: title,
      message: message,
      icon: const Icon(Icons.info_outline, color: Colors.white),
      backgroundColor: Colors.blue,
      duration: duration,
    );
  }

  static void _showFlushbar(
    BuildContext context, {
    required String title,
    required String message,
    required Widget icon,
    required Color backgroundColor,
    required Duration duration,
  }) {
    Flushbar(
      title: title,
      message: message,
      icon: icon,
      duration: duration,
      backgroundColor: backgroundColor,
      margin: const EdgeInsets.all(8),
      flushbarPosition: FlushbarPosition.BOTTOM,
      borderRadius: BorderRadius.circular(8),
      animationDuration: const Duration(milliseconds: 300),
    )..show(context);
  }
}

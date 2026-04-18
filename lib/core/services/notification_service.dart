import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_service.g.dart';

@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) {
  return NotificationService();
}

/// A global service to manage UI notifications (SnackBars) without needing a [BuildContext].
/// This is particularly useful for background tasks, providers, and deep nested components.
class NotificationService {
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  void showSnackBar(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void showError(String message) {
    showSnackBar(
      message,
      backgroundColor: Colors.red.shade800,
    );
  }

  void showSuccess(String message) {
    showSnackBar(
      message,
      backgroundColor: Colors.green.shade800,
    );
  }

  void showInfo(String message) {
    showSnackBar(
      message,
      backgroundColor: Colors.blue.shade800,
    );
  }

  void clearSnackBars() {
    messengerKey.currentState?.clearSnackBars();
  }
}

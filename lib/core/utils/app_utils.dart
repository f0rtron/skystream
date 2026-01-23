import 'package:flutter/material.dart';
import 'package:app_restarter/app_restarter.dart';
import '../../../../main.dart' as app_main;

class AppUtils {
  static Future<void> restartApp(BuildContext context) async {
    try {
      // Use app_restarter package for cross-platform restart
      await AppRestarter.restartApp(context);
    } catch (e) {
      debugPrint("AppRestarter failed: $e. Falling back to main().");
      // Fallback if package fails (e.g. context issue)
      app_main.main();
    }
  }
}

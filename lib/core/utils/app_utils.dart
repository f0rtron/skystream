import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_restarter/app_restarter.dart';

class AppUtils {
  static Future<void> restartApp(BuildContext context) async {
    try {
      // Use app_restarter package for cross-platform restart
      await AppRestarter.restartApp(context);
    } catch (e) {
      if (kDebugMode) {
        debugPrint("AppRestarter failed: $e. Falling back to main().");
      }
    }
  }

  static bool isLocalFile(String path) {
    if (path.isEmpty) return false;
    // Android/Linux/macOS absolute
    if (path.startsWith('/')) return true;
    // Windows absolute (C:\ or D:/)
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)) return true;
    // File URL
    if (path.startsWith('file:')) return true;
    return false;
  }

  static String normalizeUrl(String url) {
    if (url.isEmpty) return url;
    if (Platform.isAndroid) return url;

    if (isLocalFile(url) && !url.startsWith('file:')) {
      if (url.startsWith('/')) {
        return 'file://$url';
      }
      // Windows absolute path like C:\
      // Standardize on forward slashes for valid file:/// URIs
      final standardizedPath = url.replaceAll('\\', '/');
      return 'file:///$standardizedPath';
    }
    return url;
  }
}

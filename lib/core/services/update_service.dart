import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:version/version.dart';

import '../data/models/github_release.dart';

import '../network/dio_client_provider.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(ref.watch(dioClientProvider));
});

class UpdateService {
  final Dio _dio;
  static const String _owner = 'akashdh11';
  static const String _repo = 'skystream';

  UpdateService(this._dio);

  Future<GithubRelease?> checkForUpdate() async {
    try {
      final currentPackageInfo = await PackageInfo.fromPlatform();
      final currentVersion = Version.parse(currentPackageInfo.version);

      final response = await _dio.get(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );

      if (response.statusCode == 200) {
        final release = GithubRelease.fromJson(response.data);
        // Clean tag name (remove 'v' prefix if present)
        final tagName = release.tagName.replaceAll(RegExp(r'^v'), '');
        final latestVersion = Version.parse(tagName);

        if (latestVersion > currentVersion) {
          return release;
        }
      }
    } catch (e) {
      // Fail silently or log error
      if (kDebugMode) debugPrint('Update check failed: $e');
    }
    return null;
  }

  Future<File?> downloadUpdateAsset(
    GithubRelease release,
    Function(double) onProgress,
  ) async {
    try {
      final asset = _findPlatformAsset(release);
      if (asset == null) return null;

      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/${asset.name}';

      await _dio.download(
        asset.browserDownloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      return File(savePath);
    } catch (e) {
      if (kDebugMode) debugPrint('Download failed: $e');
      return null;
    }
  }

  GithubAsset? _findPlatformAsset(GithubRelease release) {
    if (Platform.isAndroid) {
      return release.assets.firstWhere(
        (a) => a.name.endsWith('.apk'),
        orElse: () => throw Exception('No APK found'),
      );
    } else if (Platform.isWindows) {
      return release.assets.firstWhere(
        (a) =>
            a.name.endsWith('.exe') ||
            a.name.endsWith('.msix') ||
            a.name.endsWith('.zip'),
        orElse: () => throw Exception('No Windows installer found'),
      );
    } else if (Platform.isMacOS) {
      return release.assets.firstWhere(
        (a) => a.name.endsWith('.dmg') || a.name.endsWith('.zip'),
        orElse: () => throw Exception('No DMG or ZIP found'),
      );
    } else if (Platform.isLinux) {
      return release.assets.firstWhere(
        (a) => a.name.endsWith('.AppImage') || a.name.endsWith('.deb'),
        orElse: () => throw Exception('No Linux installer found'),
      );
    }
    return null;
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:collection/collection.dart';
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
      final asset = await findPlatformAsset(release);
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

  Future<GithubAsset?> findPlatformAsset(GithubRelease release) async {
    final assets =
        release.assets.where((a) => !a.name.contains('debug')).toList();

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;

      // 1. Match specific ABI (arm64-v8a, armeabi-v7a, x86_64)
      for (final abi in abis) {
        final match = assets.firstWhereOrNull(
            (a) => a.name.contains('android') && a.name.contains(abi));
        if (match != null) return match;
      }

      // 2. Fallback to universal
      final universal = assets.firstWhereOrNull(
          (a) => a.name.contains('android') && a.name.contains('universal'));
      if (universal != null) return universal;

      // 3. Last resort: any APK
      return assets.firstWhereOrNull(
          (a) => a.name.contains('android') && a.name.endsWith('.apk'));
    } else if (Platform.isWindows) {
      final arch = Platform.environment['PROCESSOR_ARCHITECTURE']
              ?.toLowerCase() ??
          'x64';
      final isArm = arch.contains('arm') || arch.contains('aarch64');
      final archTag = isArm ? 'arm64' : 'x64';

      // 1. Match windows specific build with architecture
      var match = assets.firstWhereOrNull(
        (a) => a.name.contains('windows') && a.name.contains(archTag),
      );

      // Fallback for x86_64 / amd64 naming
      if (match == null && !isArm) {
        match = assets.firstWhereOrNull(
          (a) => a.name.contains('windows') && a.name.contains('x86_64'),
        );
      }

      if (match != null) return match;

      // 2. Fallback to any windows installer
      return assets.firstWhereOrNull(
        (a) =>
            a.name.contains('windows') &&
            (a.name.endsWith('.exe') ||
                a.name.endsWith('.msix') ||
                a.name.endsWith('.zip')),
      );
    } else if (Platform.isMacOS) {
      final info = await DeviceInfoPlugin().macOsInfo;
      final arch = info.arch; // e.g. "arm64" or "x86_64"

      // Match architecture in filename if present
      var match = assets.firstWhereOrNull(
          (a) => a.name.contains('macos') && a.name.contains(arch));

      // Fallback for x64 alias
      if (match == null && arch == 'x86_64') {
        match = assets.firstWhereOrNull(
            (a) => a.name.contains('macos') && a.name.contains('x64'));
      }

      if (match != null) return match;

      return assets.firstWhereOrNull(
        (a) =>
            a.name.contains('macos') &&
            (a.name.endsWith('.dmg') || a.name.endsWith('.zip')),
      );
    } else if (Platform.isLinux) {
      final version = Platform.version.toLowerCase();
      final isArm = version.contains('arm') || version.contains('aarch64');
      final archTag = isArm ? 'arm64' : 'x64';

      // 1. Try matching architecture
      var match = assets.firstWhereOrNull(
        (a) => a.name.contains('linux') && a.name.contains(archTag),
      );

      // Fallback for x86_64 alias
      if (match == null && !isArm) {
        match = assets.firstWhereOrNull(
          (a) => a.name.contains('linux') && a.name.contains('x86_64'),
        );
      }

      if (match != null) return match;

      // 2. Fallback to any Linux installer type
      return assets.firstWhereOrNull(
        (a) =>
            a.name.contains('linux') &&
            (a.name.endsWith('.AppImage') ||
                a.name.endsWith('.deb') ||
                a.name.endsWith('.tar.gz')),
      );
    }
    return null;
  }
}

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceProfile {
  final bool isTv;

  /// Indicates if running on a desktop operating system (macOS, Windows, Linux)
  /// Use this for capability checks (e.g. window controls, mouse hovers), 
  /// NOT for layout sizing. Use [ResponsiveBreakpoints] for layout sizing.
  final bool isDesktopOS; 

  const DeviceProfile({
    this.isTv = false,
    this.isDesktopOS = false,
  });
}

final deviceProfileProvider = FutureProvider<DeviceProfile>((ref) async {
  bool isTv = false;
  bool isDesktopOS = false;

  if (!kIsWeb) {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      isTv = androidInfo.systemFeatures.contains('android.software.leanback');
    }

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      isDesktopOS = true;
    }
  }

  return DeviceProfile(
    isTv: isTv,
    isDesktopOS: isDesktopOS,
  );
});

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../../settings/presentation/player_settings_provider.dart';

class PlayerGestureHandler extends ChangeNotifier {
  final Player player;
  final Future<PlayerSettings> Function() getSettings;
  final bool isTv;
  final bool isDesktop;

  // State from player
  Duration Function() getDuration;
  Duration Function() getPosition;

  // Callbacks to interact with UI
  final VoidCallback onInteraction;
  final VoidCallback onHideControls;
  final void Function(Duration) onSeekRelative;
  final void Function(bool isLeft, Offset tapPos, int seekSeconds)
  onDoubleTapAnimationStart;

  // Local State
  PlayerGesture? currentGesture;
  bool showOSD = false;
  IconData osdIcon = Icons.settings;
  double? osdValue;
  String osdLabel = "";
  Alignment osdAlignment = Alignment.center;
  Duration? swipeSeekValue;

  double _boostLevel = 1.0;
  Timer? _osdTimer;

  PlayerGestureHandler({
    required this.player,
    required this.getSettings,
    required this.isTv,
    required this.isDesktop,
    required this.getDuration,
    required this.getPosition,
    required this.onInteraction,
    required this.onHideControls,
    required this.onSeekRelative,
    required this.onDoubleTapAnimationStart,
  });

  @override
  void dispose() {
    _osdTimer?.cancel();
    super.dispose();
  }

  void _triggerOSDTimer() {
    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(seconds: 1), () {
      showOSD = false;
      notifyListeners();
    });
  }

  /// Dismiss the OSD overlay (e.g. on tap). Call [notifyListeners] so listeners can rebuild.
  void dismissOSD() {
    showOSD = false;
    notifyListeners();
  }

  void showToast(String message, IconData icon) {
    showOSD = true;
    osdIcon = icon;
    osdLabel = message;
    osdValue = null;
    osdAlignment = Alignment.bottomCenter;
    notifyListeners();

    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(seconds: 2), () {
      showOSD = false;
      notifyListeners();
    });
  }

  Future<void> handleDragStart(
    DragStartDetails details,
    double screenWidth,
  ) async {
    if (isTv || isDesktop) return;

    onHideControls();

    final x = details.globalPosition.dx;
    final settings = await getSettings();

    PlayerGesture type = PlayerGesture.none;
    if (x < screenWidth / 2) {
      type = settings.leftGesture;
      osdAlignment = Alignment.centerRight; // Opposite side
    } else {
      type = settings.rightGesture;
      osdAlignment = Alignment.centerLeft; // Opposite side
    }

    if (type == PlayerGesture.none) return;

    currentGesture = type;

    double startVal = 0.5;
    if (type == PlayerGesture.brightness) {
      try {
        startVal = await ScreenBrightness().application;
      } catch (e) {
        startVal = 0.5;
      }
    } else {
      startVal = (await FlutterVolumeController.getVolume()) ?? 0.5;
      if (_boostLevel > 1.0) startVal = _boostLevel;
    }

    showOSD = true;
    osdIcon = _getIconForValue(type, startVal);
    osdValue = startVal;
    osdLabel = type == PlayerGesture.brightness ? "Brightness" : "Volume";
    notifyListeners();

    _osdTimer?.cancel();
  }

  void handleDragUpdate(DragUpdateDetails details) {
    if (currentGesture == null || currentGesture == PlayerGesture.none) return;

    final delta = -details.primaryDelta! / 300;

    final double min = (currentGesture == PlayerGesture.brightness)
        ? -0.05
        : 0.0;
    final double max = (currentGesture == PlayerGesture.brightness) ? 1.0 : 2.0;

    final double newVal = ((osdValue ?? 0.0) + delta).clamp(min, max);

    osdValue = newVal;
    osdIcon = _getIconForValue(currentGesture!, newVal);

    if (currentGesture == PlayerGesture.brightness) {
      if (newVal <= 0.0) {
        ScreenBrightness().resetApplicationScreenBrightness();
        osdLabel = "Auto";
      } else {
        ScreenBrightness().setApplicationScreenBrightness(newVal);
        osdLabel = "Brightness";
      }
    } else {
      if (newVal > 1.0) {
        _boostLevel = newVal;
        player.setVolume(newVal * 100);
      } else {
        _boostLevel = 1.0;
        player.setVolume(100);
        FlutterVolumeController.setVolume(newVal);
      }
    }
    notifyListeners();
  }

  void handleDragEnd(DragEndDetails details) {
    currentGesture = null;
    _triggerOSDTimer();
  }

  Future<void> handleHorizontalDragStart(
    DragStartDetails details,
    bool isControlsVisible,
    double screenHeight,
    double bottomPadding,
  ) async {
    if (getDuration() == Duration.zero) return;

    final swipeSettings = await getSettings();
    if (!swipeSettings.swipeSeekEnabled) return;

    if (isTv || isDesktop) return;

    if (isControlsVisible) {
      if (details.globalPosition.dy > (screenHeight - 100 - bottomPadding)) {
        return; // Avoid conflict with seek bar
      }
      onHideControls();
    }

    swipeSeekValue = getPosition();
    notifyListeners();
  }

  void handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (swipeSeekValue == null) return;

    final delta = details.primaryDelta ?? 0;
    final newMs = (swipeSeekValue!.inMilliseconds + (delta * 200)).toInt();
    final clamped = newMs.clamp(0, getDuration().inMilliseconds);

    swipeSeekValue = Duration(milliseconds: clamped);
    notifyListeners();
  }

  void handleHorizontalDragEnd(DragEndDetails details) {
    if (swipeSeekValue == null) return;
    player.seek(swipeSeekValue!);
    swipeSeekValue = null;
    notifyListeners();
  }

  Future<void> handleDoubleTap(Offset tapPosition, double screenWidth) async {
    if (getDuration() == Duration.zero) return;

    final settings = await getSettings();
    if (!settings.doubleTapEnabled) return;

    final isLeft = tapPosition.dx < screenWidth / 2;
    final seconds = settings.seekDuration;

    onDoubleTapAnimationStart(isLeft, tapPosition, seconds);

    if (isLeft) {
      onSeekRelative(Duration(seconds: -seconds));
    } else {
      onSeekRelative(Duration(seconds: seconds));
    }
  }

  Future<void> toggleMute() async {
    final currentVol = player.state.volume;
    if (currentVol > 0) {
      player.setVolume(0);
      showToast("Mute", Icons.volume_off);
    } else {
      player.setVolume(100);
      changeVolume(0);
    }
  }

  Future<void> changeVolume(double step) async {
    double current = (await FlutterVolumeController.getVolume()) ?? 0.5;

    if (step > 0) {
      if (current >= 1.0) {
        _boostLevel = (_boostLevel + step * 2).clamp(1.0, 2.0);
        player.setVolume(_boostLevel * 100);
      } else {
        _boostLevel = 1.0;
        player.setVolume(100);
        await FlutterVolumeController.setVolume(
          (current + step).clamp(0.0, 1.0),
        );
      }
    } else {
      if (_boostLevel > 1.0) {
        _boostLevel = (_boostLevel + step * 2).clamp(1.0, 2.0);
        player.setVolume(_boostLevel * 100);
      } else {
        await FlutterVolumeController.setVolume(
          (current + step).clamp(0.0, 1.0),
        );
      }
    }

    current = (await FlutterVolumeController.getVolume()) ?? 0.5;

    onHideControls();

    showOSD = true;
    osdIcon = _getIconForValue(PlayerGesture.volume, current);
    if (_boostLevel > 1.0) {
      osdValue = _boostLevel;
      osdLabel = "Volume ${(_boostLevel * 100).toInt()}%";
    } else {
      osdValue = current;
      osdLabel = "Volume ${(current * 100).toInt()}%";
    }
    notifyListeners();
    _triggerOSDTimer();
  }

  IconData _getIconForValue(PlayerGesture type, double value) {
    if (type == PlayerGesture.brightness) {
      if (value <= 0.0) return Icons.brightness_auto;
      if (value < 0.3) return Icons.brightness_low;
      if (value < 0.7) return Icons.brightness_medium;
      return Icons.brightness_high;
    } else if (type == PlayerGesture.volume) {
      if (value <= 0.0) return Icons.volume_off;
      if (value < 0.3) return Icons.volume_mute;
      if (value < 0.7) return Icons.volume_down;
      if (value <= 1.0) return Icons.volume_up;
      return Icons.campaign; // Boost icon
    }
    return Icons.settings;
  }
}

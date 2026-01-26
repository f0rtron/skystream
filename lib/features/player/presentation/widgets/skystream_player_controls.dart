import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/models/torrent_status.dart'; // Added
import '../components/torrent_info_widget.dart'; // Added
import '../../../settings/presentation/player_settings_provider.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../shared/widgets/tv_input_widgets.dart';

class SkyStreamPlayerControls extends ConsumerStatefulWidget {
  final Player player;
  final String title;
  final String? subtitle;
  final VoidCallback? onBackPointer;
  final List<StreamResult>? streams;
  final StreamResult? currentStream;

  final List<SubtitleFile>? externalSubtitles;
  final TorrentStatus? torrentStatus;
  final Function(StreamResult)? onStreamSelected;
  final Function(int)? onTorrentFileSelected;
  final Function(BoxFit)? onResize;
  final Function(bool)? onVisibilityChanged;

  const SkyStreamPlayerControls({
    super.key,
    required this.player,
    required this.title,
    this.subtitle,
    this.onBackPointer,
    this.streams,
    this.currentStream,
    this.externalSubtitles,
    this.torrentStatus,
    this.onStreamSelected,
    this.onTorrentFileSelected,
    this.onResize,
    this.onVisibilityChanged,
    this.isLoading = false,
    this.forceShowControls = false,
  });

  final bool isLoading;
  final bool forceShowControls;

  @override
  ConsumerState<SkyStreamPlayerControls> createState() =>
      SkyStreamPlayerControlsState();
}

class SkyStreamPlayerControlsState
    extends ConsumerState<SkyStreamPlayerControls>
    with SingleTickerProviderStateMixin {
  final FocusNode _backFocusNode = FocusNode();
  bool _isVisible = false;
  bool _isIpad = false;
  bool _isTv = false;
  bool _isInPip = false;

  void focusBack() {
    _backFocusNode.requestFocus();
  }

  static const Map<String, String> _isoLanguages = {
    'af': 'Afrikaans',
    'ar': 'Arabic',
    'az': 'Azerbaijani',
    'be': 'Belarusian',
    'bg': 'Bulgarian',
    'bn': 'Bengali',
    'bs': 'Bosnian',
    'ca': 'Catalan',
    'cs': 'Czech',
    'cy': 'Welsh',
    'da': 'Danish',
    'de': 'German',
    'el': 'Greek',
    'en': 'English',
    'es': 'Spanish',
    'et': 'Estonian',
    'fa': 'Persian',
    'fi': 'Finnish',
    'fr': 'French',
    'gl': 'Galician',
    'gu': 'Gujarati',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'hr': 'Croatian',
    'hu': 'Hungarian',
    'hy': 'Armenian',
    'id': 'Indonesian',
    'is': 'Icelandic',
    'it': 'Italian',
    'ja': 'Japanese',
    'ka': 'Georgian',
    'kk': 'Kazakh',
    'km': 'Khmer',
    'kn': 'Kannada',
    'ko': 'Korean',
    'ky': 'Kyrgyz',
    'lt': 'Lithuanian',
    'lv': 'Latvian',
    'mk': 'Macedonian',
    'ml': 'Malayalam',
    'mn': 'Mongolian',
    'mr': 'Marathi',
    'ms': 'Malay',
    'my': 'Burmese',
    'ne': 'Nepali',
    'nl': 'Dutch',
    'no': 'Norwegian',
    'pa': 'Punjabi',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'si': 'Sinhala',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'sq': 'Albanian',
    'sr': 'Serbian',
    'sv': 'Swedish',
    'sw': 'Swahili',
    'ta': 'Tamil',
    'te': 'Telugu',
    'th': 'Thai',
    'tl': 'Tagalog',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'uz': 'Uzbek',
    'vi': 'Vietnamese',
    'zh': 'Chinese',
    'zu': 'Zulu',
    // 3-letter support
    'eng': 'English',
    'hin': 'Hindi',
    'jap': 'Japanese',
    'spa': 'Spanish',
    'fra': 'French',
    'deu': 'German',
    'ita': 'Italian',
    'rus': 'Russian',
    'por': 'Portuguese',
    'kor': 'Korean',
  };

  bool _showTorrentInfo = false; // Changed from true
  Timer? _hideTimer;
  bool _isLocked = false;
  double? _dragValue;
  Duration? _swipeSeekValue; // Horizontal drag value
  double _boostLevel = 1.0;

  // Seek animation state
  late AnimationController _seekAnimController;
  bool _isSeekingLeft = false;

  int _resizeMode = 0;

  late bool _isPlaying;
  late bool _isBuffering;
  late Duration _position;
  late Duration _duration;

  final List<StreamSubscription> _subscriptions = [];

  String _getLanguageName(String code) {
    final normalized = code.toLowerCase().trim();
    if (normalized == 'no' || normalized == 'off' || normalized == 'none') {
      return 'Off';
    }
    if (normalized == 'auto') return 'Auto';
    // Original app logic fallback for unmapped
    return _isoLanguages[normalized] ?? code;
  }

  // Gesture State
  PlayerGesture? _currentGesture;
  Alignment _osdAlignment = Alignment.center;
  Offset? _tapPosition;

  // OSD State
  bool _showOSD = false;
  IconData _osdIcon = Icons.settings;
  double? _osdValue = 0.0;
  String _osdLabel = "";
  Timer? _osdTimer;
  Duration _animDuration = const Duration(milliseconds: 300);
  bool _isFullscreen = false;
  late final FocusNode _playFocusNode;

  @override
  void initState() {
    super.initState();
    _isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;
    _playFocusNode = FocusNode();
    try {
      FlutterVolumeController.updateShowSystemUI(false);
    } catch (e) {
      debugPrint("VolumeUI Error: $e");
    }
    _checkIpad();
    _isPlaying = widget.player.state.playing;
    _isBuffering = widget.player.state.buffering;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;

    _subscriptions.addAll([
      widget.player.stream.playing.listen((val) {
        if (mounted) setState(() => _isPlaying = val);
        if (val) {
          _startHideTimer();
        } else {
          _cancelHideTimer();
        }

        // Sync PiP state with Android
        if (Platform.isAndroid) {
          const MethodChannel(
            'dev.akash.skystream.player/pip',
          ).invokeMethod('setPipState', {'isPlaying': val});
        }
      }),
      widget.player.stream.buffering.listen((val) {
        if (mounted) setState(() => _isBuffering = val);
      }),
      widget.player.stream.position.listen((val) {
        if (mounted) setState(() => _position = val);
      }),
      widget.player.stream.duration.listen((val) {
        if (mounted) {
          if (_duration == Duration.zero && val != Duration.zero) {
            _isVisible = true;
            _startHideTimer();
          }
          setState(() => _duration = val);
        }
      }),
      widget.player.stream.width.listen((_) => _updateOrientation()),
      widget.player.stream.height.listen((_) => _updateOrientation()),
    ]);

    _seekAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _seekAnimController.addListener(() {
      setState(() {});
    });

    if (Platform.isAndroid) {
      const MethodChannel(
        'dev.akash.skystream.player/pip',
      ).setMethodCallHandler((call) async {
        switch (call.method) {
          case 'pipModeChanged':
            if (mounted) {
              setState(() {
                _isInPip = call.arguments as bool;
              });
            }
            break;
          case 'play':
            widget.player.play();
            break;
          case 'pause':
            widget.player.pause();
            break;
          case 'seekForward':
            _seekRelative(const Duration(seconds: 10));
            break;
          case 'seekBackward':
            _seekRelative(const Duration(seconds: -10));
            break;
        }
      });
    }

    _isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;

    if (widget.streams != null && widget.streams!.isNotEmpty) {
      _isVisible = true;
    }
    _startHideTimer();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(SkyStreamPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceShowControls && !oldWidget.forceShowControls) {
      // Defer state updates to avoid 'setState during build' error
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isVisible = true;
          });
          widget.onVisibilityChanged?.call(true);
          _startHideTimer();
          _playFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _checkIpad() async {
    if (Platform.isIOS) {
      try {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        if (iosInfo.model.toLowerCase().contains("ipad")) {
          if (mounted) setState(() => _isIpad = true);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _playFocusNode.dispose();
    _backFocusNode.dispose();
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _seekAnimController.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (e) {}
    try {
      FlutterVolumeController.updateShowSystemUI(true);
    } catch (e) {}
    SystemChrome.setPreferredOrientations([]); // Reset to system default
    super.dispose();
  }

  void _updateOrientation() {
    // Lock orientation on Desktop
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return;
    } catch (_) {}

    final w = widget.player.state.width;
    final h = widget.player.state.height;
    if (w != null && h != null && w > 0 && h > 0) {
      if (w >= h) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
  }

  Future<void> _enterPip() async {
    try {
      const platform = MethodChannel('dev.akash.skystream.player/pip');
      await platform.invokeMethod('enterPip', {'isPlaying': _isPlaying});
    } catch (e) {
      debugPrint("PIP Error: $e");
    }
  }

  void _toggleOrientation() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> toggleFullscreen() async {
    if (Platform.isAndroid || Platform.isIOS) return;
    try {
      final isFull = await windowManager.isFullScreen();
      if (!isFull) {
        // Going Custom Fullscreen (Hide TitleBar)
        if (Platform.isWindows || Platform.isLinux) {
          // Explicitly hide title bar to remove borders on Windows
          await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        }
        await windowManager.setFullScreen(true);
      } else {
        // Exiting Fullscreen
        await windowManager.setFullScreen(false);
        if (Platform.isWindows || Platform.isLinux) {
          // Restore title bar
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        }
      }

      if (mounted) {
        setState(() {
          _isFullscreen = !isFull;
        });
      }
    } catch (_) {}
  }

  void _handleDoubleTap() {
    // Desktop Double Tap -> Toggle Fullscreen
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        toggleFullscreen();
        return;
      }
    } catch (_) {}

    if (widget.isLoading) return;
    if (_duration == Duration.zero) return;

    if (_tapPosition == null) return;
    final settings = ref.read(playerSettingsProvider);
    if (!settings.doubleTapEnabled) return;

    final width = MediaQuery.of(context).size.width;
    final isLeft = _tapPosition!.dx < width / 2;

    setState(() {
      _isSeekingLeft = isLeft;
    });
    _seekAnimController.forward(from: 0.0);

    final seconds = settings.seekDuration;

    if (_tapPosition!.dx < width / 2) {
      _seekRelative(Duration(seconds: -seconds));
    } else {
      _seekRelative(Duration(seconds: seconds));
    }
  }

  // ... (keeping other methods same)

  void _toggleVisibility() {
    _animDuration = const Duration(milliseconds: 300);
    setState(() {
      _isVisible = !_isVisible;
    });
    widget.onVisibilityChanged?.call(_isVisible);
    if (_isVisible) {
      _startHideTimer();
    }
  }

  void hideControls() {
    if (mounted) {
      _hideTimer?.cancel();
      setState(() => _isVisible = false);
      widget.onVisibilityChanged?.call(false);
    }
  }

  void showControls() {
    if (mounted) {
      setState(() => _isVisible = true);
      widget.onVisibilityChanged?.call(true);
      _startHideTimer();
    }
  }

  void _onFocusChange() {
    if (_isVisible && mounted) {
      _startHideTimer();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() {
          _isVisible = false;
        });
        widget.onVisibilityChanged?.call(false);
      }
    });
  }

  void onUserInteraction() {
    if (!_isVisible) {
      setState(() => _isVisible = true);
      widget.onVisibilityChanged?.call(true);
    }
    _startHideTimer();
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    setState(() => _isVisible = true);
    widget.onVisibilityChanged?.call(true);
  }

  void _togglePlay() {
    widget.player.playOrPause();
  }

  void _seekRelative(Duration amount) {
    final newPos = _position + amount;
    widget.player.seek(newPos);
    _startHideTimer();
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _isVisible = true;
    });
    if (!_isLocked) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  // Keyboard shortcut handlers
  void toggleMute() {
    final currentVol = widget.player.state.volume;
    if (currentVol > 0) {
      widget.player.setVolume(0);
      _showToast("Mute", Icons.volume_off);
    } else {
      widget.player.setVolume(100);
      changeVolume(0); // Trigger OSD update
    }
  }

  Future<void> changeVolume(double step) async {
    double current = (await FlutterVolumeController.getVolume()) ?? 0.5;

    // Volume boost logic
    if (step > 0) {
      if (current >= 1.0) {
        // Increase boost beyond 100%
        _boostLevel = (_boostLevel + step * 2).clamp(1.0, 2.0);
        widget.player.setVolume(_boostLevel * 100);
      } else {
        // Adjust system volume
        _boostLevel = 1.0;
        widget.player.setVolume(100);
        await FlutterVolumeController.setVolume(
          (current + step).clamp(0.0, 1.0),
        );
      }
    } else {
      if (_boostLevel > 1.0) {
        // Decrease boost
        _boostLevel = (_boostLevel + step * 2).clamp(1.0, 2.0);
        widget.player.setVolume(_boostLevel * 100);
      } else {
        // Decrease system volume
        await FlutterVolumeController.setVolume(
          (current + step).clamp(0.0, 1.0),
        );
      }
    }

    // Refresh current for OSD
    current = (await FlutterVolumeController.getVolume()) ?? 0.5;

    if (mounted) {
      if (_isVisible) {
        setState(() => _isVisible = false);
        widget.onVisibilityChanged?.call(false);
      }
      setState(() {
        _showOSD = true;
        _osdIcon = _getIconForValue(PlayerGesture.volume, current);

        // If boosted, show boost level
        if (_boostLevel > 1.0) {
          _osdValue = _boostLevel;
          _osdLabel = "Volume ${(_boostLevel * 100).toInt()}%";
        } else {
          _osdValue = current;
          _osdLabel = "Volume ${(current * 100).toInt()}%";
        }
      });
      _osdTimer?.cancel();
      _osdTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _showOSD = false);
      });
    }
  }

  void triggerSeek(bool isLeft) {
    final width = MediaQuery.of(context).size.width;
    final settings = ref.read(playerSettingsProvider);
    final seconds = settings.seekDuration;

    setState(() {
      _isSeekingLeft = isLeft;
      // Set tap position for animation to appear on correct side
      _tapPosition = Offset(isLeft ? width * 0.25 : width * 0.75, 100);
    });
    _seekAnimController.forward(from: 0.0);

    _seekRelative(Duration(seconds: isLeft ? -seconds : seconds));
  }

  void cycleResize() {
    setState(() {
      _resizeMode = (_resizeMode + 1) % 3;

      final modes = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
      final labels = ["Fit", "Zoom", "Stretch"];

      widget.onResize?.call(modes[_resizeMode]);
      _showToast(labels[_resizeMode], Icons.aspect_ratio);
    });
  }

  void _showToast(String message, IconData icon) {
    _hideTimer?.cancel();
    setState(() {
      _showOSD = true;
      _osdIcon = icon;
      _osdLabel = message;
      _osdValue = null;
      _osdAlignment = Alignment.bottomCenter;
    });

    _osdTimer?.cancel();
    _osdTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showOSD = false);
    });
  }

  void _showSourceSelection() {
    if (widget.streams == null || widget.streams!.isEmpty) return;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Select Source",
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Divider(color: theme.dividerColor),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.streams!.length,
                  itemBuilder: (ctx, index) {
                    final s = widget.streams![index];
                    final isSelected = s == widget.currentStream;
                    return ListTile(
                      leading: Icon(
                        Icons.high_quality,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.iconTheme.color,
                      ),
                      title: Text(
                        s.quality,
                        style: TextStyle(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onStreamSelected?.call(s);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return "${d.toStringAsFixed(1)} ${suffixes[i]}";
  }

  void _showContentSelection() {
    if (widget.torrentStatus == null) return;
    final files = widget.torrentStatus!.data['file_stats'] as List<dynamic>?;
    if (files == null || files.isEmpty) return;

    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "Torrent Content",
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(color: theme.dividerColor, height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: files.length,
                    itemBuilder: (ctx, index) {
                      final file = files[index];
                      final path = file['path'] as String? ?? "Unknown";
                      final length = file['length'] as int? ?? 0;
                      final id =
                          file['id'] as int? ??
                          (index + 1); // Fallback if id missing

                      // Simple check if this looks like a video
                      final isVideo =
                          path.toLowerCase().endsWith(".mp4") ||
                          path.toLowerCase().endsWith(".mkv") ||
                          path.toLowerCase().endsWith(".avi") ||
                          path.toLowerCase().endsWith(".mov");

                      return ListTile(
                        leading: Icon(
                          isVideo
                              ? Icons.movie_creation_outlined
                              : Icons.insert_drive_file_outlined,
                          color: isVideo
                              ? theme.colorScheme.primary
                              : theme.iconTheme.color,
                        ),
                        title: Text(
                          path.split('/').last, // Show filename only
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        subtitle: Text(
                          _formatBytes(length),
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          // Only allow switching to video files or let user try any file
                          widget.onTorrentFileSelected?.call(id);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTracksSelection() {
    final audioTracks = widget.player.state.tracks.audio;
    final subTracks = widget.player.state.tracks.subtitle;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  "Audio Tracks",
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Divider(color: theme.dividerColor),
                ...audioTracks.map((e) {
                  final langName = _getLanguageName(e.language ?? e.id);
                  final label = e.title != null
                      ? "$langName (${e.title})"
                      : langName;
                  final isSelected = e == widget.player.state.track.audio;

                  return ListTile(
                    title: Text(
                      label,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    onTap: () {
                      widget.player.setAudioTrack(e);
                      Navigator.pop(ctx);
                    },
                    selected: isSelected,
                    selectedColor: theme.colorScheme.primary,
                    trailing: isSelected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                  );
                }),
                if (audioTracks.isEmpty)
                  Text(
                    "No audio tracks found",
                    style: TextStyle(color: theme.textTheme.bodySmall?.color),
                  ),

                const SizedBox(height: 24),
                Text(
                  "Subtitles",
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Divider(color: theme.dividerColor),
                ListTile(
                  title: Text(
                    "Off",
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  onTap: () {
                    widget.player.setSubtitleTrack(SubtitleTrack.no());
                    Navigator.pop(ctx);
                  },
                  selected:
                      widget.player.state.track.subtitle == SubtitleTrack.no(),
                  trailing:
                      widget.player.state.track.subtitle == SubtitleTrack.no()
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                ),
                // External Subtitles
                if (widget.externalSubtitles != null)
                  ...widget.externalSubtitles!.map((s) {
                    final uriTrack = SubtitleTrack.uri(
                      s.url,
                      title: s.label,
                      language: s.lang,
                    );
                    // Check selection by ID (url) or loose match
                    final isSelected =
                        widget.player.state.track.subtitle.id == s.url ||
                        widget.player.state.track.subtitle.title == s.label;

                    return ListTile(
                      title: Text(
                        s.label,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      subtitle: s.lang != null
                          ? Text(
                              _getLanguageName(s.lang!),
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 10,
                              ),
                            )
                          : null,
                      onTap: () {
                        widget.player.setSubtitleTrack(uriTrack);
                        Navigator.pop(ctx);
                      },
                      selected: isSelected,
                      selectedColor: theme.colorScheme.primary,
                      trailing: isSelected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                    );
                  }),

                // Embedded Subtitles
                ...subTracks.map((e) {
                  final langName = _getLanguageName(e.language ?? e.id);
                  final label = e.title != null
                      ? "$langName (${e.title})"
                      : langName;
                  final isSelected = e == widget.player.state.track.subtitle;

                  return ListTile(
                    title: Text(
                      label,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    onTap: () {
                      widget.player.setSubtitleTrack(e);
                      Navigator.pop(ctx);
                    },
                    selected: isSelected,
                    selectedColor: theme.colorScheme.primary,
                    trailing: isSelected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  // ... (keeping other methods same)

  Future<void> _handleDragStart(DragStartDetails details) async {
    _animDuration = Duration.zero;
    if (_isVisible) {
      _cancelHideTimer();
      setState(() => _isVisible = false);
      widget.onVisibilityChanged?.call(false);
    }

    final width = MediaQuery.of(context).size.width;

    // Disable vertical gestures on Desktop and TV
    final profile = ref.read(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv ?? false;
    try {
      if (isTv || Platform.isMacOS || Platform.isWindows || Platform.isLinux)
        return;
    } catch (_) {}

    final x = details.globalPosition.dx;
    final settings = ref.read(playerSettingsProvider);

    PlayerGesture type = PlayerGesture.none;
    if (x < width / 2) {
      type = settings.leftGesture;
      _osdAlignment = Alignment.centerRight; // Opposite side
    } else {
      type = settings.rightGesture;
      _osdAlignment = Alignment.centerLeft; // Opposite side
    }

    if (type == PlayerGesture.none) return;

    _currentGesture = type;

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

    if (mounted) {
      if (_isVisible) {
        setState(() => _isVisible = false);
        widget.onVisibilityChanged?.call(false);
      }
      setState(() {
        _showOSD = true;
        _osdIcon = _getIconForValue(type, startVal);
        _osdValue = startVal;
        _osdLabel = type == PlayerGesture.brightness ? "Brightness" : "Volume";
      });
    }
    _osdTimer?.cancel();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_currentGesture == null || _currentGesture == PlayerGesture.none) {
      return;
    }

    final delta = -details.primaryDelta! / 300;

    // Auto brightness threshold (-0.05)
    double min = (_currentGesture == PlayerGesture.brightness) ? -0.05 : 0.0;
    // Volume boost limit (200%)
    double max = (_currentGesture == PlayerGesture.brightness) ? 1.0 : 2.0;

    double newVal = ((_osdValue ?? 0.0) + delta).clamp(min, max);

    // Update icon state
    final newIcon = _getIconForValue(_currentGesture!, newVal);

    setState(() {
      _osdValue = newVal;
      _osdIcon = newIcon;
    });

    if (_currentGesture == PlayerGesture.brightness) {
      if (newVal <= 0.0) {
        ScreenBrightness().resetApplicationScreenBrightness();
        setState(() => _osdLabel = "Auto");
      } else {
        ScreenBrightness().setApplicationScreenBrightness(newVal);
        setState(() => _osdLabel = "Brightness");
      }
    } else {
      // Handle volume boost
      if (newVal > 1.0) {
        _boostLevel = newVal;
        widget.player.setVolume(newVal * 100);
      } else {
        _boostLevel = 1.0;
        widget.player.setVolume(100);
        FlutterVolumeController.setVolume(newVal);
      }
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    _currentGesture = null;
    _osdTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showOSD = false);
    });
  }

  // Horizontal Seek
  void _handleHorizontalDragStart(DragStartDetails details) {
    if (widget.isLoading || _duration == Duration.zero) return;
    if (_isLocked) return;

    // Check settings
    if (!ref.read(playerSettingsProvider).swipeSeekEnabled) return;

    // Disable touch gestures on desktop and TV
    final profile = ref.read(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv ?? false;
    try {
      if (isTv || Platform.isMacOS || Platform.isWindows || Platform.isLinux)
        return;
    } catch (_) {}

    // Avoid conflict with seek bar
    if (_isVisible) {
      final height = MediaQuery.of(context).size.height;
      final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
      if (details.globalPosition.dy > (height - 100 - bottomPadding)) {
        return;
      }

      // Hide controls when starting swipe seek
      _cancelHideTimer();
      setState(() => _isVisible = false);
      widget.onVisibilityChanged?.call(false);
    }

    setState(() {
      _swipeSeekValue = _position;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_swipeSeekValue == null) return;

    final delta = details.primaryDelta ?? 0;
    final newMs = (_swipeSeekValue!.inMilliseconds + (delta * 200)).toInt();
    final clamped = newMs.clamp(0, _duration.inMilliseconds);

    setState(() {
      _swipeSeekValue = Duration(milliseconds: clamped);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_swipeSeekValue == null) return;
    widget.player.seek(_swipeSeekValue!);
    setState(() {
      _swipeSeekValue = null;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return "$hours:${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
    return "$minutes:${twoDigits(seconds)}";
  }

  Widget _buildKickAnimation() {
    final settings = ref.read(playerSettingsProvider);
    final int seconds = settings.seekDuration;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _seekAnimController,
          curve: Curves.fastOutSlowIn,
        ),
      ),
      child: Container(
        height: double.infinity,
        width:
            MediaQuery.of(context).size.height * 0.5, // Half-circle proportion
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: Colors.transparent, // Slightly lighter for full screen
          borderRadius: BorderRadius.only(
            topRight: _isSeekingLeft
                ? Radius.circular(MediaQuery.of(context).size.height)
                : Radius.zero,
            bottomRight: _isSeekingLeft
                ? Radius.circular(MediaQuery.of(context).size.height)
                : Radius.zero,
            topLeft: !_isSeekingLeft
                ? Radius.circular(MediaQuery.of(context).size.height)
                : Radius.zero,
            bottomLeft: !_isSeekingLeft
                ? Radius.circular(MediaQuery.of(context).size.height)
                : Radius.zero,
          ),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.2).animate(
            CurvedAnimation(
              parent: _seekAnimController,
              curve: Curves.elasticOut,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isSeekingLeft ? Icons.fast_rewind : Icons.fast_forward,
                color: Colors.white,
                size: 64, // Larger icon
              ),
              const SizedBox(height: 12),
              Text(
                "${seconds}s",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20, // Larger text
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Guard against PiP or small window size
    final size = MediaQuery.of(context).size;
    final isSmallWindow = size.width < 300 || size.height < 200;

    if (_isInPip || isSmallWindow) return const SizedBox.shrink();

    // Loading state: simplified UI
    if (widget.isLoading || _duration == Duration.zero) {
      if (!widget.forceShowControls) {
        return _buildLoadingUI();
      }
    }

    return MouseRegion(
      cursor: _isVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
      onEnter: (_) {
        // Always show cursor when mouse enters the player area
        if (!_isVisible) {
          setState(() => _isVisible = true);
          widget.onVisibilityChanged?.call(true);
        }
        _startHideTimer();
      },
      onHover: (_) {
        if (!_isVisible) {
          setState(() => _isVisible = true);
          widget.onVisibilityChanged?.call(true);
        }
        _startHideTimer();
      },
      onExit: (_) {
        // When mouse leaves, ensure cursor will be visible when it returns
        // Cancel hide timer to prevent cursor hiding while mouse is outside
        _hideTimer?.cancel();
      },
      child: GestureDetector(
        onVerticalDragStart: _handleDragStart,
        onVerticalDragUpdate: _handleDragUpdate,
        onVerticalDragEnd: _handleDragEnd,
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        onDoubleTapDown: (d) => _tapPosition = d.globalPosition,
        onDoubleTap: _handleDoubleTap,
        child: GestureDetector(
          onTap: () {
            if (_showOSD) {
              setState(() => _showOSD = false);
            }
            if (_isLocked) {
              setState(() => _isVisible = !_isVisible);
              widget.onVisibilityChanged?.call(_isVisible);
            } else {
              _toggleVisibility();
            }
          },
          behavior: HitTestBehavior.translucent,
          child: Container(
            color: _isVisible ? Colors.black54 : Colors.transparent,
            child: Stack(
              children: [
                // Locked state UI
                if (_isLocked) _buildLockedUI() else _buildUnlockedUI(),

                // Persistent buffering indicator
                if (!_isLocked && (_isBuffering || widget.isLoading))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: !_isVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(16),
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (_seekAnimController.isAnimating)
                  Positioned.fill(
                    child: Align(
                      alignment: _isSeekingLeft
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: _buildKickAnimation(),
                    ),
                  ),

                // Seek feedback overlay
                if (_swipeSeekValue != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "${_formatDuration(_swipeSeekValue!)} / ${_formatDuration(_duration)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Volume/Brightness OSD
                if (_showOSD)
                  if (Platform.isMacOS ||
                      Platform.isWindows ||
                      Platform.isLinux)
                    _buildDesktopHorizontalOSD()
                  else
                    Align(
                      alignment: _osdAlignment,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        child: _osdValue == null
                            ? Container(
                                // TOAST MODE
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _osdIcon,
                                      color: ((_osdValue ?? 0) > 1.0)
                                          ? Colors.orange
                                          : Colors.white,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _osdLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                // VERTICAL BAR MODE
                                width: 58,
                                height: 240,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _osdLabel == "Auto"
                                          ? "Auto"
                                          : "${((_osdValue ?? 0) * 100).toInt()}",
                                      style: TextStyle(
                                        color: ((_osdValue ?? 0) > 1.0)
                                            ? Colors.orange
                                            : Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: SizedBox(
                                        width: 12,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Stack(
                                            alignment: Alignment.bottomCenter,
                                            children: [
                                              // Background
                                              Container(
                                                color: Colors.grey.withValues(
                                                  alpha: 0.5,
                                                ),
                                              ),
                                              // White Bar
                                              LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final bool isBrightness =
                                                      _osdLabel ==
                                                          "Brightness" ||
                                                      _osdLabel == "Auto";
                                                  // Brightness 0-1 maps to 1.0 height
                                                  // Volume 0-2 maps to 0.5 * Val height
                                                  final double val =
                                                      (_osdValue ?? 0).clamp(
                                                        0.0,
                                                        1.0,
                                                      );
                                                  final double scale =
                                                      isBrightness ? 1.0 : 0.5;

                                                  return Align(
                                                    alignment:
                                                        Alignment.bottomCenter,
                                                    child: FractionallySizedBox(
                                                      heightFactor: val * scale,
                                                      child: Container(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                              // Orange Bar (Volume Boost only)
                                              if ((_osdValue ?? 0) > 1.0 &&
                                                  !(_osdLabel == "Brightness" ||
                                                      _osdLabel == "Auto"))
                                                LayoutBuilder(
                                                  builder: (ctx, constraints) {
                                                    final double boost =
                                                        (_osdValue! - 1.0)
                                                            .clamp(0.0, 1.0);
                                                    // Boost percentage determines height of orange bar (max 50% of total)
                                                    final double orangeHeight =
                                                        constraints.maxHeight *
                                                        (boost * 0.5);
                                                    final double bottomOffset =
                                                        constraints.maxHeight *
                                                        0.5;

                                                    return Align(
                                                      alignment: Alignment
                                                          .bottomCenter,
                                                      child: Container(
                                                        width: double.infinity,
                                                        height: orangeHeight,
                                                        margin: EdgeInsets.only(
                                                          bottom: bottomOffset,
                                                        ),
                                                        color: Colors.orange,
                                                      ),
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      transitionBuilder: (child, anim) =>
                                          ScaleTransition(
                                            scale: anim,
                                            child: child,
                                          ),
                                      child: Icon(
                                        _osdIcon,
                                        key: ValueKey(_osdIcon),
                                        color: ((_osdValue ?? 0) > 1.0)
                                            ? Colors.orange
                                            : Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHorizontalOSD() {
    final bool isLevel = _osdValue != null;
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _osdIcon,
                color: ((_osdValue ?? 0) > 1.0) ? Colors.orange : Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              if (!isLevel)
                Expanded(
                  child: Center(
                    child: Text(
                      _osdLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        children: [
                          // Background
                          Container(color: Colors.grey.withValues(alpha: 0.5)),
                          // White Bar
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final bool isBrightness =
                                  _osdLabel == "Brightness" ||
                                  _osdLabel == "Auto";
                              final double val = (_osdValue ?? 0).clamp(
                                0.0,
                                1.0,
                              );
                              final double scale = isBrightness ? 1.0 : 0.5;
                              return FractionallySizedBox(
                                widthFactor: val * scale,
                                child: Container(color: Colors.white),
                              );
                            },
                          ),
                          // Boost indicator
                          if ((_osdValue ?? 0) > 1.0)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final double boost = (_osdValue! - 1.0).clamp(
                                  0.0,
                                  1.0,
                                );
                                // Boost fills remaining space
                                final double width =
                                    constraints.maxWidth * (boost * 0.5);
                                final double leftOffset =
                                    constraints.maxWidth * 0.5;
                                return Container(
                                  margin: EdgeInsets.only(left: leftOffset),
                                  width: width,
                                  color: Colors.orange,
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40, // Fixed width for stable layout
                  child: Text(
                    "${((_osdValue! * 100).toInt())}%",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: ((_osdValue ?? 0) > 1.0)
                          ? Colors.orange
                          : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool rotate = false,
    bool highlight = false,
  }) {
    return TvButton(
      showFocusHighlight: _isTv,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: highlight ? Theme.of(context).primaryColor : Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForValue(PlayerGesture type, double value) {
    if (type == PlayerGesture.brightness) {
      if (value <= 0.0) return Icons.brightness_auto;
      if (value < 0.3) return Icons.brightness_low;
      if (value < 0.7) return Icons.brightness_medium;
      return Icons.brightness_high;
    } else {
      if (value <= 0.0) return Icons.volume_off;
      if (value < 0.33) return Icons.volume_mute;
      if (value < 0.66) return Icons.volume_down;
      return Icons.volume_up;
    }
  }

  Widget _buildLockedUI() {
    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Center(
        child: _buildActionButton(
          icon: Icons.lock,
          label: "Unlock",
          onTap: _toggleLock,
          rotate: false,
          highlight: false,
        ),
      ),
    );
  }

  Widget _buildUnlockedUI() {
    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: _animDuration,
      child: IgnorePointer(
        ignoring: !_isVisible,
        child: Stack(
          children: [
            // Top overlay (back button, title)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {},
                onDoubleTap: () {},
                onHorizontalDragStart: (_) {},
                onVerticalDragStart: (_) {},
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).viewPadding.top + 16,
                    left: 16,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      TvButton(
                        showFocusHighlight: _isTv,
                        focusNode: _backFocusNode,
                        onPressed:
                            widget.onBackPointer ??
                            () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.subtitle != null)
                              Text(
                                widget.subtitle!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 4),
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),

            // Torrent Info Overlay
            if (widget.torrentStatus != null && _showTorrentInfo)
              Positioned(
                top: 80,
                right: 20, // Changed from left: 20
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: TorrentInfoWidget(status: widget.torrentStatus),
                ),
              ),

            // Playback controls
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Seek Backward
                  TvButton(
                    showFocusHighlight: _isTv,
                    onPressed: () =>
                        _seekRelative(const Duration(seconds: -10)),
                    child: const Icon(
                      Icons.replay_10,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 48),
                  // Play/Pause Toggle
                  TvButton(
                    showFocusHighlight: _isTv,
                    autofocus: true,
                    focusNode: _playFocusNode,
                    onPressed: _togglePlay,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black45, // Slight circle bg
                        shape: BoxShape.circle,
                      ),
                      child: (_isBuffering || widget.isLoading)
                          ? const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 64,
                            ),
                    ),
                  ),
                  const SizedBox(width: 48),
                  // Seek Forward
                  TvButton(
                    showFocusHighlight: _isTv,
                    onPressed: () => _seekRelative(const Duration(seconds: 10)),
                    child: const Icon(
                      Icons.forward_10,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom overlay (slider, actions)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {},
                onDoubleTap: () {},
                onHorizontalDragStart: (_) {},
                onVerticalDragStart: (_) {},
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewPadding.bottom + 16,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Time / Slider / Duration
                      Row(
                        children: [
                          const SizedBox(width: 12),
                          SizedBox(
                            width: _duration.inHours > 0 ? 65 : 45,
                            child: Text(
                              _formatDuration(
                                _dragValue != null
                                    ? Duration(
                                        milliseconds: _dragValue!.toInt(),
                                      )
                                    : _position,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.grey,
                                trackShape: const RoundedRectSliderTrackShape(),
                                thumbColor: Colors.white,
                                overlayColor: Colors.white.withOpacity(0.2),
                              ),
                              child: TvSlider(
                                value:
                                    (_dragValue ??
                                            _position.inMilliseconds.toDouble())
                                        .clamp(
                                          0,
                                          _duration.inMilliseconds.toDouble(),
                                        ),
                                min: 0.0,
                                max: _duration.inMilliseconds.toDouble(),
                                step: 5000, // 5 seconds step
                                onChanged: (val) {
                                  _cancelHideTimer();
                                  widget.player.seek(
                                    Duration(milliseconds: val.toInt()),
                                  );
                                },
                              ),
                            ),
                          ),

                          SizedBox(
                            width: _duration.inHours > 0 ? 65 : 45,
                            child: Text(
                              _formatDuration(_duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                              textAlign: TextAlign.left,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Actions Row
                      FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    if (widget.torrentStatus != null)
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(1),
                                        child: _buildActionButton(
                                          icon: Icons.info_outline,
                                          label: "Info",
                                          onTap: () {
                                            setState(
                                              () => _showTorrentInfo =
                                                  !_showTorrentInfo,
                                            );
                                          },
                                        ),
                                      ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(2),
                                      child: _buildActionButton(
                                        icon: Icons.lock_open,
                                        label: "Lock",
                                        onTap: _toggleLock,
                                      ),
                                    ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(3),
                                      child: _buildActionButton(
                                        icon: Icons.aspect_ratio,
                                        label: "Resize",
                                        onTap: cycleResize,
                                      ),
                                    ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(4),
                                      child: _buildActionButton(
                                        icon: Icons.playlist_play,
                                        label: "Source",
                                        onTap: _showSourceSelection,
                                      ),
                                    ),
                                    if (_hasMultipleVideoFiles())
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(5),
                                        child: _buildActionButton(
                                          icon: Icons.folder_open,
                                          label: "Content",
                                          onTap: _showContentSelection,
                                        ),
                                      ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(6),
                                      child: _buildActionButton(
                                        icon: Icons.subtitles,
                                        label: "Tracks",
                                        onTap: _showTracksSelection,
                                      ),
                                    ),
                                    if (Platform.isAndroid &&
                                        !Platform.isIOS &&
                                        !(ref
                                                .read(deviceProfileProvider)
                                                .asData
                                                ?.value
                                                .isTv ??
                                            false))
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(7),
                                        child: _buildActionButton(
                                          icon: Icons.picture_in_picture_alt,
                                          label: "PIP",
                                          onTap: _enterPip,
                                        ),
                                      ),
                                    if ((Platform.isAndroid ||
                                            (Platform.isIOS && !_isIpad)) &&
                                        !(ref
                                                .read(deviceProfileProvider)
                                                .asData
                                                ?.value
                                                .isTv ??
                                            false))
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(8),
                                        child: _buildActionButton(
                                          icon: Icons.screen_rotation,
                                          label: "Rotate",
                                          onTap: _toggleOrientation,
                                        ),
                                      ),
                                    if (Platform.isMacOS ||
                                        Platform.isWindows ||
                                        Platform.isLinux)
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(9),
                                        child: _buildActionButton(
                                          icon: _isFullscreen
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                          label: _isFullscreen
                                              ? "Windowed"
                                              : "Fullscreen",
                                          onTap: toggleFullscreen,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasMultipleVideoFiles() {
    if (widget.torrentStatus == null) return false;
    final files = widget.torrentStatus!.data['file_stats'] as List<dynamic>?;
    if (files == null) return false;

    int count = 0;
    for (var f in files) {
      final path = (f['path'] as String? ?? "").toLowerCase();
      if (path.endsWith(".mp4") ||
          path.endsWith(".mkv") ||
          path.endsWith(".avi") ||
          path.endsWith(".mov")) {
        count++;
      }
    }
    return count > 1;
  }

  Widget _buildLoadingUI() {
    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: Container(
        color: Colors.transparent, // Ensure hit test works
        child: Stack(
          children: [
            Positioned(
              top: MediaQuery.of(context).viewPadding.top + 16,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 36,
                  ),
                  tooltip: 'Go Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

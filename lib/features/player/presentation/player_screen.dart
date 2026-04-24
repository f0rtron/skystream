import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_view/video_view.dart' as vv;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../features/settings/presentation/player_settings_provider.dart';
import 'widgets/skystream_player_controls.dart';
import 'player_controller.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final String videoUrl;
  final Episode? episode;

  const PlayerScreen({
    super.key,
    required this.item,
    required this.videoUrl,
    this.episode,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController; // media_kit renderer
  late final vv.VideoController
  _videoViewController; // video_view (ExoPlayer/AVPlayer)

  final ValueNotifier<BoxFit> _videoFit = ValueNotifier(BoxFit.contain);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);

  final GlobalKey<SkyStreamPlayerControlsState> _controlsKeyFinal = GlobalKey();

  bool _isTv = false;
  bool _isTablet = false;
  bool _wasPlayingBeforeBackground = false;

  late final PlayerController _playerController;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);

    final deviceProfile = ref.read(deviceProfileProvider).asData?.value;
    _isTv = deviceProfile?.isTv ?? false;
    _isTablet = deviceProfile?.isTablet ?? false;

    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    WakelockPlus.enable();

    // Initialize player with larger buffer for torrent streaming
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024, // 128MB
      ),
    );

    // Increase network timeout to allow TorrServer to pre-buffer
    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      native.setProperty('network-timeout', '120');
      native.setProperty('force-seekable', 'yes');
      // Increase metadata probing depth to match VLC (resolves missing language tags)
      native.setProperty('demuxer-lavf-probesize', '33554432'); // 32MB
      native.setProperty('demuxer-lavf-analyzeduration', '20'); // 20s
    }
    _videoController = VideoController(_player);

    // Phase 8: Initialize video_view engine (ExoPlayer on Android, AVPlayer on iOS/macOS)
    _videoViewController = vv.VideoController(autoPlay: true);

    ref.listenManual<AsyncValue<PlayerSettings>>(playerSettingsProvider, (
      _,
      next,
    ) {
      final settings = next.asData?.value;
      if (settings == null) return;
      if (settings.defaultResizeMode == "Zoom") {
        _videoFit.value = BoxFit.cover;
      } else if (settings.defaultResizeMode == "Stretch") {
        _videoFit.value = BoxFit.fill;
      }
    }, fireImmediately: true);

    _playerController = ref.read(playerControllerProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playerController.init(
        player: _player,
        item: widget.item,
        videoUrl: widget.videoUrl,
        episode: widget.episode,
        videoViewController: _videoViewController,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final ctrl = ref.read(playerControllerProvider);
      _wasPlayingBeforeBackground = ctrl.useExoPlayer
          ? _videoViewController.playbackState.value ==
                vv.VideoControllerPlaybackState.playing
          : _player.state.playing;
      _playerController.saveProgress();
      _playerController.pause();
    } else if (state == AppLifecycleState.resumed) {
      // Re-acquire wakelock — the OS may release it while the app is paused.
      WakelockPlus.enable();
      if (_wasPlayingBeforeBackground) {
        _wasPlayingBeforeBackground = false;
        _playerController.play();
      }
    }
  }

  void _updateResizeMode(BoxFit mode) {
    if (mounted) _videoFit.value = mode;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerController.disposeController();

    _player.dispose();
    _videoViewController.dispose();
    _controlsVisible.dispose();
    _videoFit.dispose();

    WakelockPlus.disable();
    if (Platform.isAndroid || Platform.isIOS) {
      // Always restore system UI mode — immersiveSticky is set for all Android
      // (including TV/FireTV) in initState, so it must always be cleared here.
      // On FireTV, leaving immersiveSticky active after the player is popped
      // causes the system to suppress hardware back-button key events.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (!_isTv) {
        if (_isTablet) {
          SystemChrome.setPreferredOrientations([]);
        } else {
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        }
      }
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        windowManager.setFullScreen(false);
        if (Platform.isWindows || Platform.isLinux) {
          windowManager.setTitleBarStyle(TitleBarStyle.normal);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PlayerScreen.dispose: $e');
      }
    }
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // Only handle KeyDown and KeyRepeat for volume/seeking
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    // TV Navigation Logic
    if (_isTv) {
      if (_controlsVisible.value) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
      } else {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _controlsKeyFinal.currentState?.showControls();
          return KeyEventResult.handled;
        }
      }
    }

    // Intercept standard playback keys
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      _controlsKeyFinal.currentState?.togglePlayPause();
      if (!_controlsVisible.value) {
        _controlsKeyFinal.currentState?.showControls();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      _controlsKeyFinal.currentState?.toggleMute();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      _controlsKeyFinal.currentState?.cycleResize();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _controlsKeyFinal.currentState?.toggleFullscreen();
      return KeyEventResult.handled;
    }

    if (!_isTv) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _controlsKeyFinal.currentState?.changeVolume(0.05);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _controlsKeyFinal.currentState?.changeVolume(-0.05);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _controlsKeyFinal.currentState?.triggerSeek(true);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _controlsKeyFinal.currentState?.triggerSeek(false);
      return KeyEventResult.handled;
    }

    if (_controlsVisible.value &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _handleBack() async {
    if (!context.mounted) return;

    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        await windowManager.setFullScreen(false);
        await Future<void>.delayed(const Duration(seconds: 1));
      } catch (e) {
        if (kDebugMode) debugPrint('PlayerScreen._handleBack: $e');
      }
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = ref.watch(
      playerControllerProvider.select((s) => s.errorMessage),
    );
    final isLoading = ref.watch(
      playerControllerProvider.select((s) => s.isLoading),
    );
    final subtitleSettings = ref.watch(playerSettingsProvider).asData?.value;

    if (errorMessage != null) {
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.playbackError,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        errorMessage,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        autofocus: true,
                        onPressed: _handleBack,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(AppLocalizations.of(context)!.goBack),
                      ),
                    ],
                  ),
                ),
              ),
              // Top-left back button — always visible for iOS/desktop
              // where there may be no system back gesture.
              Positioned(
                top: 8,
                left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: AppLocalizations.of(context)!.goBack,
                    onPressed: _handleBack,
                  ),
              ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _controlsVisible,
      builder: (context, controlsVisible, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            // On TV: intercept back to hide controls first (if controls are
            // visible and video is playing), so the user doesn't exit by accident.
            // On phone/tablet: always pop directly — no two-step back.
            if (_isTv && _controlsVisible.value) {
              final isPlaying = ref.read(
                playerControllerProvider.select((s) => s.useExoPlayer),
              )
                  ? _videoViewController.playbackState.value ==
                        vv.VideoControllerPlaybackState.playing
                  : _player.state.playing;
              if (isPlaying) {
                _controlsKeyFinal.currentState?.hideControls();
                return;
              }
            }
            await _handleBack();
          },
          child: Scaffold(
            body: Focus(
              autofocus: true,
              onKeyEvent: _handleKey,
              child: Stack(
                children: [
                  RepaintBoundary(
                    child: ValueListenableBuilder<BoxFit>(
                      valueListenable: _videoFit,
                      builder: (_, fit, child) => Center(
                        // Phase 8: Switch engine based on stream type
                        child: Consumer(
                          builder: (context, ref, _) {
                            final useExoPlayer = ref.watch(
                              playerControllerProvider.select(
                                (s) => s.useExoPlayer,
                              ),
                            );
                            if (useExoPlayer) {
                              return vv.VideoView(
                                controller: _videoViewController,
                                videoFit: fit,
                              );
                            }
                            return Video(
                              controller: _videoController,
                              fit: fit,
                              subtitleViewConfiguration:
                                  const SubtitleViewConfiguration(
                                    visible: false,
                                  ),
                              controls: (state) => const SizedBox.shrink(),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final useExoPlayer = ref.watch(
                        playerControllerProvider.select((s) => s.useExoPlayer),
                      );
                      if (useExoPlayer) {
                        return const SizedBox.shrink();
                      }

                      return Positioned(
                        bottom:
                            (controlsVisible ? 120.0 : 20.0) +
                            ((100 -
                                    (subtitleSettings?.subtitlePosition ??
                                        100.0)) *
                                (MediaQuery.sizeOf(context).height * 0.008)),
                        left: 20,
                        right: 20,
                        child: SubtitleView(
                          controller: _videoController,
                          configuration: SubtitleViewConfiguration(
                            style: TextStyle(
                              fontSize: subtitleSettings?.subtitleSize ?? 22.0,
                              color: Color(
                                subtitleSettings?.subtitleColor ?? 0xFFFFFFFF,
                              ),
                              backgroundColor:
                                  Color(
                                    subtitleSettings?.subtitleBackgroundColor ??
                                        0x00000000,
                                  ).withValues(
                                    alpha:
                                        subtitleSettings
                                            ?.subtitleBackgroundOpacity ??
                                        0.0,
                                  ),
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: SkyStreamPlayerControls(
                        key: _controlsKeyFinal,
                        isLoading: isLoading,
                        player: _player,
                        videoViewController: _videoViewController,
                        title: widget.item.title,
                        subtitle: ref
                            .read(playerControllerProvider)
                            .streamSubtitle,
                        onResize: _updateResizeMode,
                        onBackPointer: _handleBack,
                        onVisibilityChanged: (v) {
                          if (mounted) {
                            _controlsVisible.value = v;
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

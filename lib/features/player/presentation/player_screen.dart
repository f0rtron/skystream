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
  final ValueNotifier<bool> _forceShowControls = ValueNotifier(false);

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
    } else if (state == AppLifecycleState.resumed &&
        _wasPlayingBeforeBackground) {
      _wasPlayingBeforeBackground = false;
      _playerController.play();
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
    _forceShowControls.dispose();
    _videoFit.dispose();

    WakelockPlus.disable();
    if ((Platform.isAndroid || Platform.isIOS) && !_isTv) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (_isTablet) {
        SystemChrome.setPreferredOrientations([]);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

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
          _controlsVisible.value = true;
          _forceShowControls.value = true;
          Future.delayed(
            const Duration(milliseconds: 200),
            () => _forceShowControls.value = false,
          );
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
        _forceShowControls.value = true;
        Future.delayed(
          const Duration(milliseconds: 100),
          () => _forceShowControls.value = false,
        );
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
    if (!mounted) return;

    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        await windowManager.setFullScreen(false);
        // Small delay to allow macOS/Windows to settle layout
        await Future.delayed(const Duration(milliseconds: 150));
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
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text("Go Back"),
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
            if (_controlsVisible.value) {
              _controlsKeyFinal.currentState?.hideControls();
            } else {
              await _handleBack();
            }
          },
          child: Scaffold(
            body: Focus(
              autofocus: false,
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
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _forceShowControls,
                        builder: (_, forceShow, _) => SkyStreamPlayerControls(
                          key: _controlsKeyFinal,
                          isLoading: isLoading,
                          forceShowControls: forceShow,
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

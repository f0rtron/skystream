import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../features/settings/presentation/player_settings_provider.dart';
import '../../../shared/widgets/custom_widgets.dart';
import 'widgets/skystream_player_controls.dart';
import 'player_controller.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final String videoUrl;

  const PlayerScreen({super.key, required this.item, required this.videoUrl});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController;

  final ValueNotifier<BoxFit> _videoFit = ValueNotifier(BoxFit.contain);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  final ValueNotifier<bool> _forceShowControls = ValueNotifier(false);

  final GlobalKey<SkyStreamPlayerControlsState> _controlsKeyFinal = GlobalKey();

  bool _isTv = false;
  bool _isTablet = false;
  late final FocusNode _skipFocusNode;

  late final PlayerController _playerController;

  @override
  void initState() {
    super.initState();
    _skipFocusNode = FocusNode(onKeyEvent: _handleSkipFocusKey);
    MediaKit.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);

    final deviceProfile = ref.read(deviceProfileProvider).asData?.value;
    _isTv = deviceProfile?.isTv ?? false;
    _isTablet = deviceProfile?.isTablet ?? false;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    // Initialize player with larger buffer for torrent streaming
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024, // 128MB
      ),
    );

    // Increase network timeout to allow TorrServer to pre-buffer
    if (_player.platform is NativePlayer) {
      (_player.platform as NativePlayer).setProperty('network-timeout', '100');
    }
    _videoController = VideoController(_player);

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
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _playerController.saveProgress();
    }
  }

  KeyEventResult _handleSkipFocusKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _controlsKeyFinal.currentState?.focusBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _updateResizeMode(BoxFit mode) {
    if (mounted) _videoFit.value = mode;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerController.disposeController();

    _player.dispose();
    _skipFocusNode.dispose();
    _controlsVisible.dispose();
    _forceShowControls.dispose();
    _videoFit.dispose();

    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (_isTv) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else if (_isTablet) {
      // For tablets, allow system default orientation (usually follows sensor)
      // This prevents forcing portrait mode when the user is holding it in landscape
      SystemChrome.setPreferredOrientations([]);
    } else {
      // For phones, typically reset to portrait
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        windowManager.setFullScreen(false);
        if (Platform.isWindows || Platform.isLinux) {
          windowManager.setTitleBarStyle(TitleBarStyle.normal);
        }
      } catch (e) {
        debugPrint('PlayerScreen.dispose: $e');
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
      _player.playOrPause();
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
                onPressed: () => Navigator.pop(context),
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
          canPop: !controlsVisible,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (controlsVisible) {
              _controlsKeyFinal.currentState?.hideControls();
            }
          },
          child: Scaffold(
            body: MouseRegion(
              onHover: (_) {
                if (!_controlsVisible.value) {
                  _controlsVisible.value = true;
                }
                _controlsKeyFinal.currentState?.onUserInteraction();
              },
              child: Focus(
                autofocus: false,
                onKeyEvent: _handleKey,
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: ValueListenableBuilder<BoxFit>(
                        valueListenable: _videoFit,
                        builder: (_, fit, child) => Center(
                          child: Video(
                            controller: _videoController,
                            fit: fit,
                            subtitleViewConfiguration:
                                const SubtitleViewConfiguration(visible: false),
                            controls: (state) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: controlsVisible ? 120 : 20,
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
                            backgroundColor: Color(
                              subtitleSettings?.subtitleBackgroundColor ??
                                  0x00000000,
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
                    ),
                    RepaintBoundary(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _forceShowControls,
                        builder: (_, forceShow, _) => SkyStreamPlayerControls(
                          key: _controlsKeyFinal,
                          isLoading: isLoading,
                          forceShowControls: forceShow,
                          player: _player,
                          title: widget.item.title,
                          subtitle: ref.read(playerControllerProvider).streamSubtitle,
                          // Most properties are now watched internally by controls
                          // to further narrow rebuild scope.
                          onResize: _updateResizeMode,
                          onVisibilityChanged: (v) {
                            if (mounted) {
                              _controlsVisible.value = v;
                            }
                          },
                        ),
                      ),
                    ),
                    if (isLoading)
                      ValueListenableBuilder<bool>(
                        valueListenable: _forceShowControls,
                        builder: (_, forceShow, child) {
                          if (forceShow) return const SizedBox.shrink();
                          return _buildSkipButtonOverlay();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkipButtonOverlay() {
    final isManualSwitch = ref.read(
      playerControllerProvider.select((s) => s.isManualSwitch),
    );
    final streams = ref.read(playerControllerProvider.select((s) => s.streams));
    final currentIndex = ref.read(
      playerControllerProvider.select((s) => s.currentStreamIndex),
    );

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: () {
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
            _controlsKeyFinal.currentState?.toggleFullscreen();
          }
        },
        child: Stack(
          children: [
            Positioned(
              bottom: 160,
              left: 0,
              right: 0,
              child: Center(
                child: isManualSwitch
                    ? const SizedBox.shrink()
                    : CustomButton(
                        isPrimary: false,
                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                        focusNode: _skipFocusNode,
                        autofocus: true,
                        showFocusHighlight: _isTv,
                        onPressed: () => _forceShowControls.value = true,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.skip_next),
                              const SizedBox(width: 8),
                              Text(
                                "Skip to manual source selection (${currentIndex + 1}/${streams.length})",
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

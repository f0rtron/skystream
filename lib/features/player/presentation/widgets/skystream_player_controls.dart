import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../player_controller.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/models/torrent_status.dart';
import '../components/torrent_info_widget.dart';
import '../../../settings/presentation/player_settings_provider.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import 'player_stream_widgets.dart';
import 'player_control_components.dart';
import 'next_episode_overlay.dart';
import 'player_bottom_sheets.dart';
import 'player_loading_overlay.dart';
import 'player_osd_overlay.dart';
import '../player_platform_service.dart';
import '../player_gesture_handler.dart';

class SkyStreamPlayerControls extends ConsumerStatefulWidget {
  final Player player;
  final String? title;
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
    this.title,
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

  bool _showTorrentInfo = false; // Changed from true
  Timer? _hideTimer;
  bool _isLocked = false;

  // Seek animation state
  late AnimationController _seekAnimController;
  bool _isSeekingLeft = false;

  int _resizeMode = 0;

  late bool _isPlaying;
  late bool _isBuffering;
  late Duration _position;
  late Duration _duration;

  final List<StreamSubscription> _subscriptions = [];

  late final PlayerPlatformService _platformService;
  late final PlayerGestureHandler _gestureHandler;
  Offset? _tapPosition;
  Duration _animDuration = const Duration(milliseconds: 300);
  bool _isFullscreen = false;
  late final FocusNode _playFocusNode;

  @override
  void initState() {
    super.initState();
    _isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;

    _platformService = PlayerPlatformService();
    _gestureHandler = PlayerGestureHandler(
      player: widget.player,
      getSettings: () async => await ref.read(playerSettingsProvider.future),
      isTv: _isTv,
      isDesktop: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
      getDuration: () => _duration,
      getPosition: () => _position,
      onInteraction: () {
        if (!_isVisible) {
          setState(() => _isVisible = true);
          widget.onVisibilityChanged?.call(true);
        }
        _startHideTimer();
      },
      onHideControls: () {
        _cancelHideTimer();
        if (_isVisible && mounted) {
          setState(() => _isVisible = false);
          widget.onVisibilityChanged?.call(false);
        }
      },
      onSeekRelative: _seekRelative,
      onDoubleTapAnimationStart: (isLeft, tapPos, seconds) {
        if (mounted) {
          setState(() {
            _isSeekingLeft = isLeft;
            _tapPosition = tapPos;
          });
          _seekAnimController.forward(from: 0.0);
        }
      },
    );

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

    // OPTIMIZATION: Removed setState calls for position/buffering - now using StreamBuilder widgets
    // This reduces rebuilds from 60+/second to only when visibility/lock state changes
    _subscriptions.addAll([
      // Playing state: Only for timer/PiP sync, NOT for UI rebuilds (StreamBuilder handles that)
      widget.player.stream.playing.listen((val) {
        _isPlaying = val; // Update local cache without setState
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
      // Buffering: No setState needed - StreamBuilder in PlayerPlayPauseButton handles UI
      widget.player.stream.buffering.listen((val) {
        _isBuffering = val; // Update local cache for non-UI logic
      }),
      // Position: No setState needed - StreamBuilder in PlayerProgressBar handles UI
      widget.player.stream.position.listen((val) {
        _position = val; // Update local cache for seek calculations
      }),
      // Duration: Only setState when transitioning from zero (to show controls)
      widget.player.stream.duration.listen((val) {
        final oldDuration = _duration;
        _duration = val; // Update local cache
        if (mounted && oldDuration == Duration.zero && val != Duration.zero) {
          setState(() {
            _isVisible = true;
          });
          _startHideTimer();
        }
      }),
      widget.player.stream.width.listen((_) => _updateOrientation()),
      widget.player.stream.height.listen((_) => _updateOrientation()),
    ]);

    _seekAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // No addListener needed — AnimatedBuilder wraps the seek widget directly

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
      } catch (e) {
        debugPrint('SkyStreamPlayerControls._checkIpad: $e');
      }
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _playFocusNode.dispose();
    _backFocusNode.dispose();
    _hideTimer?.cancel();
    _seekAnimController.dispose();
    _gestureHandler.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('Failed to reset brightness: $e');
    }
    try {
      FlutterVolumeController.updateShowSystemUI(true);
    } catch (e) {
      debugPrint('Failed to restore volume UI: $e');
    }
    SystemChrome.setPreferredOrientations([]); // Reset to system default
    super.dispose();
  }

  void _updateOrientation() {
    _platformService.updateOrientation(
      widget.player.state.width,
      widget.player.state.height,
    );
  }

  Future<void> _enterPip() async {
    await _platformService.enterPip(_isPlaying);
  }

  void _toggleOrientation() {
    _platformService.toggleOrientation(context);
  }

  Future<void> toggleFullscreen() async {
    final nowFullscreen = await _platformService.toggleFullscreen();
    if (mounted) {
      setState(() {
        _isFullscreen = nowFullscreen;
      });
    }
  }

  void _handleDoubleTap() async {
    // Desktop Double Tap -> Toggle Fullscreen
    try {
      if (context.isDesktop &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        toggleFullscreen();
        return;
      }
    } catch (e) {
      debugPrint('SkyStreamPlayerControls._handleDoubleTap: $e');
    }

    if (widget.isLoading || _duration == Duration.zero) return;
    if (_tapPosition != null) {
      _gestureHandler.handleDoubleTap(
        _tapPosition!,
        MediaQuery.sizeOf(context).width,
      );
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

  /// Torrent status is passed via widget props from the parent rebuild.
  /// This method is retained for API compatibility but no longer forces a rebuild.
  void updateTorrentStatus(TorrentStatus status) {}

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
    if (!_isVisible) {
      setState(() => _isVisible = true);
      widget.onVisibilityChanged?.call(true);
    }
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
    _gestureHandler.toggleMute();
  }

  Future<void> changeVolume(double step) async {
    await _gestureHandler.changeVolume(step);
  }

  void triggerSeek(bool isLeft) {
    final width = MediaQuery.sizeOf(context).width;
    final settings =
        ref.read(playerSettingsProvider).asData?.value ??
        const PlayerSettings();
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
      _gestureHandler.showToast(labels[_resizeMode], Icons.aspect_ratio);
    });
  }

  Future<void> _handleDragStart(DragStartDetails details) async {
    await _gestureHandler.handleDragStart(
      details,
      MediaQuery.sizeOf(context).width,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _gestureHandler.handleDragUpdate(details);
  }

  void _handleDragEnd(DragEndDetails details) {
    _gestureHandler.handleDragEnd(details);
  }

  // Horizontal Seek
  void _handleHorizontalDragStart(DragStartDetails details) async {
    final height = MediaQuery.sizeOf(context).height;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    await _gestureHandler.handleHorizontalDragStart(
      details,
      _isVisible,
      height,
      bottomPadding,
    );
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _gestureHandler.handleHorizontalDragUpdate(details);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    _gestureHandler.handleHorizontalDragEnd(details);
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
    final seconds =
        ref.watch(playerSettingsProvider).asData?.value.seekDuration ?? 10;

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
            MediaQuery.sizeOf(context).height * 0.5, // Half-circle proportion
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: Colors.transparent, // Slightly lighter for full screen
          borderRadius: BorderRadius.only(
            topRight: _isSeekingLeft
                ? Radius.circular(MediaQuery.sizeOf(context).height)
                : Radius.zero,
            bottomRight: _isSeekingLeft
                ? Radius.circular(MediaQuery.sizeOf(context).height)
                : Radius.zero,
            topLeft: !_isSeekingLeft
                ? Radius.circular(MediaQuery.sizeOf(context).height)
                : Radius.zero,
            bottomLeft: !_isSeekingLeft
                ? Radius.circular(MediaQuery.sizeOf(context).height)
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
    // Watch relevant player state selectively, falling back to props for initial frame
    final controllerTitle = ref.watch(playerControllerProvider.select((s) => s.playerTitle));
    final title = controllerTitle.isEmpty ? (widget.title ?? "") : controllerTitle;
    
    final controllerSubtitle = ref.watch(playerControllerProvider.select((s) => s.streamSubtitle));
    final subtitle = controllerSubtitle ?? widget.subtitle;
    final streams = ref.watch(playerControllerProvider.select((s) => s.streams));
    final currentStream = ref.watch(playerControllerProvider.select((s) => s.currentStream));
    final externalSubtitles = ref.watch(playerControllerProvider.select((s) => s.externalSubtitles));
    final torrentStatus = ref.watch(playerControllerProvider.select((s) => s.torrentStatus));
    final showNextEpOverlay = ref.watch(playerControllerProvider.select((s) => s.showNextEpisodeOverlay));
    final nextEpTitle = ref.watch(playerControllerProvider.select((s) => s.nextEpisodeTitle));

    // Guard against PiP or small window size
    final size = MediaQuery.sizeOf(context);
    final isSmallWindow = size.width < 300 || size.height < 200;

    if (_isInPip || isSmallWindow) return const SizedBox.shrink();

    // Loading state: simplified UI
    if (widget.isLoading || _duration == Duration.zero) {
      if (!widget.forceShowControls) {
        return _buildLoadingUI(title: title, subtitle: subtitle);
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
            if (_gestureHandler.showOSD) {
              _gestureHandler.dismissOSD();
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
                if (_isLocked) 
                  _buildLockedUI() 
                else 
                  _buildUnlockedUI(
                    title: title, 
                    subtitle: subtitle, 
                    torrentStatus: torrentStatus,
                    streams: streams,
                    currentStream: currentStream,
                    externalSubtitles: externalSubtitles,
                  ),

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

                // Seek animation — isolated via AnimatedBuilder
                AnimatedBuilder(
                  animation: _seekAnimController,
                  builder: (context, _) {
                    if (!_seekAnimController.isAnimating) {
                      return const SizedBox.shrink();
                    }
                    return Positioned.fill(
                      child: Align(
                        alignment: _isSeekingLeft
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: _buildKickAnimation(),
                      ),
                    );
                  },
                ),

                // OSD and volume overlay — only this subtree rebuilds on handler changes
                PlayerOSDVolumeOverlay(
                  handler: _gestureHandler,
                  getDuration: () => _duration,
                  formatDuration: _formatDuration,
                ),

                // Next Episode Overlay (Persistent when triggered)
                if (showNextEpOverlay && nextEpTitle != null)
                  NextEpisodeOverlay(
                    nextEpisodeTitle: nextEpTitle,
                    onPlayNext: () => ref.read(playerControllerProvider.notifier).playNextEpisode(),
                    onDismiss: () => ref.read(playerControllerProvider.notifier).dismissNextEpisodeOverlay(),
                  ),
              ],
            ),
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
    return PlayerActionButton(
      icon: icon,
      label: label,
      onTap: onTap,
      highlight: highlight,
      isTv: _isTv,
    );
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

  Widget _buildUnlockedUI({
    required String title,
    String? subtitle,
    TorrentStatus? torrentStatus,
    List<StreamResult>? streams,
    StreamResult? currentStream,
    List<SubtitleFile>? externalSubtitles,
  }) {
    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: _animDuration,
      child: IgnorePointer(
        ignoring: !_isVisible,
        child: Stack(
          children: [
            // Top overlay (back button, title) - Extracted to component
            PlayerTopBar(
              title: title,
              subtitle: subtitle,
              onBack: widget.onBackPointer ?? () => Navigator.of(context).pop(),
              isTv: _isTv,
              backFocusNode: _backFocusNode,
            ),

            // Torrent Info Overlay
            if (torrentStatus != null && _showTorrentInfo)
              Positioned(
                top: 80,
                right: 20,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: TorrentInfoWidget(status: torrentStatus),
                ),
              ),

            // Playback controls - Extracted to component
            PlayerCenterControls(
              player: widget.player,
              isLoading: widget.isLoading,
              isTv: _isTv,
              playFocusNode: _playFocusNode,
              onSeekBackward: () => _seekRelative(const Duration(seconds: -10)),
              onSeekForward: () => _seekRelative(const Duration(seconds: 10)),
              onPlayPause: _togglePlay,
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
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress bar with StreamBuilder
                      PlayerProgressBar(player: widget.player, onSeekStart: _cancelHideTimer),
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
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(0),
                                      child: _buildActionButton(
                                        icon: _isLocked ? Icons.lock : Icons.lock_open,
                                        label: _isLocked ? "Unlock" : "Lock",
                                        onTap: _toggleLock,
                                        highlight: _isLocked,
                                      ),
                                    ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(1),
                                      child: _buildActionButton(
                                        icon: Icons.high_quality,
                                        label: "Sources",
                                        onTap: () => PlayerBottomSheets.showSourceSelection(
                                          context: context,
                                          streams: streams,
                                          currentStream: currentStream,
                                          onStreamSelected: (s) => ref.read(playerControllerProvider.notifier).changeStream(s),
                                        ),
                                      ),
                                    ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(2),
                                      child: _buildActionButton(
                                        icon: Icons.subtitles,
                                        label: "Tracks",
                                        onTap: () => PlayerBottomSheets.showTracksSelection(
                                          context: context,
                                          player: widget.player,
                                          externalSubtitles: externalSubtitles,
                                        ),
                                      ),
                                    ),
                                    if (torrentStatus != null)
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(3),
                                        child: _buildActionButton(
                                          icon: Icons.folder,
                                          label: "Content",
                                          onTap: () => PlayerBottomSheets.showContentSelection(
                                            context: context,
                                            torrentStatus: torrentStatus,
                                            onTorrentFileSelected: (idx) => ref.read(playerControllerProvider.notifier).onTorrentFileSelected(idx),
                                          ),
                                        ),
                                      ),
                                    if (torrentStatus != null)
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(4),
                                        child: _buildActionButton(
                                          icon: Icons.info_outline,
                                          label: "Stats",
                                          onTap: () {
                                            setState(() => _showTorrentInfo = !_showTorrentInfo);
                                          },
                                          highlight: _showTorrentInfo,
                                        ),
                                      ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(5),
                                      child: _buildActionButton(
                                        icon: Icons.aspect_ratio,
                                        label: "Resize",
                                        onTap: cycleResize,
                                      ),
                                    ),
                                    if (ref.read(playerControllerProvider.notifier).isSeries)
                                      FocusTraversalOrder(
                                        order: const NumericFocusOrder(6),
                                        child: _buildActionButton(
                                          icon: Icons.skip_next,
                                          label: "Next",
                                          onTap: () => ref
                                              .read(playerControllerProvider.notifier)
                                              .playNextEpisode(),
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


  Widget _buildLoadingUI({String? title, String? subtitle}) {
    return PlayerLoadingOverlay(
      onDoubleTap: _handleDoubleTap,
      onBack: () => Navigator.of(context).pop(),
      title: title,
      subtitle: subtitle,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_view/video_view.dart' as vv;
import '../player_controller.dart';
import '../../../../shared/widgets/custom_widgets.dart';

/// A self-contained progress bar widget that uses StreamBuilder to avoid
/// rebuilding the parent widget on every position update.
class PlayerProgressBar extends ConsumerStatefulWidget {
  final Player player;
  final vv.VideoController? videoViewController;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;

  const PlayerProgressBar({
    super.key,
    required this.player,
    this.videoViewController,
    this.onSeekStart,
    this.onSeekEnd,
  });

  @override
  ConsumerState<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends ConsumerState<PlayerProgressBar> {
  double? _dragValue;

  // ValueNotifiers so position/duration updates don't setState the whole widget.
  final _vvPositionNotifier = ValueNotifier<int>(0);
  final _vvDurationNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    widget.videoViewController?.position.addListener(_onVvPosition);
    widget.videoViewController?.mediaInfo.addListener(_onVvMediaInfo);
  }

  @override
  void didUpdateWidget(PlayerProgressBar old) {
    super.didUpdateWidget(old);
    if (old.videoViewController != widget.videoViewController) {
      old.videoViewController?.position.removeListener(_onVvPosition);
      old.videoViewController?.mediaInfo.removeListener(_onVvMediaInfo);
      widget.videoViewController?.position.addListener(_onVvPosition);
      widget.videoViewController?.mediaInfo.addListener(_onVvMediaInfo);
    }
  }

  void _onVvPosition() {
    _vvPositionNotifier.value = widget.videoViewController?.position.value ?? 0;
  }

  void _onVvMediaInfo() {
    _vvDurationNotifier.value =
        widget.videoViewController?.mediaInfo.value?.duration ?? 0;
  }

  @override
  void dispose() {
    widget.videoViewController?.position.removeListener(_onVvPosition);
    widget.videoViewController?.mediaInfo.removeListener(_onVvMediaInfo);
    _vvPositionNotifier.dispose();
    _vvDurationNotifier.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final absDuration = duration.abs();
    final hours = absDuration.inHours;
    final minutes = absDuration.inMinutes.remainder(60);
    final seconds = absDuration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final useExoPlayer = ref.watch(
      playerControllerProvider.select((s) => s.useExoPlayer),
    );
    final canSeek = ref.watch(
      playerControllerProvider.select((s) => s.canSeek),
    );

    if (useExoPlayer && widget.videoViewController != null) {
      return _buildVideoViewBar(canSeek: canSeek);
    }
    return _buildMediaKitBar(canSeek: canSeek);
  }

  Widget _buildVideoViewBar({required bool canSeek}) {
    final isLive = ref.watch(playerControllerProvider.select((s) => s.isLive));

    return ValueListenableBuilder<int>(
      valueListenable: _vvDurationNotifier,
      builder: (context, durationMs, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _vvPositionNotifier,
          builder: (context, positionMs, _) {
            final durationMsD = durationMs.toDouble();
            final positionMsD = positionMs.toDouble();
            final displayValue = _dragValue ?? positionMsD;
            final displayDuration = Duration(
              milliseconds: (_dragValue ?? positionMsD).toInt(),
            );
            final duration = Duration(milliseconds: durationMs);

            return _buildRow(
              duration: duration,
              durationMs: durationMsD,
              displayValue: displayValue,
              displayDuration: displayDuration,
              bufferWidget: null,
              canSeek: canSeek,
              onSeekEnd: (val) => ref
                  .read(playerControllerProvider.notifier)
                  .seekTo(Duration(milliseconds: val.toInt())),
              isLive: isLive,
            );
          },
        );
      },
    );
  }

  Widget _buildMediaKitBar({required bool canSeek}) {
    final isLive = ref.watch(playerControllerProvider.select((s) => s.isLive));

    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      initialData: widget.player.state.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final durationMs = duration.inMilliseconds.toDouble();

        return StreamBuilder<Duration>(
          stream: widget.player.stream.position,
          initialData: widget.player.state.position,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final positionMs = position.inMilliseconds.toDouble();
            final displayValue = _dragValue ?? positionMs;
            final displayDuration = _dragValue != null
                ? Duration(milliseconds: _dragValue!.toInt())
                : position;

            final bufferWidget = durationMs > 0
                ? StreamBuilder<Duration>(
                    stream: widget.player.stream.buffer,
                    initialData: widget.player.state.buffer,
                    builder: (context, bufferSnapshot) {
                      final bufferMs = (bufferSnapshot.data ?? Duration.zero)
                          .inMilliseconds
                          .toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: LinearProgressIndicator(
                          value: (bufferMs / durationMs).clamp(0, 1),
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.25),
                          ),
                          minHeight: 4,
                        ),
                      );
                    },
                  )
                : null;

            return _buildRow(
              duration: duration,
              durationMs: durationMs,
              displayValue: displayValue,
              displayDuration: displayDuration,
              bufferWidget: bufferWidget,
              canSeek: canSeek,
              onSeekEnd: (val) => ref
                  .read(playerControllerProvider.notifier)
                  .seekTo(Duration(milliseconds: val.toInt())),
              isLive: isLive,
            );
          },
        );
      },
    );
  }

  Widget _buildRow({
    required Duration duration,
    required double durationMs,
    required double displayValue,
    required Duration displayDuration,
    required Widget? bufferWidget,
    required bool canSeek,
    required void Function(double val) onSeekEnd,
    bool isLive = false,
  }) {
    return Row(
      children: [
        const SizedBox(width: 12),
        // Left Side: Current Position
        SizedBox(
          width: duration.inHours > 0 ? 70 : 50,
          child: Text(
            _formatDuration(displayDuration),
            style: const TextStyle(
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              ?bufferWidget,
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                  trackShape: const RoundedRectSliderTrackShape(),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.2),
                ),
                child: CustomSlider(
                  value: displayValue.clamp(
                    0,
                    durationMs > 0 ? durationMs : 1.0,
                  ),
                  min: 0.0,
                  max: durationMs > 0 ? durationMs : 1.0,
                  step: 5000,
                  onChanged: canSeek
                      ? (val) => setState(() => _dragValue = val)
                      : null,
                  onChangeStart: canSeek
                      ? (val) {
                          widget.onSeekStart?.call();
                          setState(() => _dragValue = val);
                        }
                      : null,
                  onChangeEnd: canSeek
                      ? (val) {
                          onSeekEnd(val);
                          widget.onSeekEnd?.call();
                          setState(() => _dragValue = null);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (isLive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(50),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withAlpha(120), width: 1),
            ),
            child: const Text(
              "🔴  LIVE",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          )
        else
          SizedBox(
            width: duration.inHours > 0 ? 70 : 50,
            child: Text(
              _formatDuration(duration),
              style: const TextStyle(
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.left,
            ),
          ),
        const SizedBox(width: 12),
      ],
    );
  }
}

class PlayerPlayPauseButton extends StatelessWidget {
  final Player player;
  final vv.VideoController? videoViewController;
  final bool isLoading;
  final bool isTv;
  final FocusNode? focusNode;
  final VoidCallback? onPressed;

  const PlayerPlayPauseButton({
    super.key,
    required this.player,
    this.videoViewController,
    this.isLoading = false,
    this.isTv = false,
    this.focusNode,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final isBuffering = ref.watch(
          playerControllerProvider.select((s) => s.isBuffering),
        );
        final useExoPlayer = ref.watch(
          playerControllerProvider.select((s) => s.useExoPlayer),
        );

        if (useExoPlayer && videoViewController != null) {
          return ListenableBuilder(
            listenable: videoViewController!.playbackState,
            builder: (context, _) {
              final isPlaying =
                  videoViewController!.playbackState.value ==
                  vv.VideoControllerPlaybackState.playing;
              return _buildButton(
                isPlaying: isPlaying,
                isSpinning: isBuffering || isLoading,
              );
            },
          );
        }

        return StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (context, snapshot) {
            return _buildButton(
              isPlaying: snapshot.data ?? false,
              isSpinning: isBuffering || isLoading,
            );
          },
        );
      },
    );
  }

  Widget _buildButton({required bool isPlaying, required bool isSpinning}) {
    return CustomButton(
      showFocusHighlight: isTv,
      autofocus: true,
      focusNode: focusNode,
      onPressed: onPressed ?? () => player.playOrPause(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: isSpinning
            ? const SizedBox(
                width: 64,
                height: 64,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3.5,
                  ),
                ),
              )
            : Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 64,
              ),
      ),
    );
  }
}

class PlayerBufferingIndicator extends StatelessWidget {
  final bool isVisible;

  const PlayerBufferingIndicator({super.key, this.isVisible = false});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final isBuffering = ref.watch(
          playerControllerProvider.select((s) => s.isBuffering),
        );
        final isLoading = ref.watch(
          playerControllerProvider.select((s) => s.isLoading),
        );
        final userSkippedOverlay = ref.watch(
          playerControllerProvider.select((s) => s.userSkippedOverlay),
        );

        // If controls are visible, the play button already shows a spinner; skip.
        // If the user hasn't skipped and we are loading, the primary loading overlay is visible; skip.
        if ((!isBuffering && !isLoading) || isVisible) return const SizedBox.shrink();
        if (isLoading && !userSkippedOverlay) return const SizedBox.shrink();

        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

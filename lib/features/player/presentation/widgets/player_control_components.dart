import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../shared/widgets/custom_widgets.dart';
import 'player_stream_widgets.dart';

/// Top bar with back button and title for the player.
/// Extracted from SkyStreamPlayerControls to reduce widget size.
class PlayerTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool isTv;
  final FocusNode? backFocusNode;

  const PlayerTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.isTv = false,
    this.backFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
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
            top: MediaQuery.viewPaddingOf(context).top + 16,
            left: 16,
            right: 16,
            bottom: 8,
          ),
          child: Row(
            children: [
              CustomButton(
                showFocusHighlight: isTv,
                focusNode: backFocusNode,
                onPressed: onBack ?? () => Navigator.of(context).pop(),
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
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      title,
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
    );
  }
}

/// Center playback controls (seek back, play/pause, seek forward).
/// Uses StreamBuilder-based PlayerPlayPauseButton for efficient updates.
class PlayerCenterControls extends StatelessWidget {
  final Player player;
  final bool isLoading;
  final bool isTv;
  final FocusNode? playFocusNode;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final VoidCallback onPlayPause;

  const PlayerCenterControls({
    super.key,
    required this.player,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onPlayPause,
    this.isLoading = false,
    this.isTv = false,
    this.playFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Seek Backward
          CustomButton(
            showFocusHighlight: isTv,
            onPressed: onSeekBackward,
            child: const Icon(Icons.replay_10, color: Colors.white, size: 36),
          ),
          const SizedBox(width: 48),
          // Play/Pause Toggle
          PlayerPlayPauseButton(
            player: player,
            isLoading: isLoading,
            isTv: isTv,
            focusNode: playFocusNode,
            onPressed: onPlayPause,
          ),
          const SizedBox(width: 48),
          // Seek Forward
          CustomButton(
            showFocusHighlight: isTv,
            onPressed: onSeekForward,
            child: const Icon(Icons.forward_10, color: Colors.white, size: 36),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar with progress slider and action buttons.
class PlayerBottomBar extends StatelessWidget {
  final Player player;
  final VoidCallback onSeekStart;
  final List<Widget> actionButtons;

  const PlayerBottomBar({
    super.key,
    required this.player,
    required this.onSeekStart,
    required this.actionButtons,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
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
              PlayerProgressBar(player: player, onSeekStart: onSeekStart),
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
                          children: actionButtons,
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
    );
  }
}

/// A reusable action button for the player controls bottom bar.
class PlayerActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool rotate;
  final bool highlight;
  final bool isTv;
  final int focusOrder;

  const PlayerActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.rotate = false,
    this.highlight = false,
    this.isTv = false,
    this.focusOrder = 0,
  });

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(focusOrder.toDouble()),
      child: CustomButton(
        showFocusHighlight: isTv,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: rotate ? 0.5 : 0.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, child) {
                  return Transform.rotate(
                    angle: value * 3.14159,
                    child: Icon(
                      icon,
                      color: highlight ? Colors.blue : Colors.white,
                      size: 28,
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: highlight ? Colors.blue : Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../player_gesture_handler.dart';

/// Rebuilds only when [PlayerGestureHandler] notifies (OSD/volume state).
/// Use this instead of listening to the handler in the full controls to avoid
/// rebuilding the entire player UI on every OSD change.
class PlayerOSDVolumeOverlay extends ConsumerWidget {
  const PlayerOSDVolumeOverlay({
    super.key,
    required this.getDuration,
    required this.formatDuration,
  });

  final Duration Function() getDuration;
  final String Function(Duration) formatDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerGestureHandlerProvider);
    final handler = ref.read(playerGestureHandlerProvider.notifier);

    return Stack(
      children: [
        if (state.swipeSeekValue != null)
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
                '${formatDuration(state.swipeSeekValue!)} / ${formatDuration(getDuration())}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        PlayerOsdOverlay(
          showOSD: state.showOSD,
          osdValue: state.osdValue,
          osdLabel: state.osdLabel,
          osdIcon: state.osdIcon,
          osdAlignment: state.osdAlignment,
          supportsVolumeBoost: handler.supportsVolumeBoost,
        ),
      ],
    );
  }
}

class PlayerOsdOverlay extends StatelessWidget {
  final bool showOSD;
  final double? osdValue;
  final String osdLabel;
  final IconData osdIcon;
  final Alignment osdAlignment;
  final bool supportsVolumeBoost;

  const PlayerOsdOverlay({
    super.key,
    required this.showOSD,
    required this.osdValue,
    required this.osdLabel,
    required this.osdIcon,
    required this.osdAlignment,
    required this.supportsVolumeBoost,
  });

  @override
  Widget build(BuildContext context) {
    if (!showOSD) return const SizedBox.shrink();
    final bool showBoostState =
        supportsVolumeBoost &&
        (osdValue ?? 0) > 1.0 &&
        !(osdLabel == "Brightness" || osdLabel == "Auto");

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return _buildDesktopHorizontalOSD(showBoostState);
    }

    return Align(
      alignment: osdAlignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: osdValue == null
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
                      osdIcon,
                      color: showBoostState ? Colors.orange : Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      osdLabel,
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
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  children: [
                    Text(
                      osdLabel == "Auto"
                          ? "Auto"
                          : "${((osdValue ?? 0) * 100).toInt()}",
                      style: TextStyle(
                        color: showBoostState ? Colors.orange : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SizedBox(
                        width: 12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              // Background
                              Container(
                                color: Colors.grey.withValues(alpha: 0.5),
                              ),
                              // White Bar
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final bool isBrightness =
                                      osdLabel == "Brightness" ||
                                      osdLabel == "Auto";
                                  final double val = (osdValue ?? 0).clamp(
                                    0.0,
                                    1.0,
                                  );
                                  final double scale = isBrightness
                                      ? 1.0
                                      : (supportsVolumeBoost ? 0.5 : 1.0);

                                  return Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: val * scale,
                                      child: Container(color: Colors.white),
                                    ),
                                  );
                                },
                              ),
                              if (showBoostState)
                                LayoutBuilder(
                                  builder: (ctx, constraints) {
                                    final double boost = (osdValue! - 1.0)
                                        .clamp(0.0, 1.0);
                                    final double orangeHeight =
                                        constraints.maxHeight * (boost * 0.5);
                                    final double bottomOffset =
                                        constraints.maxHeight * 0.5;

                                    return Align(
                                      alignment: Alignment.bottomCenter,
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
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        osdIcon,
                        key: ValueKey(osdIcon),
                        color: showBoostState ? Colors.orange : Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDesktopHorizontalOSD(bool showBoostState) {
    final bool isLevel = osdValue != null;
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
                osdIcon,
                color: showBoostState ? Colors.orange : Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              if (!isLevel)
                Expanded(
                  child: Center(
                    child: Text(
                      osdLabel,
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
                                  osdLabel == "Brightness" ||
                                  osdLabel == "Auto";
                              final double val = (osdValue ?? 0).clamp(
                                0.0,
                                1.0,
                              );
                              final double scale = isBrightness
                                  ? 1.0
                                  : (supportsVolumeBoost ? 0.5 : 1.0);
                              return FractionallySizedBox(
                                widthFactor: val * scale,
                                child: Container(color: Colors.white),
                              );
                            },
                          ),
                          if (showBoostState)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final double boost = (osdValue! - 1.0).clamp(
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
                    "${((osdValue! * 100).toInt())}%",
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: showBoostState ? Colors.orange : Colors.white,
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
}

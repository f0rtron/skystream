import 'package:flutter/material.dart';

class PlayerLoadingOverlay extends StatelessWidget {
  final VoidCallback onDoubleTap;
  final VoidCallback onBack;

  const PlayerLoadingOverlay({
    super.key,
    required this.onDoubleTap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + 16,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 36),
                  tooltip: 'Go Back',
                  onPressed: onBack,
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

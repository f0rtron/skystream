import 'package:flutter/material.dart';

class PlayerLoadingOverlay extends StatelessWidget {
  final VoidCallback onDoubleTap;
  final VoidCallback onBack;
  final String? title;
  final String? subtitle;

  const PlayerLoadingOverlay({
    super.key,
    required this.onDoubleTap,
    required this.onBack,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          // Solid background
          Positioned.fill(child: Container(color: Colors.black)),

          // Back button
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 16,
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
                onPressed: onBack,
              ),
            ),
          ),

          // Loading Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 24),
                if (title != null)
                  Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 22),
                const Text(
                  "Finding the best available source…",
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

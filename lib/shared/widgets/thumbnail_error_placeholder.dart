import 'package:flutter/material.dart';

/// Consistent error placeholder for thumbnails/posters when image loading fails.
/// Use this across all screens (discover, search, library, details, etc.) for
/// a unified look and theme-aware styling.
class ThumbnailErrorPlaceholder extends StatelessWidget {
  final double? iconSize;

  const ThumbnailErrorPlaceholder({super.key, this.iconSize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = iconSize ?? 48.0;
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.broken_image,
          size: size,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

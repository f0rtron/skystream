import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import 'package:skystream/shared/widgets/focusable_item.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Added import

class ContinueWatchingCard extends ConsumerWidget {
  // Changed to ConsumerWidget
  final HistoryItem historyItem;
  final double width;
  final bool isLarge;

  const ContinueWatchingCard({
    super.key,
    required this.historyItem,
    this.width = 110,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Added ref
    final item = historyItem.item;
    // Calculate progress (0.0 to 1.0)
    final double progress = (historyItem.duration > 0)
        ? (historyItem.position / historyItem.duration).clamp(0.0, 1.0)
        : 0.0;

    return FocusableItem(
      onTap: () =>
          context.push('/details', extra: {'item': item, 'autoPlay': true}),
      // Android-like behaviour: Long press to show metadata/action
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                // Basic Actions
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('View Details'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/details', extra: item); // Standard view
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Remove from History',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    // ref is available here because we capture it from build
                    ref
                        .read(watchHistoryProvider.notifier)
                        .removeFromHistory(item.url);
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed ${item.title} from history'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // Poster
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: CachedNetworkImage(
                      imageUrl: item.posterUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.broken_image),
                    ),
                  ),

                  // Dark Overlay & Play Icon
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26, // Slight dim
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white70, width: 2),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Progress Bar
                  if (progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white30,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: isLarge ? 15 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

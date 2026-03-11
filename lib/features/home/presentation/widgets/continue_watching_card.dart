import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';

import 'package:skystream/shared/widgets/focusable_item.dart';
import 'package:skystream/shared/widgets/thumbnail_error_placeholder.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/router/app_router.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import '../../../../core/extensions/extension_manager.dart';

class ContinueWatchingCard extends ConsumerWidget {
  final HistoryItem historyItem;
  final double width;
  final bool isLarge;

  const ContinueWatchingCard({
    super.key,
    required this.historyItem,
    this.width = 280,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = historyItem.item;
    // Calculate progress (0.0 to 1.0)
    final double progress = (historyItem.duration > 0)
        ? (historyItem.position / historyItem.duration).clamp(0.0, 1.0)
        : 0.0;
    final int percentage = (progress * 100).toInt();

    // Resolve Provider Name
    final providers = ref.watch(extensionManagerProvider);
    final providerObj = (item.provider != null)
        ? providers.where((p) => p.id == item.provider).firstOrNull
        : null;
    final providerName = providerObj?.name ?? item.provider;

    return FocusableItem(
      onTap: () =>
          context.push('/details', extra: DetailsRouteExtra(item: item, autoPlay: true)),
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
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('View Details'),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/details', extra: DetailsRouteExtra(item: item));
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Remove from History',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  onTap: () {
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
      child: Stack(
        children: [
          Container(
            width: width,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
                      fit: BoxFit.cover,
                      memCacheWidth: 200, // P15: Optimize memory
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (_, _, _) =>
                          const ThumbnailErrorPlaceholder(),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (item.provider != null && item.provider!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              providerName!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const Spacer(),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "$percentage% watched",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Close button at top-right corner
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  ref
                      .read(watchHistoryProvider.notifier)
                      .removeFromHistory(item.url);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed ${item.title} from history'),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

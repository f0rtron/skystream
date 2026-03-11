import 'package:skystream/shared/widgets/focusable_item.dart';
import 'package:skystream/shared/widgets/thumbnail_error_placeholder.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/router/app_router.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'library_provider.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryItems = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: libraryItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_outline_rounded,
                    size: 64,
                    color: Theme.of(context).dividerColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your library is empty',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(LayoutConstants.spacingMd),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180, // Responsive column sizing
                childAspectRatio: 2 / 3.4, // Matches poster aspect ratio
                crossAxisSpacing: LayoutConstants.spacingMd,
                mainAxisSpacing: LayoutConstants.spacingMd,
              ),
              itemCount: libraryItems.length,
              itemBuilder: (context, index) {
                final item = libraryItems[index];
                return RepaintBoundary(child: FocusableItem(
                  onTap: () => context.push('/details', extra: DetailsRouteExtra(item: item)),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
                            fit: BoxFit.cover,
                            memCacheWidth: 300, // P15: Optimize memory
                            placeholder: (context, url) => Container(
                              color: Theme.of(context).dividerColor,
                            ),
                            errorWidget: (_, _, _) =>
                                const ThumbnailErrorPlaceholder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ));
              },
            ),
    );
  }
}

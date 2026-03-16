import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/features/search/presentation/search_provider.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../details_screen.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';

// Delegates to the shared searchAllProviders() function — no duplicated
// fan-out, mapping, or filtering logic.
final _providerSearchProvider = StreamProvider.family
    .autoDispose<SearchAggregateState, String>((ref, query) {
      ref.watch(extensionManagerProvider);
      final manager = ref.read(extensionManagerProvider.notifier);
      // Collect the final emission from the incremental stream

      var cancelled = false;
      ref.onDispose(() => cancelled = true);

      return searchAllProviders(
        query,
        manager,
        isCancelled: () => cancelled,
      );
    });

class ProviderSearchSection extends ConsumerStatefulWidget {
  final String query;
  final bool compact;
  final String? parentMediaType; // 'movie' or 'tv'

  const ProviderSearchSection({
    super.key,
    required this.query,
    this.compact = false,
    this.parentMediaType,
  });

  @override
  ConsumerState<ProviderSearchSection> createState() =>
      _ProviderSearchSectionState();
}

class _ProviderSearchSectionState extends ConsumerState<ProviderSearchSection> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.isEmpty) return const SizedBox.shrink();

    final plugins = ref.watch(extensionManagerProvider);
    final searchAsync = ref.watch(_providerSearchProvider(widget.query));

    Widget content;
    if (plugins.isEmpty) {
      content = Container(
        height: 140,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(LayoutConstants.spacingMd),
        child: Text(
          "No plugins installed",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );
    } else {
      content = searchAsync.when(
        data: (state) {
          final allItems = <Map<String, dynamic>>[];
          for (var pResult in state.results) {
            for (var item in pResult.results) {
              allItems.add({
                'item': item,
                'providerName': pResult.providerName,
              });
            }
          }

          if (allItems.isEmpty) {
            if (state.isLoading) {
              return const SizedBox(
                height: 140,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return Container(
              height: 140,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(LayoutConstants.spacingMd),
              child: Text(
                "No streams found.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            );
          }

          return SizedBox(
            height: 140,
            child: DesktopScrollWrapper(
              controller: _scrollController,
              child: ListView.separated(
                controller: _scrollController,
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                padding: widget.compact
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(
                        horizontal: LayoutConstants.spacingMd,
                      ),
                itemCount: allItems.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: LayoutConstants.spacingSm),
                itemBuilder: (context, index) {
                  final data = allItems[index];
                  final item = data['item'] as MultimediaItem;
                  final providerName = data['providerName'] as String;

                  return CardsWrapper(
                    onTap: () {
                      // Enrich item with provider and content type before navigation
                      final enrichedItem = item.copyWith(
                        provider: providerName,
                        contentType: widget.parentMediaType != null
                            ? MultimediaItem.parseContentType(
                                widget.parentMediaType,
                              )
                            : item.contentType,
                      );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              DetailsScreen(item: enrichedItem),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 220,
                      child: Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        color: Theme.of(context).colorScheme.surface,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              height: double.infinity,
                              child: CachedNetworkImage(
                                imageUrl: AppImageFallbacks.poster(
                                  item.posterUrl,
                                  label: item.title,
                                ),
                                fit: BoxFit.cover,
                                placeholder: (_, _) =>
                                    ShimmerPlaceholder(borderRadius: 8),
                                errorWidget: (_, _, _) =>
                                    const ThumbnailErrorPlaceholder(),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
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
                                        providerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        loading: () => const SizedBox(
          height: 140, // Fix 2: Force height for centering
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (err, _) => Padding(
          padding: const EdgeInsets.all(LayoutConstants.spacingMd),
          child: Text("Error: $err"),
        ),
      );
    }

    if (widget.compact) return content;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 180),
      clipBehavior: Clip.hardEdge, // Fix 1: Clip content to container borders
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: LayoutConstants.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutConstants.spacingMd,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.extension,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: LayoutConstants.spacingXs),
                Text(
                  "Available Sources",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: LayoutConstants.spacingXs),
                // Fix 3: Styled Beta Tag
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "BETA",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LayoutConstants.spacingSm),
          content,
        ],
      ),
    );
  }
}

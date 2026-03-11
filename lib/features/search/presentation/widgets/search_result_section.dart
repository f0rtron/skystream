import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';

import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/router/app_router.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/shared/widgets/desktop_scroll_wrapper.dart';
import 'package:skystream/shared/widgets/thumbnail_error_placeholder.dart';
import '../../../../shared/widgets/cards_wrapper.dart';

class SearchResultSection extends ConsumerStatefulWidget {
  final String providerName;
  final String providerId;
  final List<MultimediaItem> results;

  const SearchResultSection({
    super.key,
    required this.providerName,
    required this.providerId,
    required this.results,
  });

  @override
  ConsumerState<SearchResultSection> createState() =>
      _SearchResultSectionState();
}

class _SearchResultSectionState extends ConsumerState<SearchResultSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty) return const SizedBox.shrink();

    final isLarge = context.isTabletOrLarger;
    // Matching MediaHorizontalList/ContinueWatchingSection dimensions
    final double width = isLarge ? 200.0 : 130.0;
    final double listHeight = isLarge ? 350.0 : 230.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Blue Accent Style
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.providerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isLarge ? 24 : 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        _buildDebugTag(context, ref),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: isLarge ? 30 : 20,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: listHeight,
          child: DesktopScrollWrapper(
            controller: _scrollController,
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: widget.results.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: isLarge ? 24 : 12),
              itemBuilder: (context, rIndex) {
                final item = widget.results[rIndex];
                final uniqueTag =
                    'search_${widget.providerId}_${item.url}_$rIndex';

                return RepaintBoundary(child: CardsWrapper(
                  key: ValueKey(item.url),
                  onTap: () => context.push('/details', extra: DetailsRouteExtra(item: item)),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Hero(
                            tag: uniqueTag, // Added Hero tag support
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                memCacheWidth:
                                    300, // P15: Optimize memory usage
                                placeholder: (context, url) => Container(
                                  color: Theme.of(context).dividerColor,
                                ),
                                errorWidget: (_, _, _) =>
                                    const ThumbnailErrorPlaceholder(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 1, // Matched Dashboard style
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.8),
                            fontSize: isLarge ? 22 : 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ));
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebugTag(BuildContext context, WidgetRef ref) {
    bool isDebug = false;
    try {
      final manager = ref.read(extensionManagerProvider.notifier);
      final p = manager.getAllProviders().firstWhere(
        (p) => p.id == widget.providerId,
      );
      if (p.isDebug) {
        isDebug = true;
      }
    } catch (e) {
      debugPrint('SearchResultSection._buildDebugTag: $e');
    }

    if (!isDebug) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'DEBUG',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/shared/widgets/focusable_item.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/core/router/app_router.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';

class HomeSection extends ConsumerStatefulWidget {
  final String title;
  final List<MultimediaItem> items;
  const HomeSection({super.key, required this.title, required this.items});

  @override
  ConsumerState<HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends ConsumerState<HomeSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final isLarge = context.isTabletOrLarger;

    final double width = isLarge ? 170 : 110;
    final double posterHeight = width * 1.5; // 2:3 aspect ratio
    final double totalHeight = posterHeight + 100; // Space for text and focus

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            widget.title,
            style: isLarge
                ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  )
                : Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          height: totalHeight,
          child: DesktopScrollWrapper(
            controller: _scrollController,
            showButtons: isLarge, // Show nav buttons on both desktop and TV
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutConstants.spacingMd,
                vertical: LayoutConstants.spacingXs,
              ), // Added vertical padding for focus scaling
              scrollDirection: Axis.horizontal,
              itemCount: widget.items.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: isLarge ? LayoutConstants.spacingLg : LayoutConstants.spacingSm),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return FocusableItem(
                  key: ValueKey(item.url),
                  onTap: () => context.push('/details', extra: DetailsRouteExtra(item: item)),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
                              fit: BoxFit.cover,
                              memCacheWidth: 350, // P15: Optimize memory
                              placeholder: (context, url) => Container(
                                color: Theme.of(context).dividerColor,
                              ),
                              errorWidget: (_, _, _) =>
                                  const ThumbnailErrorPlaceholder(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                                fontSize: isLarge ? 15 : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

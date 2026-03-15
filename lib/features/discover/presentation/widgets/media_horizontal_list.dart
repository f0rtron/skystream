import 'package:flutter/material.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../details/presentation/tmdb_movie_details_screen.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../shared/widgets/multimedia_card.dart';
import '../view_all_screen.dart';
import '../../../../core/domain/entity/multimedia_item.dart';

class MediaHorizontalList extends StatefulWidget {
  final String title;
  final List<MultimediaItem> mediaList;
  final ViewAllCategory category;
  final void Function(MultimediaItem)? onTap;
  final bool showViewAll;
  final String? heroTagPrefix;

  const MediaHorizontalList({
    super.key,
    required this.title,
    required this.mediaList,
    required this.category,
    this.onTap,
    this.showViewAll = true,
    this.heroTagPrefix,
  });

  @override
  State<MediaHorizontalList> createState() => _MediaHorizontalListState();
}

class _MediaHorizontalListState extends State<MediaHorizontalList> {
  late ScrollController _scrollController;

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
    if (widget.mediaList.isEmpty) return const SizedBox.shrink();

    final isDesktop = context.isDesktop;
    final listHeight = isDesktop ? 350.0 : 230.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row
        Padding(
          padding: const EdgeInsets.fromLTRB(LayoutConstants.spacingMd, LayoutConstants.spacingLg, LayoutConstants.spacingMd, LayoutConstants.spacingSm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Title with Blue Underline Accent
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isDesktop ? 24 : 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: isDesktop ? 30 : 20, // Accent width
                      height: 3,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showViewAll) const SizedBox(width: LayoutConstants.spacingXs),

              if (widget.showViewAll)
                CardsWrapper(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ViewAllScreen(
                          title: widget.title,
                          initialMediaList: widget.mediaList,
                          category: widget.category,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LayoutConstants.spacingSm,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "View All",
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 10,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // List
        SizedBox(
          height: listHeight, // Adjusted for 2:3 ratio within list
          child: DesktopScrollWrapper(
            // Wraps ListView
            controller: _scrollController,
            showButtons: isDesktop, // Show nav buttons on desktop/TV
            child: ListView.separated(
              controller: _scrollController, // Passes controller
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd),
              scrollDirection: Axis.horizontal,
              itemCount: widget.mediaList.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: isDesktop ? LayoutConstants.spacingLg : LayoutConstants.spacingSm),
              itemBuilder: (context, index) {
                final item = widget.mediaList[index];
                final imageUrl = item.posterImageUrl;
                final itemTitle = item.title;
                final prefix = widget.heroTagPrefix ?? 'list';
                final uniqueTag =
                    '${prefix}_${widget.title}_${item.id}_${itemTitle.hashCode}_$index';
                final mediaType = item.mediaType;

                return MultimediaCard(
                  imageUrl: imageUrl,
                  title: itemTitle,
                  heroTag: uniqueTag,
                  onTap: () {
                    if (widget.onTap != null) {
                      widget.onTap!(item);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => TmdbMovieDetailsScreen(
                            movieId: item.id,
                            mediaType: mediaType,
                            heroTag: uniqueTag,
                            placeholderPoster: imageUrl,
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

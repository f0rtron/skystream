import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../core/utils/image_fallbacks.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';

import '../../library/presentation/library_provider.dart';

import 'details_controller.dart';
import "widgets/details_layout_widgets.dart";
import "widgets/premium_details_widgets.dart";
import "../../../shared/widgets/expandable_text.dart";

class DetailsScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final bool autoPlay;

  const DetailsScreen({super.key, required this.item, this.autoPlay = false});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  bool _didTriggerAutoPlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(detailsControllerProvider(widget.item.url).notifier)
          .loadDetails(widget.item, autoPlay: widget.autoPlay);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(detailsControllerProvider(widget.item.url), (prev, next) {
      if (!widget.autoPlay || _didTriggerAutoPlay) return;
      final prevState = prev ?? const DetailsState();
      final nextState = next;
      if (prevState.details.isLoading != true || !nextState.details.hasValue)
        return;
      final item = nextState.details.value!;
      _didTriggerAutoPlay = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(detailsControllerProvider(widget.item.url).notifier)
            .handlePlayPress(context, item);
      });
    });
    final isBookmarked = ref.watch(
      libraryProvider.select(
        (items) => items.any((i) => i.url == widget.item.url),
      ),
    );
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final isLarge = context.isTabletOrLarger;

    final detailsAsync = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.details),
    );
    final details = detailsAsync.value;
    final isMovie = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.isMovie),
    );
    final item = details ?? widget.item;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: isLarge
                ? LayoutConstants.detailsExpandedHeightDesktop
                : LayoutConstants.detailsExpandedHeightMobile,
            stretch: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'banner_${item.url}',
                    child: CachedNetworkImage(
                      imageUrl:
                          AppImageFallbacks.optional(item.bannerUrl) ??
                          AppImageFallbacks.poster(
                            item.posterUrl,
                            label: item.title,
                          ),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      memCacheWidth: 800, // P19: Optimize memory
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                        label: item.title,
                        isBackdrop: true,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.5),
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                foregroundColor: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: isBookmarked
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                ),
                onPressed: () {
                  if (isBookmarked) {
                    libraryNotifier.removeItem(item.url);
                  } else {
                    libraryNotifier.addItem(item);
                  }
                },
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (isLarge)
            ..._buildDesktopSlivers(
              context,
              item,
              details,
              detailsAsync,
              isMovie,
            )
          else
            ..._buildMobileSlivers(
              context,
              item,
              details,
              detailsAsync,
              isMovie,
            ),
        ],
      ),
    );
  }

  List<Widget> _buildDesktopSlivers(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState,
    bool isMovie,
  ) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Poster and actions
              SizedBox(
                width: 250,
                child: Column(
                  children: [
                    Hero(
                      tag: 'poster_${item.url}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: AppImageFallbacks.poster(
                            item.posterUrl,
                            label: item.title,
                          ),
                          width: 250,
                          height: 375,
                          fit: BoxFit.cover,
                          memCacheWidth: 250, // P19: Optimize memory
                          errorWidget: (_, _, _) =>
                              ThumbnailErrorPlaceholder(label: item.title),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    DetailsActionButtons(
                      item: widget.item,
                      details: details,
                      itemUrl: widget.item.url,
                      vertical: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              // Right side: Metadata and Synopsis
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.logoUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: CachedNetworkImage(
                          imageUrl: item.logoUrl!,
                          height: 80,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                        ),
                      )
                    else
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    const SizedBox(height: 16),
                    MetadataBar(
                      item: item,
                      isLoading: detailsState is AsyncLoading,
                    ),
                    const SizedBox(height: 24),
                    if (item.nextAiring != null) ...[
                      NextAiringWidget(nextAiring: item.nextAiring!),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      'Synopsis',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),
                    ExpandableText(
                      text: item.description ?? 'No description available.',
                      maxLines: 10,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detailsState is AsyncLoading)
                const Center(child: CircularProgressIndicator())
              else if (detailsState is AsyncError)
                Text(
                  "Error: ${detailsState.error}",
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (!isMovie && details?.episodes != null)
                DetailsSeasonListWrapper(itemUrl: widget.item.url),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
        sliver: SliverDetailsDesktopEpisodeGrid(
          parentItem: item,
          itemUrl: widget.item.url,
          isMovie: isMovie,
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 50),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.cast != null && item.cast!.isNotEmpty) ...[
                CastCarousel(cast: item.cast!),
              ],
              if (item.trailers != null && item.trailers!.isNotEmpty) ...[
                const SizedBox(height: 32),
                TrailersSection(trailers: item.trailers!),
              ],
              if (item.recommendations != null &&
                  item.recommendations!.isNotEmpty) ...[
                const SizedBox(height: 32),
                RecommendationsCarousel(
                  items: item.recommendations!,
                  onItemTap: (rec) {
                    context.push(
                      '/details',
                      extra: DetailsRouteExtra(item: rec),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildMobileSlivers(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState,
    bool isMovie,
  ) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'poster_${item.url}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: AppImageFallbacks.poster(
                          item.posterUrl,
                          label: item.title,
                        ),
                        width: 100,
                        height: 150,
                        fit: BoxFit.cover,
                        memCacheWidth:
                            200, // P19: Optimize memory (2x for retina)
                        errorWidget: (_, _, _) =>
                            ThumbnailErrorPlaceholder(label: item.title),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.logoUrl != null)
                          CachedNetworkImage(
                            imageUrl: item.logoUrl!,
                            height: 50,
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                            errorWidget: (_, _, _) => Text(
                              item.title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          )
                        else
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        const SizedBox(height: 8),
                        MetadataBar(
                          item: item,
                          isLoading: detailsState is AsyncLoading,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              DetailsActionButtons(
                item: widget.item,
                details: details,
                itemUrl: widget.item.url,
              ),
              if (item.nextAiring != null) ...[
                const SizedBox(height: 16),
                NextAiringWidget(nextAiring: item.nextAiring!),
              ],
              const SizedBox(height: 24),
              Text(
                'Synopsis',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 8),
              ExpandableText(
                text: item.description ?? 'No description available.',
                maxLines: 4,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              if (detailsState is AsyncLoading)
                const Center(child: CircularProgressIndicator())
              else if (detailsState is AsyncError)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.1),
                  child: Text("Error: ${detailsState.error}"),
                )
              else if (!isMovie && details?.episodes != null)
                DetailsSeasonListWrapper(itemUrl: widget.item.url),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        sliver: SliverDetailsEpisodeList(
          parentItem: item,
          itemUrl: widget.item.url,
          isMovie: isMovie,
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.cast != null && item.cast!.isNotEmpty) ...[
                const SizedBox(height: 16),
                CastCarousel(cast: item.cast!),
              ],
              if (item.trailers != null && item.trailers!.isNotEmpty) ...[
                const SizedBox(height: 32),
                TrailersSection(trailers: item.trailers!),
              ],
              if (item.recommendations != null &&
                  item.recommendations!.isNotEmpty) ...[
                const SizedBox(height: 32),
                RecommendationsCarousel(
                  items: item.recommendations!,
                  onItemTap: (rec) {
                    context.push(
                      '/details',
                      extra: DetailsRouteExtra(item: rec),
                    );
                  },
                ),
              ],
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    ];
  }
}

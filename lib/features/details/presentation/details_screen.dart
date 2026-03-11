import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../core/utils/image_fallbacks.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';

import '../../library/presentation/library_provider.dart';

import 'details_controller.dart';
import "widgets/details_layout_widgets.dart";

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
      if (prevState.details.isLoading != true || !nextState.details.hasValue) return;
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

    final state = ref.watch(detailsControllerProvider(widget.item.url));
    final details = state.details.value;
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
                      imageUrl: AppImageFallbacks.optional(item.bannerUrl) ??
                        AppImageFallbacks.poster(item.posterUrl, label: item.title),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      memCacheWidth: 800, // P19: Optimize memory
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (_, _, _) =>
                          const ThumbnailErrorPlaceholder(),
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
              onPressed: () => Navigator.of(context).pop(),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isLarge ? 32.0 : 16.0,
                vertical: 16.0,
              ),
              child: isLarge
                  ? _buildDesktopLayout(context, item, details, state)
                  : _buildMobileLayout(context, item, details, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    DetailsState state,
  ) {
    return Row(
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
                    imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
                    width: 250,
                    height: 375,
                    fit: BoxFit.cover,
                    memCacheWidth: 250, // P19: Optimize memory
                  ),
                ),
              ),
              const SizedBox(height: 24),
              DetailsActionButtons(
                item: widget.item,
                details: details,
                state: state,
                vertical: true,
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        // Right side: Metadata and episodes
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.episodes != null && item.episodes!.length > 1)
                    DetailsChip(label: '${item.episodes!.length} Eps'),
                  if (item.provider != null)
                    DetailsProviderChip(providerName: item.provider!),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Synopsis',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.description ?? 'No description available.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              if (state.details is AsyncLoading)
                const Center(child: CircularProgressIndicator())
              else if (state.details is AsyncError)
                Text(
                  "Error: ${state.details.error}",
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (state.isMovie)
                const SizedBox.shrink() // Movies don't need an episode list
              else if (details?.episodes != null) ...[
                if (state.seasonMap.keys.length > 1)
                  DetailsSeasonSelector(state: state, itemUrl: widget.item.url),
                const SizedBox(height: 16),
                DetailsDesktopEpisodeGrid(
                  episodes: state.seasonMap[state.selectedSeason] ?? [],
                  parentItem: item,
                  state: state,
                ),
              ] else
                const Text("No episodes found."),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    DetailsState state,
  ) {
    return Column(
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
                  imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
                  width: 100,
                  height: 150,
                  fit: BoxFit.cover,
                  memCacheWidth: 200, // P19: Optimize memory (2x for retina)
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (item.episodes != null && item.episodes!.length > 1)
                        DetailsChip(label: '${item.episodes!.length} Eps'),
                      if (item.provider != null)
                        DetailsProviderChip(providerName: item.provider!),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        DetailsActionButtons(item: widget.item, details: details, state: state),
        const SizedBox(height: 24),
        Text(
          'Synopsis',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          item.description ?? 'No description available.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).textTheme.bodyMedium?.color,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        if (state.details is AsyncLoading)
          Container(
            height: 100,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          )
        else if (state.details is AsyncError)
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
            child: Text("Error: ${state.details.error}"),
          )
        else if (state.isMovie)
          const SizedBox.shrink()
        else if (details?.episodes != null) ...[
          if (state.seasonMap.keys.length > 1)
            DetailsSeasonSelector(state: state, itemUrl: widget.item.url),
          const SizedBox(height: 16),
          DetailsEpisodeList(
            episodes: state.seasonMap[state.selectedSeason] ?? [],
            parentItem: item,
            state: state,
          ),
        ] else
          const Text("No episodes found."),
        const SizedBox(height: 50),
      ],
    );
  }
}

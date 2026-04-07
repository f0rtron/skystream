import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';

import '../controllers/discover_search_controller.dart';

class DiscoverSearchDelegate extends SearchDelegate {
  DiscoverSearchDelegate()
    : super(
        searchFieldLabel: 'Search movies, tv shows...',
        searchFieldStyle: const TextStyle(color: Colors.white70, fontSize: 18),
      );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        toolbarHeight: 70,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        border: InputBorder.none,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: theme.colorScheme.primary,
        selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
      const SizedBox(width: 8),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();

    return _SearchResultsGrid(query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();

    return _SearchSuggestionsList(query: query);
  }
}

class _SearchSuggestionsList extends ConsumerStatefulWidget {
  final String query;

  const _SearchSuggestionsList({required this.query});

  @override
  ConsumerState<_SearchSuggestionsList> createState() =>
      _SearchSuggestionsListState();
}

class _SearchSuggestionsListState
    extends ConsumerState<_SearchSuggestionsList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(discoverSearchControllerProvider.notifier)
          .onQueryChanged(widget.query);
    });
  }

  @override
  void didUpdateWidget(covariant _SearchSuggestionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(discoverSearchControllerProvider.notifier)
            .onQueryChanged(widget.query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(discoverSearchControllerProvider);
    final isLoading = searchState.isLoading;
    final suggestions = searchState.suggestions;
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
      );
    }

    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final item = suggestions[index];
        final title = item.title;
        final year = item.releaseDate.split('-').first;
        final mediaType = item.mediaType;

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: item.thumbnailImageUrl,
              width: 40,
              height: 60,
              fit: BoxFit.cover,
              placeholder: (_, _) => ShimmerPlaceholder(borderRadius: 4),
            ),
          ),
          title: Text(
            title,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          subtitle: Text(
            '$mediaType ${year.isNotEmpty ? '($year)' : ''}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          onTap: () {
            context.push(
              '/tmdb-details',
              extra: TmdbDetailsRouteExtra(
                movieId: item.id,
                mediaType: item.tmdbMediaType,
                heroTag: 'search_${item.id}',
              ),
            );
          },
        );
      },
    );
  }
}

class _SearchResultsGrid extends ConsumerStatefulWidget {
  final String query;

  const _SearchResultsGrid({required this.query});

  @override
  ConsumerState<_SearchResultsGrid> createState() => _SearchResultsGridState();
}

class _SearchResultsGridState extends ConsumerState<_SearchResultsGrid> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(discoverSearchControllerProvider.notifier)
          .fetchResults(widget.query);
    });
  }

  @override
  void didUpdateWidget(covariant _SearchResultsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(discoverSearchControllerProvider.notifier)
            .fetchResults(widget.query);
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(discoverSearchControllerProvider.notifier).fetchNextPage();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(discoverSearchControllerProvider);
    final isLoading = searchState.isLoading;
    final results = searchState.results;
    if (isLoading && results.isEmpty) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final isDesktop =
          screenWidth > LayoutConstants.discoverCarouselDesktopBreakpoint;
      final maxExtent = isDesktop ? 240.0 : 150.0;
      const childAspectRatio = 0.55;

      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 10,
        itemBuilder: (context, index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: ShimmerPlaceholder(borderRadius: 12)),
              const SizedBox(height: 8),
              ShimmerPlaceholder.rectangular(height: 14, borderRadius: 4),
            ],
          );
        },
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 60,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              "No results found for \"${widget.query}\"",
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop =
        screenWidth > LayoutConstants.discoverCarouselDesktopBreakpoint;
    final maxExtent = isDesktop ? 240.0 : 150.0;
    const childAspectRatio = 0.55;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: results.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          return ShimmerPlaceholder(borderRadius: 12);
        }

        final item = results[index];
        final imageUrl = item.posterImageUrl;
        final title = item.title;
        final id = item.id;
        final mediaType = item.mediaType;
        final uniqueTag = 'search_result_${id}_$index';

        return GestureDetector(
          onTap: () {
            context.push(
              '/tmdb-details',
              extra: TmdbDetailsRouteExtra(
                movieId: id,
                mediaType: mediaType,
                heroTag: uniqueTag,
                placeholderPoster: imageUrl,
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
                  tag: uniqueTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, _) =>
                          ShimmerPlaceholder(borderRadius: 4),
                      errorWidget: (_, _, _) =>
                          const ThumbnailErrorPlaceholder(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

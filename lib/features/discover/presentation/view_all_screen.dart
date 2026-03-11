import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/widgets/cards_wrapper.dart';
import '../../details/presentation/tmdb_movie_details_screen.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/models/tmdb_item.dart';
import 'controllers/view_all_controller.dart';

enum ViewAllCategory {
  popularMovies,
  popularTV,
  nowPlayingMovies,
  onTheAirTV,
  topRatedMovies,
  topRatedTV,
  airingTodayTV,
  trending,
}

class ViewAllScreen extends ConsumerStatefulWidget {
  final String title;
  final List<TmdbItem> initialMediaList;
  final ViewAllCategory category;

  const ViewAllScreen({
    super.key,
    required this.title,
    required this.initialMediaList,
    required this.category,
  });

  @override
  ConsumerState<ViewAllScreen> createState() => _ViewAllScreenState();
}

class _ViewAllScreenState extends ConsumerState<ViewAllScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(viewAllControllerProvider(widget.category).notifier)
          .init(widget.initialMediaList);
      _checkInitialFill();
    });
  }

  void _checkInitialFill() {
    if (!mounted) return;
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent <= 0) {
      final state = ref.read(viewAllControllerProvider(widget.category));
      if (state.hasMore && !state.isLoading) {
        ref.read(viewAllControllerProvider(widget.category).notifier).fetchNextPage().then((_) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _checkInitialFill(),
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(viewAllControllerProvider(widget.category).notifier).fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ViewAllState state = ref.watch(viewAllControllerProvider(widget.category));

    // Calculate aspect ratio for 2:3 posters
    final isDesktop = context.isDesktop;
    final maxExtent = isDesktop ? 240.0 : 150.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = (screenWidth / maxExtent).ceil();
    const childAspectRatio = 0.55;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black45,
            foregroundColor: Colors.white,
          ),
        ),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0.0, 0.3],
          ),
        ),
        child: GridView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount:
              state.items.length + (state.isLoading ? crossAxisCount : 0),
          itemBuilder: (context, index) {
            if (index >= state.items.length) {
              return const ShimmerPlaceholder();
            }

            final item = state.items[index];
            final imageUrl = item.posterImageUrl;
            final itemTitle = item.title;
            final uniqueTag =
                'view_all_${widget.category.name}_${item.id}_$index';
            final mediaType = item.mediaType;

            return RepaintBoundary(child: CardsWrapper(
              onTap: () {
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
              },
              borderRadius: BorderRadius.circular(12),
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
                          memCacheWidth: 350,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (context, url) =>
                              const ShimmerPlaceholder(),
                          errorWidget: (_, _, _) =>
                              const ThumbnailErrorPlaceholder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    itemTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ));
          },
        ),
      ),
    );
  }
}

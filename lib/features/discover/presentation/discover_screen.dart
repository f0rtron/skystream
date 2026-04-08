import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/cards_wrapper.dart';
import '../data/tmdb_provider.dart';
import 'view_all_screen.dart';
import 'widgets/discover_carousel.dart';
import 'widgets/media_horizontal_list.dart';
import 'widgets/unified_filter_dialog.dart';
import '../data/filter_provider.dart';
import 'delegates/discover_search_delegate.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../l10n/generated/app_localizations.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with AutomaticKeepAliveClientMixin {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _isScrolledNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> _appBarOpacityNotifier = ValueNotifier<double>(0);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset * 0.8;
    final opacity = (offset / 300).clamp(0.0, 1.0);
    if (opacity != _appBarOpacityNotifier.value) {
      _appBarOpacityNotifier.value = opacity;
    }
    final isScrolled = _scrollController.offset > 200;
    if (isScrolled != _isScrolledNotifier.value) {
      _isScrolledNotifier.value = isScrolled;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isScrolledNotifier.dispose();
    _appBarOpacityNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return ValueListenableBuilder<bool>(
      valueListenable: _isScrolledNotifier,
      builder: (context, isScrolled, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final overlayStyle = isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark;

        return Scaffold(
          backgroundColor: Theme.of(
            context,
          ).scaffoldBackgroundColor, // Base background
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            systemOverlayStyle: overlayStyle,
            forceMaterialTransparency: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: ValueListenableBuilder<double>(
              valueListenable: _appBarOpacityNotifier,
              builder: (context, opacity, child) {
                return Opacity(
                  opacity: opacity,
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                );
              },
            ),
            title: Text(
              AppLocalizations.of(context)!.discover,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 24,
              ),
            ),
            centerTitle: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(
                  right: LayoutConstants.spacingXs,
                ),
                child: CardsWrapper(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const UnifiedFilterDialog(),
                    );
                  },
                  borderRadius: BorderRadius.circular(50),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final filters = ref.watch(
                        discoverFilterProvider,
                      ); // Updated
                      // Language exclusion: Only highlight for content filters
                      final hasActiveFilter =
                          filters.selectedGenre != null ||
                          filters.selectedYear != null ||
                          filters.minRating != null;

                      return CircleAvatar(
                        backgroundColor: hasActiveFilter
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.1),
                        radius: 18,
                        child: Icon(
                          Icons.tune,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 18,
                        ),
                      );
                    },
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(
                  right: LayoutConstants.spacingMd,
                ),
                child: CardsWrapper(
                  onTap: () {
                    showSearch(
                      context: context,
                      delegate: DiscoverSearchDelegate(),
                      useRootNavigator: false,
                      maintainState: true,
                    );
                  },
                  borderRadius: BorderRadius.circular(50),
                  child: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    radius: 18,
                    child: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Consumer(
                  builder: (context, ref, _) {
                    final heroMoviesAsync = ref.watch(
                      discoverHeroMovieProvider,
                    );
                    return heroMoviesAsync.when(
                      skipLoadingOnReload: false,
                      skipLoadingOnRefresh: false,
                      data: (movies) {
                        if (movies.isEmpty) return const SizedBox.shrink();
                        return DiscoverCarousel(
                          movies: movies,
                          scrollController: _scrollController,
                        );
                      },
                      loading: () => Padding(
                        padding: const EdgeInsets.only(
                          bottom: LayoutConstants.spacingLg,
                        ),
                        child: SizedBox(
                          height: 500,
                          width: double.infinity,
                          child: ShimmerPlaceholder(borderRadius: 12),
                        ),
                      ),
                      error: (err, stack) => Container(
                        height: 500,
                        margin: const EdgeInsets.only(
                          bottom: LayoutConstants.spacingLg,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                AppLocalizations.of(context)!.couldNotLoadTrending,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () =>
                                    ref.invalidate(discoverHeroMovieProvider),
                                icon: const Icon(Icons.refresh),
                                label: Text(AppLocalizations.of(context)!.retry),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  popularMoviesProvider,
                  AppLocalizations.of(context)!.popularMovies,
                  ViewAllCategory.popularMovies,
                ),
              ),

              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  popularTVProvider,
                  AppLocalizations.of(context)!.popularTVShows,
                  ViewAllCategory.popularTV,
                ),
              ),

              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  nowPlayingMoviesProvider,
                  AppLocalizations.of(context)!.newMovies,
                  ViewAllCategory.nowPlayingMovies,
                ),
              ),

              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  onTheAirTVProvider,
                  AppLocalizations.of(context)!.newTVShows,
                  ViewAllCategory.onTheAirTV,
                ),
              ),

              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  topRatedMoviesProvider,
                  AppLocalizations.of(context)!.featuredMovies,
                  ViewAllCategory.topRatedMovies,
                ),
              ),

              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  topRatedTVProvider,
                  AppLocalizations.of(context)!.featuredTVShows,
                  ViewAllCategory.topRatedTV,
                ),
              ),

              SliverToBoxAdapter(
                child: _buildSection(
                  context,
                  airingTodayTVProvider,
                  AppLocalizations.of(context)!.lastVideosTVShows,
                  ViewAllCategory.airingTodayTV,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    FutureProvider<List<MultimediaItem>> provider,
    String title,
    ViewAllCategory category,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final asyncValue = ref.watch(provider);
        return asyncValue.when(
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            return MediaHorizontalList(
              title: title,
              mediaList: items,
              category: category,
              heroTagPrefix: 'discover',
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(
              vertical: LayoutConstants.spacingMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title Placeholder
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LayoutConstants.spacingMd,
                  ),
                  child: ShimmerPlaceholder.rectangular(
                    width: 150,
                    height: 24,
                    borderRadius: 4,
                  ),
                ),
                const SizedBox(height: LayoutConstants.spacingMd),
                // List Placeholder
                SizedBox(
                  height: 250,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: LayoutConstants.spacingSm),
                    itemBuilder: (context, index) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerPlaceholder.rectangular(
                            width: 130, // mobile width
                            height: 195,
                            borderRadius: 12,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          error: (e, _) => const SizedBox.shrink(),
        );
      },
    );
  }
}

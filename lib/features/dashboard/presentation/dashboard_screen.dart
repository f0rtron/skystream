import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/tmdb_provider.dart';
import 'widgets/dashboard_carousel.dart';
import 'widgets/media_horizontal_list.dart';
import 'widgets/unified_filter_dialog.dart';
import '../data/filter_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late ScrollController _scrollController;
  final ValueNotifier<bool> _isScrolledNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isScrolled =
        _scrollController.offset > 200; // Threshold for status bar switch
    if (isScrolled != _isScrolledNotifier.value) {
      _isScrolledNotifier.value = isScrolled;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isScrolledNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch all providers
    final heroMovieAsync = ref.watch(dashboardHeroMovieProvider);
    final popularMoviesAsync = ref.watch(popularMoviesProvider);
    final popularTVAsync = ref.watch(popularTVProvider);
    final nowPlayingAsync = ref.watch(nowPlayingMoviesProvider);
    final onTheAirTVAsync = ref.watch(onTheAirTVProvider);
    final topRatedMoviesAsync = ref.watch(topRatedMoviesProvider);
    final topRatedTVAsync = ref.watch(topRatedTVProvider);
    final airingTodayTVAsync = ref.watch(airingTodayTVProvider);

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
            flexibleSpace: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, child) {
                double offset = 0;
                if (_scrollController.hasClients) {
                  offset = _scrollController.offset * 0.8;
                }
                // Transition to black over 300 pixels
                final opacity = (offset / 300).clamp(0.0, 1.0);

                return Opacity(
                  opacity: opacity,
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                );
              },
            ),
            title: Text(
              "SkyStream",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            centerTitle: false,
            actions: [
              // Unified Filter Button
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const UnifiedFilterDialog(),
                    );
                  },
                  child: Consumer(
                    builder: (context, ref, _) {
                      final filters = ref.watch(dashboardFilterProvider);
                      // Language exclusion: Only highlight for content filters
                      final hasActiveFilter =
                          filters.selectedGenre != null ||
                          filters.selectedYear != null ||
                          filters.minRating != null;

                      return CircleAvatar(
                        backgroundColor: hasActiveFilter
                            ? Colors.blueAccent
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.1),
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

              // Search Button
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.1),
                  radius: 18,
                  child: IconButton(
                    icon: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () {},
                  ),
                ),
              ),
            ],
          ),
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Hero / Featured Carousel
              SliverToBoxAdapter(
                child: heroMovieAsync.when(
                  data: (movies) {
                    if (movies.isEmpty) return const SizedBox.shrink();
                    return DashboardCarousel(
                      movies: movies,
                      scrollController: _scrollController,
                    );
                  },
                  loading: () => const SizedBox(
                    height: 500,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, stack) => SizedBox(
                    height: 500,
                    child: Center(child: Text('Error: $err')),
                  ),
                ),
              ),

              // Section: Popular Movies
              SliverToBoxAdapter(
                child: _buildSection(popularMoviesAsync, "Popular Movies"),
              ),

              // Section: Popular TV Shows
              SliverToBoxAdapter(
                child: _buildSection(popularTVAsync, "Popular TV Shows"),
              ),

              // Section: New Movies
              SliverToBoxAdapter(
                child: _buildSection(nowPlayingAsync, "New Movies"),
              ),

              // Section: New TV Shows
              SliverToBoxAdapter(
                child: _buildSection(onTheAirTVAsync, "New TV Shows"),
              ),

              // Section: Featured Movies
              SliverToBoxAdapter(
                child: _buildSection(topRatedMoviesAsync, "Featured Movies"),
              ),

              // Section: Featured TV Shows
              SliverToBoxAdapter(
                child: _buildSection(topRatedTVAsync, "Featured TV Shows"),
              ),

              // Section: Airing Today
              SliverToBoxAdapter(
                child: _buildSection(
                  airingTodayTVAsync,
                  "Last videos TV Shows",
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ), // Bottom spacing
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(
    AsyncValue<List<Map<String, dynamic>>> asyncValue,
    String title,
  ) {
    return asyncValue.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return MediaHorizontalList(title: title, mediaList: items);
      },
      loading: () => SizedBox(
        height: 250,
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

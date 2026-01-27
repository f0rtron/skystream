import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/config/tmdb_config.dart';
import '../../../details/presentation/tmdb_movie_details_screen.dart';
import '../../../../shared/widgets/tv_cards_wrapper.dart'; // Import TvCardsWrapper
import '../../../../shared/widgets/shimmer_placeholder.dart';

class DiscoverCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> movies;
  final ScrollController? scrollController;
  final void Function(Map<String, dynamic>)? onTap;

  const DiscoverCarousel({
    super.key,
    required this.movies,
    this.scrollController,
    this.onTap,
  });

  @override
  State<DiscoverCarousel> createState() => _DiscoverCarouselState();
}

class _DiscoverCarouselState extends State<DiscoverCarousel> {
  int _currentIndex = 0;
  final CarouselSliderController _carouselController =
      CarouselSliderController();

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final heroHeight = size.height * 0.60;
    final isDesktop = size.width > 800;

    return SizedBox(
      height: heroHeight,
      child: Stack(
        children: [
          CarouselSlider.builder(
            carouselController: _carouselController,
            itemCount: widget.movies.length,
            options: CarouselOptions(
              height: heroHeight,
              viewportFraction: 1.0,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 15),
              autoPlayAnimationDuration: const Duration(milliseconds: 1000),
              autoPlayCurve: Curves.fastOutSlowIn,
              scrollPhysics: const BouncingScrollPhysics(),
              onPageChanged: (index, reason) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
            itemBuilder: (context, index, realIndex) {
              final movie = widget.movies[index];
              return _buildCarouselItem(context, movie, heroHeight);
            },
          ),

          // Animated Pagination Dots
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.movies.asMap().entries.map((entry) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _currentIndex == entry.key ? 24.0 : 8.0,
                  height: 8.0,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Theme.of(context).colorScheme.onSurface.withValues(
                      alpha: _currentIndex == entry.key
                          ? 0.9
                          : 0.3, // Slightly lower opacity for inactive
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Left Navigation Button
          if (isDesktop)
            AnimatedOpacity(
              opacity:
                  1.0, // Always visible on large screens for TV/desktop nav
              duration: const Duration(milliseconds: 200),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      onPressed: () => _carouselController.previousPage(),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Right Navigation Button
          if (isDesktop)
            AnimatedOpacity(
              opacity:
                  1.0, // Always visible on large screens for TV/desktop nav
              duration: const Duration(milliseconds: 200),
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      onPressed: () => _carouselController.nextPage(),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      icon: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _navigateToDetails(BuildContext context, Map<String, dynamic> movie) {
    // Determine type: 'title' usually implies movie, 'name' implies TV
    // But better to check 'media_type' if available (trending/search provides it),
    // fallback to title check.
    String mediaType =
        movie['media_type'] ?? (movie['title'] != null ? 'movie' : 'tv');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TmdbMovieDetailsScreen(
          movieId: movie['id'],
          mediaType: mediaType,
          heroTag: 'hero_${movie['id']}',
        ),
      ),
    );
  }

  Widget _buildCarouselItem(
    BuildContext context,
    Map<String, dynamic> movie,
    double height,
  ) {
    final posterPath = movie['poster_path'];
    final backdropPath = movie['backdrop_path'] ?? posterPath;
    String imageUrl;
    if (backdropPath != null) {
      if (backdropPath.startsWith('http')) {
        imageUrl = backdropPath;
      } else {
        imageUrl = '${TmdbConfig.backdropSizeUrl}$backdropPath';
      }
    } else {
      imageUrl = 'https://via.placeholder.com/500x750';
    }

    final title = movie['title'] ?? movie['name'] ?? 'Unknown';
    final logoUrl = movie['logo_url'];

    // Metadata parsing
    final releaseDate = movie['release_date'] ?? movie['first_air_date'] ?? '';
    final year = releaseDate.isNotEmpty ? releaseDate.split('-')[0] : '';
    final isMovie = movie['title'] != null;

    String? type;
    if (movie['media_type'] == 'movie') {
      type = "Movie";
    } else if (movie['media_type'] == 'tv') {
      type = "TV Show";
    }
    // If media_type is null or unknown, type remains null

    final genres = movie['genres_str'] as String? ?? '';

    final metadata = [
      if (type != null) type,
      if (genres.isNotEmpty) genres,
      if (year.isNotEmpty) year,
    ].join(' • ');

    // Use a locally scoped AnimatedBuilder if controller exists
    if (widget.scrollController == null) {
      return _buildStaticItem(
        context,
        imageUrl,
        logoUrl,
        title,
        isMovie,
        metadata,
        height,
        movie,
      );
    }

    return TvCardsWrapper(
      onTap: () {
        if (widget.onTap != null) {
          widget.onTap!(movie);
        } else {
          _navigateToDetails(context, movie);
        }
      },
      borderRadius: BorderRadius.zero,
      child: AnimatedBuilder(
        animation: widget.scrollController!,
        builder: (context, child) {
          double scrollOffset = 0.0;
          if (widget.scrollController!.hasClients) {
            scrollOffset = widget.scrollController!.offset;
          }

          // Parallax effect: Background moves slower than foreground
          final parallaxOffset = scrollOffset * 0.1;

          // Content effect: Slide up faster and fade out
          final contentOffset = -scrollOffset * 0.2;
          final opacity = (1.0 - (scrollOffset / (height * 0.5))).clamp(
            0.0,
            1.0,
          );

          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Parallax Background
                Transform.translate(
                  offset: Offset(0, parallaxOffset),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    height: height,
                    width: double.infinity,
                    memCacheWidth:
                        1080, // High enough for quality, constrained for memory
                    placeholder: (context, url) => const ShimmerPlaceholder(),
                    errorWidget: (context, url, error) =>
                        Container(color: Colors.black),
                  ),
                ),

                // 2. Static Gradient
                // Transform.translate(
                //   offset: Offset(0, -1),
                //   child: Container(
                //     decoration: BoxDecoration(
                //       gradient: LinearGradient(
                //         begin: Alignment.topCenter,
                //         end: Alignment.bottomCenter,
                //         colors: [
                //           Theme.of(
                //             context,
                //           ).scaffoldBackgroundColor.withOpacity(0.9),
                //           Theme.of(
                //             context,
                //           ).scaffoldBackgroundColor.withOpacity(0.7),
                //           Theme.of(
                //             context,
                //           ).scaffoldBackgroundColor.withOpacity(0.5),
                //           Theme.of(
                //             context,
                //           ).scaffoldBackgroundColor.withOpacity(0.0),
                //           Theme.of(context).scaffoldBackgroundColor,
                //         ],
                //         stops: const [0.0, 0.1, 0.2, 0.3, 1],
                //       ),
                //     ),
                //   ),
                // ),
                Transform.translate(
                  offset: Offset(0, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          // Theme.of(
                          //   context,
                          // ).scaffoldBackgroundColor.withOpacity(0.1),
                          // Theme.of(
                          //   context,
                          // ).scaffoldBackgroundColor.withOpacity(0.05),
                          // Theme.of(
                          //   context,
                          // ).scaffoldBackgroundColor.withOpacity(0.01),
                          // Theme.of(
                          //   context,
                          // ).scaffoldBackgroundColor.withOpacity(0.0),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.0),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.4),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.8),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.9),
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                        stops: const [
                          // 0.0,
                          // 0.05,
                          // 0.07,
                          // 0.3,
                          0.6,
                          0.7,
                          0.8,
                          0.9,
                          1.0,
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Animated Content
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 50,
                  child: Transform.translate(
                    offset: Offset(0, contentOffset),
                    child: Opacity(
                      opacity: opacity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo or Title Fallback
                          if (logoUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: _buildLogo(logoUrl, title),
                            )
                          else
                            _buildTitleFallback(title),

                          // Metadata Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (type != null) ...[
                                Icon(
                                  isMovie ? Icons.movie_outlined : Icons.tv,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  metadata,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    shadows: [
                                      if (Theme.of(context).brightness ==
                                          Brightness.dark)
                                        const Shadow(
                                          color: Colors.black,
                                          blurRadius: 4,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStaticItem(
    BuildContext context,
    String imageUrl,
    String? logoUrl,
    String title,
    bool isMovie,
    String metadata,
    double height,
    Map<String, dynamic> movie,
  ) {
    return TvCardsWrapper(
      onTap: () {
        if (widget.onTap != null) {
          // Need to access widget.onTap but this method is in state, so it works.
          widget.onTap!(movie);
        } else {
          _navigateToDetails(context, movie);
        }
      },
      borderRadius: BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            height: height,
            width: double.infinity,
            memCacheWidth: 1080,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(
                    context,
                  ).scaffoldBackgroundColor.withValues(alpha: 0.0),
                  Theme.of(
                    context,
                  ).scaffoldBackgroundColor.withValues(alpha: 0.0),
                  Theme.of(
                    context,
                  ).scaffoldBackgroundColor.withValues(alpha: 0.9),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
                stops: const [0.0, 0.4, 0.85, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 30, // Adjusted from 50
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logoUrl != null)
                  _buildLogo(logoUrl, title)
                else
                  _buildTitleFallback(title),
                Text(
                  metadata,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(String logoUrl, String title) {
    if (logoUrl.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        logoUrl,
        height: 140,
        width: 300,
        fit: BoxFit.contain,
        placeholderBuilder: (context) =>
            const SizedBox(height: 140, width: 300),
      );
    }
    return CachedNetworkImage(
      imageUrl: logoUrl,
      height: 140,
      width: 300,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      memCacheWidth: 300, // P19: Optimize memory
      placeholder: (context, url) => const SizedBox(height: 140, width: 300),
      errorWidget: (context, url, error) => _buildTitleFallback(title),
    );
  }

  Widget _buildTitleFallback(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 40,
          fontFamily: 'RobotoCondensed',
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          shadows: [
            if (Theme.of(context).brightness == Brightness.dark)
              const Shadow(color: Colors.black, blurRadius: 10),
          ],
        ),
      ),
    );
  }
}

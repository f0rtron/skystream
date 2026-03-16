import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../details/presentation/tmdb_movie_details_screen.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../../core/domain/entity/multimedia_item.dart';

class DiscoverCarousel extends StatefulWidget {
  final List<MultimediaItem> movies;
  final ScrollController? scrollController;
  final void Function(MultimediaItem)? onTap;

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
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier<int>(0);
  final CarouselSliderController _carouselController =
      CarouselSliderController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onParentScroll);
  }

  void _onParentScroll() {
    if (widget.scrollController!.hasClients) {
      _scrollOffset.value = widget.scrollController!.offset;
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onParentScroll);
    _scrollOffset.dispose();
    _currentIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final heroHeight = size.height * 0.60;
    final isDesktop =
        size.width > LayoutConstants.discoverCarouselDesktopBreakpoint;

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
                _currentIndexNotifier.value = index;
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
            child: ValueListenableBuilder<int>(
              valueListenable: _currentIndexNotifier,
              builder: (context, currentIndex, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: widget.movies.asMap().entries.map((entry) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: currentIndex == entry.key ? 24.0 : 8.0,
                      height: 8.0,
                      margin: const EdgeInsets.symmetric(horizontal: 4.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(
                              alpha: currentIndex == entry.key ? 0.9 : 0.3,
                            ),
                      ),
                    );
                  }).toList(),
                );
              },
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
                        padding: const EdgeInsets.all(
                          LayoutConstants.spacingMd,
                        ),
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
                        padding: const EdgeInsets.all(
                          LayoutConstants.spacingMd,
                        ),
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

  void _navigateToDetails(BuildContext context, MultimediaItem movie) {
    // Determine type: 'title' usually implies movie, 'name' implies TV
    // But better to check 'media_type' if available (trending/search provides it),
    // fallback to title check.
    final String mediaType = movie.mediaType;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TmdbMovieDetailsScreen(
          movieId: movie.id,
          mediaType: mediaType,
          heroTag: 'hero_${movie.id}',
        ),
      ),
    );
  }

  Widget _buildCarouselItem(
    BuildContext context,
    MultimediaItem movie,
    double height,
  ) {
    final imageUrl = movie.backdropImageUrl;
    final title = movie.title;
    final logoUrl = movie.logoUrl;
    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;

    // Metadata parsing
    final year = movie.year?.toString() ?? '';
    final genres = movie.tags?.join(' • ') ?? '';
    final provider = movie.provider;

    String? type;
    final mType = movie.mediaType.toLowerCase();

    if (mType == 'movie') {
      type = "Movie";
    } else if (mType == 'series' || mType == 'tv') {
      type = "TV Show";
    } else if (mType == 'anime') {
      type = "Anime";
    } else if (mType == 'livestream') {
      type = "Live Stream";
    } else {
      type = mType.isNotEmpty
          ? mType[0].toUpperCase() + mType.substring(1)
          : null;
    }

    final metadata = [
      if (provider != null && provider.isNotEmpty) provider,
      type,
      if (genres.isNotEmpty) genres,
      if (year.isNotEmpty) year,
    ].whereType<String>().join(' • ');

    // Use a locally scoped AnimatedBuilder if controller exists
    if (widget.scrollController == null) {
      return _buildStaticItem(
        context,
        imageUrl,
        logoUrl,
        title,
        metadata,
        height,
        movie,
      );
    }

    return CardsWrapper(
      onTap: () {
        if (widget.onTap != null) {
          widget.onTap!(movie);
        } else {
          _navigateToDetails(context, movie);
        }
      },
      borderRadius: BorderRadius.zero,
      child: ValueListenableBuilder<double>(
        valueListenable: _scrollOffset,
        builder: (context, scrollOffset, child) {
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
                // 1. Background Image with Parallax
                Transform.translate(
                  offset: Offset(0, parallaxOffset),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    height: height,
                    width: double.infinity,
                    memCacheWidth:
                        1080, // High enough for quality, constrained for memory
                    placeholder: (context, url) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    errorWidget: (_, _, _) => const ThumbnailErrorPlaceholder(),
                  ),
                ),

                // 2. Gradients for readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.1),
                          scaffoldColor.withValues(alpha: 0.8),
                          scaffoldColor,
                        ],
                        stops: const [0.0, 0.4, 0.6, 0.85, 1.0],
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
                              padding: const EdgeInsets.only(
                                bottom: LayoutConstants.spacingLg,
                              ),
                              child: _buildLogo(logoUrl, title),
                            )
                          else
                            _buildTitleFallback(title),

                          // Metadata Row (Premium Layout)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (provider != null &&
                                    provider.isNotEmpty) ...[
                                  _buildMiniBadge(
                                    context,
                                    provider.toUpperCase(),
                                    isProvider: true,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (type != null) ...[
                                  _buildMiniBadge(context, type.toUpperCase()),
                                  const SizedBox(width: 12),
                                ],
                                if (genres.isNotEmpty) ...[
                                  Flexible(
                                    child: Text(
                                      genres,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                if (year.isNotEmpty) ...[
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 10,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    year,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
    String metadata,
    double height,
    MultimediaItem movie,
  ) {
    return CardsWrapper(
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
            placeholder: (context, url) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            errorWidget: (_, _, _) => const ThumbnailErrorPlaceholder(),
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
                  ).scaffoldBackgroundColor.withValues(alpha: 0.8),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
                stops: const [0.5, 0.85, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logoUrl != null)
                  _buildLogo(logoUrl, title)
                else
                  _buildTitleFallback(title),
                const SizedBox(height: 8),
                Text(
                  metadata,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
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
      padding: const EdgeInsets.only(bottom: LayoutConstants.spacingMd),
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

  Widget _buildMiniBadge(
    BuildContext context,
    String label, {
    bool isProvider = false,
  }) {
    final theme = Theme.of(context);
    final color = isProvider
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

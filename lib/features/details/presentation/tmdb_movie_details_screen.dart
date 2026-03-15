import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/tmdb_details.dart';
import 'package:intl/intl.dart';

import 'widgets/provider_search_section.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../data/tmdb_details_provider.dart';
import 'tmdb_details_controller.dart';
import 'widgets/movie_cast_list.dart';
import 'widgets/movie_trailers_carousel.dart';
import 'widgets/movie_production_companies.dart';
import 'widgets/movie_seasons_list.dart';
import 'widgets/tmdb_details_stats_section.dart';
import 'widgets/tmdb_details_desktop_hero.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';

class TmdbMovieDetailsScreen extends ConsumerStatefulWidget {
  final int movieId;
  final String mediaType; // 'movie' or 'tv'
  final String? heroTag;
  final String? placeholderPoster;

  const TmdbMovieDetailsScreen({
    super.key,
    required this.movieId,
    this.mediaType = 'movie',
    this.heroTag,
    this.placeholderPoster,
  });

  @override
  ConsumerState<TmdbMovieDetailsScreen> createState() =>
      _TmdbMovieDetailsScreenState();
}

class _TmdbMovieDetailsScreenState
    extends ConsumerState<TmdbMovieDetailsScreen> {
  bool _isDescriptionExpanded = false;
  late ScrollController _scrollController;
  final ValueNotifier<bool> _showAppBarTitle = ValueNotifier<bool>(false);
  final ValueNotifier<double> _titleOpacity = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _contentOpacity = ValueNotifier<double>(1.0);
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);

  late final ScrollController _castScrollController;
  late final ScrollController _trailerScrollController;

  late final ScrollController _episodeScrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _castScrollController = ScrollController();
    _trailerScrollController = ScrollController();

    _episodeScrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    if (widget.mediaType == 'tv') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(tmdbDetailsControllerProvider(widget.movieId).notifier)
            .fetchEpisodes(1);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _castScrollController.dispose();
    _trailerScrollController.dispose();

    _episodeScrollController.dispose();
    _showAppBarTitle.dispose();
    _titleOpacity.dispose();
    _contentOpacity.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;

    final show = offset > 450;
    if (show != _showAppBarTitle.value) {
      _showAppBarTitle.value = show;
    }

    final newTitleOpacity = ((offset - 300) / 100).clamp(0.0, 1.0);
    if (newTitleOpacity != _titleOpacity.value) {
      _titleOpacity.value = newTitleOpacity;
    }

    final newContentOpacity = (1.0 - (offset / 300)).clamp(0.0, 1.0);
    if (newContentOpacity != _contentOpacity.value) {
      _contentOpacity.value = newContentOpacity;
    }

    _scrollOffset.value = offset;
  }

  @override
  Widget build(BuildContext context) {
    final params = MovieDetailsParams(widget.movieId, widget.mediaType);
    final detailsAsync = ref.watch(movieDetailsProvider(params));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: detailsAsync.when(
        data: (data) {
          if (data == null) {
            return Center(
              child: Text(
                "Content not found",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            );
          }
          if (context.isDesktop) {
            return _buildDesktopLayout(data);
          }
          return _buildMobileLayout(data);
        },
        loading: () => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: const BackButton(),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: const BackButton(),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Failed to load content",
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.refresh(movieDetailsProvider(params)),
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(TmdbDetails data) {
    final isMovie = widget.mediaType == 'movie';
    final seasons = data.seasons;
    final cast = data.cast;
    final trailers = data.trailers;
    final productionCompanies = data.productionCompanies;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scaffoldColor = theme.scaffoldBackgroundColor;
    final textColor = theme.colorScheme.onSurface;
    final textSecondary = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Scaffold(
      backgroundColor: scaffoldColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: isDark ? Colors.black45 : Colors.white54,
            foregroundColor: textColor,
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: TmdbDetailsDesktopHero(
        data: data,
        isMovie: isMovie,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            if (!isMovie) ...[
              MovieSeasonsList(
                movieId: widget.movieId,
                seasons: seasons,
                textColor: textColor,
              ),
            ],
            if (cast.isNotEmpty) ...[
              MovieCastList(
                cast: cast,
                textColor: textColor,
                textSecondary: textSecondary,
              ),
            ],
            if (trailers.isNotEmpty) ...[
              MovieTrailersCarousel(
                trailers: trailers,
                textColor: textColor,
              ),
            ],
            if (productionCompanies.isNotEmpty) ...[
              MovieProductionCompanies(
                productionCompanies: productionCompanies,
                textColor: textColor,
                textSecondary: textSecondary,
              ),
            ],
            TmdbDetailsStatsSection(data: data, isMovie: isMovie),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(TmdbDetails data) {
    final isMovie = widget.mediaType == 'movie';

    final backdropImageUrl = data.backdropImageUrl;
    final title = data.title;
    final overview = data.overview;

    final tagline = data.tagline;
    final runtime = data.runtime;
    final releaseDate = data.releaseDateFull;
    final status = data.status;
    final budget = data.budget;
    final genres = data.genres;
    final cast = data.cast;
    final productionCompanies = data.productionCompanies;
    final trailers = data.trailers;

    final hours = runtime ~/ 60;
    final minutes = runtime % 60;
    final durationText = hours > 0 ? '${hours}H ${minutes}M' : '${minutes}M';
    final year = releaseDate.isNotEmpty ? releaseDate.split('-')[0] : '';
    final rating = data.voteAverage.toStringAsFixed(1);

    final certification = data.certification;
    final director = data.director;
    final logoUrl = data.logoUrl;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverAppBar(
          expandedHeight: 550,
          pinned: true,
          backgroundColor: Theme.of(
            context,
          ).scaffoldBackgroundColor, // Theme aware
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.1),
              radius: 18,
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          title: ValueListenableBuilder<double>(
            valueListenable: _titleOpacity,
            builder: (context, opacity, child) {
              if (opacity <= 0) return const SizedBox.shrink();
              return Opacity(
                opacity: opacity,
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: 1.0,
                  ),
                ),
              );
            },
          ),
          centerTitle: false,
          flexibleSpace: FlexibleSpaceBar(
            background: ValueListenableBuilder<double>(
              valueListenable: _scrollOffset,
              builder: (context, offset, child) {
                final contentOffset = -offset * 0.4;
                final parallaxOffset = -offset * 0.1;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      offset: Offset(0, parallaxOffset),
                      child: CachedNetworkImage(
                        imageUrl: backdropImageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                        ),
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
                            Theme.of(context).scaffoldBackgroundColor
                                .withValues(alpha: 0.0),
                            Theme.of(
                              context,
                            ).scaffoldBackgroundColor.withValues(alpha: 0.0),
                            Theme.of(context).scaffoldBackgroundColor
                                .withValues(alpha: 0.8),
                            Theme.of(context).scaffoldBackgroundColor,
                          ],
                          stops: const [0.0, 0.4, 0.8, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _contentOpacity,
                        builder: (context, opacity, child) {
                          return Transform.translate(
                            offset: Offset(0, contentOffset),
                            child: Opacity(
                              opacity: opacity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (logoUrl != null) ...[
                                    if (logoUrl.toLowerCase().endsWith('.svg'))
                                      SvgPicture.network(
                                        logoUrl,
                                        width: 280,
                                        height: 120,
                                        fit: BoxFit.contain,
                                      )
                                    else
                                      CachedNetworkImage(
                                        imageUrl: logoUrl,
                                        width: 280,
                                        height: 120,
                                        fit: BoxFit.contain,
                                        alignment: Alignment.center,
                                      ),
                                  ] else
                                    Text(
                                      title.toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontSize: 40,
                                        fontFamily: 'RobotoCondensed',
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    genres.isNotEmpty
                                        ? genres.take(3).join(' • ')
                                        : (isMovie ? 'Movie' : 'TV Show'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // 2. Metadata, Synopsis, Cast, Production, Trailers, Details
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source Search (Provider Integration)
                ProviderSearchSection(query: title),
                const SizedBox(height: 24),

                // Metadata Row: [TMDB] MOVIE/TV  2026  1H 56M  [PG-13]
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildTmdbLogo(),
                    _buildTopBadge(context, isMovie ? "MOVIE" : "TV SHOW"),
                    _buildIconInfo(context, Icons.calendar_today_rounded, year),
                    _buildIconInfo(context, Icons.star_rounded, rating, iconColor: const Color(0xFF01B4E4)),
                    if (runtime > 0)
                      _buildIconInfo(context, Icons.timer_outlined, durationText),
                    if (certification.isNotEmpty)
                      _buildBorderedInfo(context, certification),
                    if (!isMovie && data.seasons.isNotEmpty)
                      _buildIconInfo(context, Icons.layers_rounded, "${data.seasons.length} Seasons"),
                  ],
                ),

                const SizedBox(height: 12),

                // Director / Creator
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                    ),
                    children: [
                      TextSpan(
                        text: isMovie ? "Director: " : "Creator: ",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      TextSpan(text: director),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Synopsis with Expansion
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overview,
                        maxLines: _isDescriptionExpanded ? null : 3,
                        overflow: _isDescriptionExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.8),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      if (overview.length > 150)
                        GestureDetector(
                          onTap: () => setState(
                            () => _isDescriptionExpanded =
                                !_isDescriptionExpanded,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              children: [
                                Text(
                                  _isDescriptionExpanded
                                      ? "Show Less"
                                      : "Show More",
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Icon(
                                  _isDescriptionExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Cast Section
                if (cast.isNotEmpty) ...[MovieCastList(cast: cast)],

                // Production Section
                if (productionCompanies.isNotEmpty) ...[
                  MovieProductionCompanies(
                    productionCompanies: productionCompanies,
                  ),
                ],

                // Trailers Section
                if (trailers.isNotEmpty) ...[
                  MovieTrailersCarousel(trailers: trailers),
                ],

                if (!isMovie && data.seasons.isNotEmpty) ...[
                  MovieSeasonsList(
                    movieId: widget.movieId,
                    seasons: data.seasons,
                  ),
                ],

                // Movie Details Table
                Text(
                  isMovie ? "MOVIE DETAILS" : "SHOW DETAILS",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                if (tagline.isNotEmpty)
                  _buildDetailRow("Tagline", "\"$tagline\""),
                _buildDetailRow("Status", status),
                _buildDetailRow(
                  isMovie ? "Release Date" : "First Air Date",
                  DateFormat(
                    'MMMM d, yyyy',
                  ).format(DateTime.parse(releaseDate)),
                ),
                if (budget > 0)
                  _buildDetailRow(
                    "Budget",
                    NumberFormat.currency(
                      symbol: '\$',
                      decimalDigits: 0,
                    ).format(budget),
                  ),
                _buildDetailRow("Origin Country", data.originCountry),
                _buildDetailRow("Original Language", data.originalLanguage),

                const SizedBox(height: 32),

                // Safe Area padding

                // Safe Area padding
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTmdbLogo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF01B4E4), // TMDB Blue
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        "TMDB",
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildTopBadge(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildIconInfo(BuildContext context, IconData icon, String text, {Color? iconColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBorderedInfo(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

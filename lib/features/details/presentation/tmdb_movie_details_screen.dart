import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/tmdb_config.dart';
import '../../../core/services/tmdb_service.dart';
import '../../discover/data/tmdb_provider.dart';
import '../../discover/data/language_provider.dart';
import 'widgets/provider_search_section.dart';
import '../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../shared/widgets/tv_cards_wrapper.dart'; // Import TvCardsWrapper
import '../../../shared/widgets/shimmer_placeholder.dart';

class MovieDetailsParams {
  final int id;
  final String type; // 'movie' or 'tv'
  MovieDetailsParams(this.id, this.type);

  @override
  bool operator ==(Object other) =>
      other is MovieDetailsParams && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}

final movieDetailsProvider =
    FutureProvider.family<Map<String, dynamic>?, MovieDetailsParams>((
      ref,
      params,
    ) async {
      final service = ref.watch(tmdbServiceProvider);
      final language = ref.watch(languageProvider);

      // Wrap in timeout to prevent infinite loading when connection is stale
      // This ensures error UI is shown instead of forever-loading spinner
      try {
        if (params.type == 'tv') {
          return await service
              .getTvDetails(params.id, language: language)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () => throw TimeoutException('Request timed out'),
              );
        } else {
          return await service
              .getMovieDetails(params.id, language: language)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () => throw TimeoutException('Request timed out'),
              );
        }
      } on TimeoutException {
        rethrow; // Let error handler show retry UI
      }
    });

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

  int _selectedSeason = 1;

  Future<Map<String, dynamic>?>? _episodesFuture;
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
        _fetchEpisodes(1);
      });
    }
  }

  void _fetchEpisodes(int season) {
    setState(() {
      _selectedSeason = season;
      _episodesFuture = ref
          .read(tmdbServiceProvider)
          .getTvSeasonDetails(
            widget.movieId,
            season,
            language: ref.read(languageProvider),
          );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _castScrollController.dispose();
    _trailerScrollController.dispose();

    _episodeScrollController.dispose();
    _showAppBarTitle.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 450;
    if (show != _showAppBarTitle.value) {
      _showAppBarTitle.value = show;
    }
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
          if (MediaQuery.of(context).size.width > 900) {
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

  Widget _buildDesktopLayout(Map<String, dynamic> data) {
    final isMovie = widget.mediaType == 'movie';
    final backdropPath = data['backdrop_path'];
    var title = data['title'] ?? data['name'] ?? '';
    var overview = data['overview'] ?? '';

    // Use English translation if available to avoid empty fields
    if (data['translations'] != null) {
      final translations = List<Map<String, dynamic>>.from(
        data['translations']['translations'] ?? [],
      );
      final enTrans = translations.firstWhere(
        (t) => t['iso_639_1'] == 'en',
        orElse: () => {},
      );
      if (enTrans.isNotEmpty && enTrans['data'] != null) {
        final enTitle = enTrans['data']['title'] ?? enTrans['data']['name'];
        if (enTitle != null && enTitle.toString().isNotEmpty) {
          title = enTitle;
        }
        final enOverview = enTrans['data']['overview'];
        if (enOverview != null && enOverview.toString().isNotEmpty) {
          overview = enOverview;
        }
      }
    }

    final runtime = isMovie
        ? (data['runtime'] ?? 0)
        : ((data['episode_run_time'] as List?)?.isNotEmpty == true
              ? data['episode_run_time'][0]
              : 0);
    final hours = runtime ~/ 60;
    final minutes = runtime % 60;
    final durationText = hours > 0 ? '${hours}H ${minutes}M' : '${minutes}M';

    final releaseDate = isMovie
        ? (data['release_date'] ?? '')
        : (data['first_air_date'] ?? '');
    final year = releaseDate.isNotEmpty ? releaseDate.split('-')[0] : '';
    final rating = (data['vote_average'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final genres = List<Map<String, dynamic>>.from(data['genres'] ?? []);
    final genreText = genres.map((g) => g['name']).join(' | ');

    // Determine Certification
    String certification = isMovie ? "PG-13" : "TV-14";
    if (isMovie) {
      final releaseDates = data['release_dates'] != null
          ? data['release_dates']['results'] as List
          : [];
      if (releaseDates.isNotEmpty) {
        final usRelease = releaseDates.firstWhere(
          (r) => r['iso_3166_1'] == 'US',
          orElse: () => null,
        );
        if (usRelease != null) {
          final certs = usRelease['release_dates'] as List;
          if (certs.isNotEmpty && certs.first['certification'] != '') {
            certification = certs.first['certification'];
          }
        }
      }
    } else {
      final contentRatings = data['content_ratings'] != null
          ? data['content_ratings']['results'] as List
          : [];
      if (contentRatings.isNotEmpty) {
        final usRating = contentRatings.firstWhere(
          (r) => r['iso_3166_1'] == 'US',
          orElse: () => null,
        );
        if (usRating != null) certification = usRating['rating'];
      }
    }

    final seasons = !isMovie
        ? List<Map<String, dynamic>>.from(data['seasons'] ?? [])
        : [];
    final credits = data['credits'] ?? {};
    final cast = List<Map<String, dynamic>>.from(credits['cast'] ?? []);

    // Find Director / Creator
    String director = "Unknown";
    final crew = List<Map<String, dynamic>>.from(credits['crew'] ?? []);
    if (isMovie) {
      final dir = crew.firstWhere(
        (m) => m['job'] == 'Director',
        orElse: () => {'name': 'Unknown'},
      );
      director = dir['name'];
    } else {
      final creators = data['created_by'] as List?;
      if (creators != null && creators.isNotEmpty) {
        director = creators.map((c) => c['name']).join(', ');
      }
    }
    // Logo
    String? logoUrl;
    final images = data['images'];
    if (images != null) {
      final logos = List<Map<String, dynamic>>.from(images['logos'] ?? []);
      final language = ref.read(languageProvider);
      logoUrl = TmdbService.pickBestLogo(logos, language);
    }

    final videos = List<Map<String, dynamic>>.from(
      data['videos'] != null ? data['videos']['results'] : [],
    );
    final trailers = videos
        .where(
          (v) =>
              v['site'] == 'YouTube' &&
              (v['type'] == 'Trailer' || v['type'] == 'Teaser'),
        )
        .toList();
    final productionCompanies = List<Map<String, dynamic>>.from(
      data['production_companies'] ?? [],
    );
    final status = data['status'] ?? 'Unknown';
    final budget = data['budget'] ?? 0;
    final revenue = data['revenue'] ?? 0;
    final tagline = data['tagline'] ?? '';
    final originCountry = (data['origin_country'] as List?)?.join(', ') ?? 'US';
    final originalLanguage =
        (data['original_language'] as String?)?.toUpperCase() ?? 'EN';
    final releaseDateFull = isMovie
        ? (data['release_date'] ?? '')
        : (data['first_air_date'] ?? '');

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scaffoldColor = theme.scaffoldBackgroundColor;
    final textColor = theme.colorScheme.onSurface;
    final textSecondary = theme.colorScheme.onSurface.withOpacity(0.7);

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (backdropPath != null)
            Positioned.fill(
              child: ShaderMask(
                shaderCallback: (rect) {
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [scaffoldColor, Colors.transparent],
                    stops: const [0.2, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstOut,
                child: CachedNetworkImage(
                  imageUrl: '${TmdbConfig.imageBaseUrl}$backdropPath',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),

          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    scaffoldColor.withOpacity(0.8),
                    scaffoldColor.withOpacity(0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [scaffoldColor, Colors.transparent],
                  stops: const [0.0, 0.4],
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.6, // 60% Width
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (logoUrl != null)
                          CachedNetworkImage(
                            imageUrl: logoUrl,
                            height: 200,
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.contain,
                            // In Light mode, white logos might be invisible.
                            //Ideally we need dark logos for light mode but TMDB API is tricky.
                            // For now, we rely on the fact most logos are colored or white.
                            // If white on white, it fails.
                            // Adding a shadow could help, but let's stick to standard logic first.
                            placeholder: (_, __) => Text(
                              title,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 56,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                          )
                        else
                          Text(
                            title,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Text(
                              year.isNotEmpty ? "$year  •  " : "",
                              style: TextStyle(
                                color: textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              durationText,
                              style: TextStyle(
                                color: textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: textSecondary),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                certification,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF01B4E4), // TMDB Blue
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "TMDB",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              rating,
                              style: const TextStyle(
                                color: Color(0xFF01B4E4),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (director != "Unknown") ...[
                              const SizedBox(width: 12),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: textSecondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Director: $director",
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          overview,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          genreText,
                          style: TextStyle(
                            color: textSecondary.withOpacity(0.5),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Icon(
                              Icons.extension,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Available Sources",
                              style: TextStyle(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "BETA",
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(
                            maxWidth: 600,
                            maxHeight: 220,
                          ),
                          child: ProviderSearchSection(
                            query: title,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60),

                  if (!isMovie) ...[
                    Row(
                      children: [
                        Text(
                          "Episodes",
                          style: TextStyle(
                            color: textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[900] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButton<int>(
                            value: _selectedSeason,
                            dropdownColor: isDark
                                ? Colors.grey[900]
                                : Colors.white,
                            underline: const SizedBox(),
                            style: TextStyle(color: textColor),
                            icon: Icon(Icons.arrow_drop_down, color: textColor),
                            items: seasons.map<DropdownMenuItem<int>>((s) {
                              final num = s['season_number'];
                              final count = s['episode_count'];
                              return DropdownMenuItem(
                                value: num,
                                child: Text("Season $num (${count} Ep)"),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) _fetchEpisodes(val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildDesktopEpisodesList(),
                    const SizedBox(height: 50),
                  ],

                  if (cast.isNotEmpty) ...[
                    Text(
                      "Cast",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 140, // Height for Cast Cards
                      child: DesktopScrollWrapper(
                        controller: _castScrollController,
                        child: ListView.separated(
                          clipBehavior: Clip.none,
                          controller: _castScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: cast.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final actor = cast[index];
                            final p = actor['profile_path'];
                            return TvCardsWrapper(
                              onTap: () {},
                              borderRadius: BorderRadius.circular(40),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 40,
                                    backgroundImage: p != null
                                        ? NetworkImage(
                                            '${TmdbConfig.imageBaseUrl}$p',
                                          )
                                        : null,
                                    child: p == null
                                        ? const Icon(
                                            Icons.person,
                                            color: Colors.grey,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      actor['name'],
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      actor['character'] ?? '',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],

                  if (trailers.isNotEmpty) ...[
                    Text(
                      "Trailers & Clips",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 160,
                      child: DesktopScrollWrapper(
                        controller: _trailerScrollController,
                        child: ListView.separated(
                          clipBehavior: Clip.none,
                          controller: _trailerScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: trailers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final video = trailers[index];
                            final key = video['key'];
                            return TvCardsWrapper(
                              onTap: () {
                                launchUrl(
                                  Uri.parse(
                                    'https://www.youtube.com/watch?v=$key',
                                  ),
                                );
                              },
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: NetworkImage(
                                        'https://img.youtube.com/vi/$key/mqdefault.jpg',
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                    color: Colors.black,
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                  if (productionCompanies.isNotEmpty) ...[
                    Text(
                      "Production",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50, // Reduced for TV
                      child: DesktopScrollWrapper(
                        controller: ScrollController(),
                        child: ListView.separated(
                          clipBehavior: Clip.none,
                          scrollDirection: Axis.horizontal,
                          itemCount: productionCompanies.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 24),
                          itemBuilder: (context, index) {
                            final c = productionCompanies[index];
                            final logo = c['logo_path'];
                            if (logo != null) {
                              return Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: CachedNetworkImage(
                                  imageUrl: '${TmdbConfig.imageBaseUrl}$logo',
                                  height: 20, // Reduced for TV
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) =>
                                      const SizedBox(width: 20, height: 20),
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.error, size: 20),
                                ),
                              );
                            }
                            return Chip(
                              label: Text(c['name']),
                              backgroundColor: textSecondary.withOpacity(0.1),
                              labelStyle: TextStyle(
                                color: textColor,
                                fontSize: 14,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],

                  // 5. Details (Rich Stats)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMovie ? "Movie Details" : "Show Details",
                        style: TextStyle(
                          color: textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (tagline.isNotEmpty) ...[
                        _buildDetailItem(
                          "Tagline",
                          "\"$tagline\"",
                          italic: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Wrap(
                        spacing: 40,
                        runSpacing: 24,
                        children: [
                          _buildDetailItem("Status", status),
                          _buildDetailItem(
                            isMovie ? "Release Date" : "First Air Date",
                            releaseDateFull.isNotEmpty
                                ? DateFormat(
                                    'MMMM d, yyyy',
                                  ).format(DateTime.parse(releaseDateFull))
                                : 'Unknown',
                          ),
                          _buildDetailItem(
                            "Original Language",
                            originalLanguage,
                          ),
                          _buildDetailItem("Origin Country", originCountry),
                          if (budget > 0)
                            _buildDetailItem(
                              "Budget",
                              NumberFormat.currency(
                                symbol: '\$',
                                decimalDigits: 0,
                              ).format(budget),
                            ),
                          if (revenue > 0)
                            _buildDetailItem(
                              "Revenue",
                              NumberFormat.currency(
                                symbol: '\$',
                                decimalDigits: 0,
                              ).format(revenue),
                            ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {bool italic = false}) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final textSecondary = theme.colorScheme.onSurface.withOpacity(0.7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopEpisodesList() {
    if (_episodesFuture == null) return const SizedBox.shrink();
    return FutureBuilder<Map<String, dynamic>?>(
      future: _episodesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 240,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: ShimmerPlaceholder.rectangular(
                      width: 300,
                      height: double.infinity,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        ShimmerPlaceholder.rectangular(width: 150, height: 14),
                        SizedBox(height: 6),
                        ShimmerPlaceholder.rectangular(width: 100, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) return const SizedBox.shrink();
        final episodes = List<Map<String, dynamic>>.from(
          snapshot.data!['episodes'] ?? [],
        );

        return SizedBox(
          height: 240, // Slightly taller for extra metadata
          child: DesktopScrollWrapper(
            controller: _episodeScrollController,
            child: ListView.separated(
              controller: _episodeScrollController,
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              itemCount: episodes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final ep = episodes[index];
                final img = ep['still_path'];
                final voteAverage =
                    (ep['vote_average'] as num?)?.toDouble() ?? 0.0;
                final runtime = ep['runtime'] as int? ?? 0;
                final hours = runtime ~/ 60;
                final minutes = runtime % 60;
                final runtimeText = hours > 0
                    ? '${hours}h ${minutes}m'
                    : '${minutes}m';

                return TvCardsWrapper(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Please select a source from 'Available Sources' above to play.",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 300,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: img != null
                              ? CachedNetworkImage(
                                  imageUrl: '${TmdbConfig.imageBaseUrl}$img',
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                )
                              : const Center(child: ShimmerPlaceholder()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "E${ep['episode_number']} • ${ep['name']}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Rating and Runtime Row
                              Row(
                                children: [
                                  _buildTmdbLogo(),
                                  const SizedBox(width: 8),
                                  Text(
                                    voteAverage.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (runtime > 0)
                                    Text(
                                      runtimeText,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                ep['overview'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout(Map<String, dynamic> data) {
    final isMovie = widget.mediaType == 'movie';

    final backdropPath = data['backdrop_path'];
    var title = data['title'] ?? data['name'] ?? '';
    var overview = data['overview'] ?? '';

    // Check for English translation to fix foreign titles and overviews
    if (data['translations'] != null) {
      final translations = List<Map<String, dynamic>>.from(
        data['translations']['translations'] ?? [],
      );
      final enTrans = translations.firstWhere(
        (t) => t['iso_639_1'] == 'en',
        orElse: () => {},
      );
      if (enTrans.isNotEmpty && enTrans['data'] != null) {
        final enTitle = enTrans['data']['title'] ?? enTrans['data']['name'];
        if (enTitle != null && enTitle.toString().isNotEmpty) {
          title = enTitle;
        }
        final enOverview = enTrans['data']['overview'];
        if (enOverview != null && enOverview.toString().isNotEmpty) {
          overview = enOverview;
        }
      }
    }

    final tagline = data['tagline'] ?? '';
    final runtime = isMovie
        ? (data['runtime'] ?? 0)
        : ((data['episode_run_time'] as List?)?.isNotEmpty == true
              ? data['episode_run_time'][0]
              : 0);
    final releaseDate = isMovie
        ? (data['release_date'] ?? '')
        : (data['first_air_date'] ?? '');
    final status = data['status'] ?? 'Unknown';
    final budget = data['budget'] ?? 0;
    final genres = List<Map<String, dynamic>>.from(data['genres'] ?? []);
    final credits = data['credits'] ?? {};
    final cast = List<Map<String, dynamic>>.from(credits['cast'] ?? []);
    final crew = List<Map<String, dynamic>>.from(credits['crew'] ?? []);
    final productionCompanies = List<Map<String, dynamic>>.from(
      data['production_companies'] ?? [],
    );
    final videos = List<Map<String, dynamic>>.from(
      data['videos'] != null ? data['videos']['results'] : [],
    );

    final hours = runtime ~/ 60;
    final minutes = runtime % 60;
    final durationText = hours > 0 ? '${hours}H ${minutes}M' : '${minutes}M';
    final year = releaseDate.isNotEmpty ? releaseDate.split('-')[0] : '';
    final rating = (data['vote_average'] as num?)?.toStringAsFixed(1) ?? '0.0';

    String certification = isMovie ? "PG-13" : "TV-14";
    if (isMovie) {
      final releaseDates = data['release_dates'] != null
          ? data['release_dates']['results'] as List
          : [];
      if (releaseDates.isNotEmpty) {
        final usRelease = releaseDates.firstWhere(
          (r) => r['iso_3166_1'] == 'US',
          orElse: () => null,
        );
        if (usRelease != null) {
          final certs = usRelease['release_dates'] as List;
          if (certs.isNotEmpty && certs.first['certification'] != '') {
            certification = certs.first['certification'];
          }
        }
      }
    } else {
      final contentRatings = data['content_ratings'] != null
          ? data['content_ratings']['results'] as List
          : [];
      if (contentRatings.isNotEmpty) {
        final usRating = contentRatings.firstWhere(
          (r) => r['iso_3166_1'] == 'US',
          orElse: () => null,
        );
        if (usRating != null) certification = usRating['rating'];
      }
    }

    String director = "Unknown";
    if (isMovie) {
      final dir = crew.firstWhere(
        (m) => m['job'] == 'Director',
        orElse: () => {'name': 'Unknown'},
      );
      director = dir['name'];
    } else {
      final creators = data['created_by'] as List?;
      if (creators != null && creators.isNotEmpty) {
        director = creators.map((c) => c['name']).join(', ');
      }
    }

    String? logoUrl;
    final images = data['images'];
    if (images != null) {
      final logos = List<Map<String, dynamic>>.from(images['logos'] ?? []);
      // Ensure consistent logic with Dashboard
      // We can iterate logos and cast them correctly
      final language = ref.read(languageProvider);
      logoUrl = TmdbService.pickBestLogo(logos, language);
    }

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
              ).colorScheme.onSurface.withOpacity(0.1),
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
          title: AnimatedBuilder(
            animation: _scrollController,
            builder: (context, child) {
              double offset = 0;
              if (_scrollController.hasClients)
                offset = _scrollController.offset;
              // Fade in as the main logo fades out (Main logo fully hidden at 300)
              final double opacity = ((offset - 300) / 100).clamp(0.0, 1.0);

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
            background: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, child) {
                double offset = 0.0;
                if (_scrollController.hasClients) {
                  offset = _scrollController.offset;
                }
                final opacity = (1.0 - (offset / 300)).clamp(0.0, 1.0);
                final contentOffset = -offset * 0.4;
                final parallaxOffset = -offset * 0.1;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Backdrop Image
                    if (backdropPath != null)
                      Transform.translate(
                        offset: Offset(0, parallaxOffset),
                        child: CachedNetworkImage(
                          imageUrl: '${TmdbConfig.imageBaseUrl}$backdropPath',
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),

                    // Gradient Overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(context).scaffoldBackgroundColor
                                .withOpacity(0.0), // Top transparent
                            Theme.of(
                              context,
                            ).scaffoldBackgroundColor.withOpacity(0.0),
                            Theme.of(
                              context,
                            ).scaffoldBackgroundColor.withOpacity(0.8), // Fog
                            Theme.of(
                              context,
                            ).scaffoldBackgroundColor, // Bottom solid
                          ],
                          stops: const [0.0, 0.4, 0.8, 1.0],
                        ),
                      ),
                    ),

                    // Content Overlay (Title, Genre, Buttons) -> CENTERED
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Transform.translate(
                        offset: Offset(0, contentOffset),
                        child: Opacity(
                          opacity: opacity,
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.center, // Centered
                            children: [
                              // Movie Logo or Text Title
                              if (logoUrl != null) ...[
                                if (logoUrl.toLowerCase().endsWith('.svg'))
                                  SvgPicture.network(
                                    logoUrl,
                                    width: 280,
                                    height: 120,
                                    fit: BoxFit.contain,
                                    // If logo is black in light mode, it works. If white, it disappears on white bg.
                                    // However, we fixed logo priority to be Color/PNG.
                                    // If we have a White text logo on White background -> Invisible.
                                    // We might need a shadow or auto-color?
                                    // But usually logos are color.
                                  )
                                else
                                  CachedNetworkImage(
                                    imageUrl: logoUrl,
                                    width: 280,
                                    height: 120,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.center, // Centered
                                  ),
                              ] else
                                Text(
                                  title.toUpperCase(),
                                  textAlign: TextAlign.center, // Centered
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
                              // Genre
                              Text(
                                genres.isNotEmpty
                                    ? genres
                                          .take(3)
                                          .map((g) => g['name'])
                                          .join(' • ')
                                    : (isMovie ? 'Movie' : 'TV Show'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),

                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
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

                // Metadata Row: 2026  1H 56M  [PG-13]
                Row(
                  children: [
                    Text(
                      year,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 20),
                    _buildTmdbLogo(),
                    const SizedBox(width: 8),
                    Text(
                      rating,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 20),
                    if (runtime > 0) ...[
                      Text(
                        durationText,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 20),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        certification,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!isMovie && data['number_of_seasons'] != null) ...[
                      const SizedBox(width: 20),
                      Text(
                        "${data['number_of_seasons']} Seasons",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
                          ).colorScheme.onSurface.withOpacity(0.7),
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
                          ).colorScheme.onSurface.withOpacity(0.8),
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
                if (cast.isNotEmpty) ...[
                  Text(
                    "Cast",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 140,
                    child: ListView.builder(
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount: cast.length,
                      itemBuilder: (context, index) {
                        final member = cast[index];
                        final profilePath = member['profile_path'];
                        return TvCardsWrapper(
                          onTap: () {},
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 90,
                            margin: const EdgeInsets.only(right: 16),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 35,
                                  backgroundColor: Colors.grey[800],
                                  backgroundImage: profilePath != null
                                      ? CachedNetworkImageProvider(
                                          '${TmdbConfig.imageBaseUrl}$profilePath',
                                        )
                                      : null,
                                  child: profilePath == null
                                      ? Text(
                                          member['name'][0],
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  member['name'],
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  member['character'] ?? '',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Production Section
                if (productionCompanies.isNotEmpty) ...[
                  Text(
                    "PRODUCTION",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount: productionCompanies.length,
                      itemBuilder: (context, index) {
                        final company = productionCompanies[index];
                        final logo = company['logo_path'];
                        if (logo == null) {
                          return Container(
                            margin: const EdgeInsets.only(right: 16),
                            child: Chip(
                              label: Text(company['name'] ?? ''),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.1),
                              labelStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }
                        return Container(
                          margin: const EdgeInsets.only(right: 16),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: '${TmdbConfig.imageBaseUrl}$logo',
                            fit: BoxFit.contain,
                            width: 100,
                            placeholder: (_, __) => const SizedBox.shrink(),
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // Trailers Section
                if (videos.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        "Trailers",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Text(
                              "Official Trailers",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 12,
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount: videos.length,
                      itemBuilder: (context, index) {
                        final video = videos[index];
                        final videoKey = video['key'];
                        final thumbUrl =
                            'https://img.youtube.com/vi/$videoKey/0.jpg';
                        return TvCardsWrapper(
                          onTap: () async {
                            final uri = Uri.parse(
                              'https://www.youtube.com/watch?v=$videoKey',
                            );
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          child: Container(
                            width: 200,
                            margin: const EdgeInsets.only(right: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                image: NetworkImage(thumbUrl),
                                fit: BoxFit.cover,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  left: 8,
                                  child: Text(
                                    video['name'] ?? 'Trailer',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // Seasons & Episodes
                if (!isMovie && data['seasons'] != null) ...[
                  // Seasons List
                  Text(
                    "Seasons",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount: (data['seasons'] as List).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final season = (data['seasons'] as List)[index];
                        final posterPath = season['poster_path'];
                        final seasonNum = season['season_number'];
                        final isSelected = _selectedSeason == seasonNum;

                        return TvCardsWrapper(
                          onTap: () => _fetchEpisodes(seasonNum),
                          child: Container(
                            width: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[900],
                              border: isSelected
                                  ? Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: posterPath != null
                                        ? CachedNetworkImage(
                                            imageUrl:
                                                '${TmdbConfig.imageBaseUrl}$posterPath',
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            errorWidget: (_, __, ___) =>
                                                const Icon(Icons.tv),
                                          )
                                        : const Center(child: Icon(Icons.tv)),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    color: isSelected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primary.withOpacity(0.2)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      seasonNum > 0
                                          ? 'Season $seasonNum'
                                          : (season['name'] ?? 'Specials'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Episodes List
                  if (_episodesFuture != null)
                    FutureBuilder<Map<String, dynamic>?>(
                      future: _episodesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError || !snapshot.hasData) {
                          return const SizedBox.shrink();
                        }
                        final episodes = List<Map<String, dynamic>>.from(
                          snapshot.data!['episodes'] ?? [],
                        );
                        if (episodes.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Episodes",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: episodes.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final ep = episodes[index];
                                final epImg = ep['still_path'];
                                final voteAverage =
                                    (ep['vote_average'] as num?)?.toDouble() ??
                                    0.0;
                                final runtime = ep['runtime'] as int? ?? 0;
                                final hours = runtime ~/ 60;
                                final minutes = runtime % 60;
                                final runtimeText = hours > 0
                                    ? '${hours}h ${minutes}m'
                                    : '${minutes}m';

                                return TvCardsWrapper(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Please select a source from 'Available Sources' above to play.",
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 120,
                                          height: 68,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            image: epImg != null
                                                ? DecorationImage(
                                                    image: NetworkImage(
                                                      '${TmdbConfig.imageBaseUrl}$epImg',
                                                    ),
                                                    fit: BoxFit.cover,
                                                  )
                                                : null,
                                            color: Colors.grey[800],
                                          ),
                                          child: epImg == null
                                              ? const Icon(
                                                  Icons.movie,
                                                  color: Colors.white54,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "${ep['episode_number']}. ${ep['name']}",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  _buildTmdbLogo(),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    voteAverage.toStringAsFixed(
                                                      1,
                                                    ),
                                                    style: TextStyle(
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  if (runtime > 0)
                                                    Text(
                                                      runtimeText,
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.7),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                ep['overview'] ?? '',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 32),
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
                _buildDetailRow(
                  "Origin Country",
                  (data['origin_country'] as List?)?.join(', ') ?? 'US',
                ),
                _buildDetailRow(
                  "Original Language",
                  (data['original_language'] as String).toUpperCase(),
                ),

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

  Widget _buildDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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

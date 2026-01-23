import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/tmdb_service.dart';
import 'language_provider.dart';
import 'filter_provider.dart';

final tmdbServiceProvider = Provider<TmdbService>((ref) {
  return TmdbService();
});

final genresProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  return service.getGenres(language: lang);
});

final trendingMoviesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getTrending(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final popularMoviesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getPopularMovies(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final nowPlayingMoviesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getNowPlayingMovies(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final topRatedMoviesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getTopRated(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final popularTVProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getPopularTV(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final topRatedTVProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getTopRatedTV(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final onTheAirTVProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getOnTheAirTV(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final airingTodayTVProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  return service.getAiringTodayTV(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final dashboardHeroMovieProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(dashboardFilterProvider);
  final trending = await service.getTrendingAllDay(
    language: lang,
    genreId: filters.selectedGenre?['id'],
    year: filters.selectedYear,
    minRating: filters.minRating,
  );

  if (trending.isNotEmpty) {
    // Take top 5
    final topMovies = trending
        .take(5)
        .where((m) => m['media_type'] != 'person')
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final service = ref.read(tmdbServiceProvider);

    // Fetch metadata + logos for top 5 (Consistent with Details Screen)
    await Future.wait(
      topMovies.map((movie) async {
        final id = movie['id'];
        final mediaType = movie['media_type'] ?? 'movie';

        // Fetch full details
        final details = mediaType == 'tv'
            ? await service.getTvDetails(id, language: lang)
            : await service.getMovieDetails(id, language: lang);

        if (details != null) {
          movie.addAll(details);

          // 1. Extract Logo from 'images' (via append_to_response)
          if (movie['images'] != null) {
            final logos = List<Map<String, dynamic>>.from(
              movie['images']['logos'] ?? [],
            );
            final logoUrl = TmdbService.pickBestLogo(logos, lang);
            if (logoUrl != null) {
              movie['logo_url'] = logoUrl;
            }
          }

          // 2. Map Genres from details directly
          if (movie['genres'] != null) {
            final genres = List<Map<String, dynamic>>.from(
              movie['genres'],
            ).take(3).map((g) => g['name']).join(' • ');
            movie['genres_str'] = genres;
          }
        }
      }),
    );

    return topMovies;
  }
  return [];
});

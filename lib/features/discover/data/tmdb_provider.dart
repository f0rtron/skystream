import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/tmdb_service.dart';
import 'language_provider.dart';
import 'filter_provider.dart';

import '../../../core/network/dio_client_provider.dart';
import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/models/tmdb_genre.dart';

final tmdbServiceProvider = Provider<TmdbService>((ref) {
  return TmdbService(ref.watch(dioClientProvider));
});

final genresProvider = FutureProvider<List<TmdbGenre>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  return service.getGenres(language: lang);
});

final trendingMoviesProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getTrending(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final popularMoviesProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getPopularMovies(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final nowPlayingMoviesProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getNowPlayingMovies(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final topRatedMoviesProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getTopRated(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final popularTVProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getPopularTV(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final topRatedTVProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getTopRatedTV(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final onTheAirTVProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getOnTheAirTV(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final airingTodayTVProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  return service.getAiringTodayTV(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );
});

final discoverHeroMovieProvider = FutureProvider<List<MultimediaItem>>((ref) async {
  final service = ref.watch(tmdbServiceProvider);
  final lang = ref.watch(languageProvider);
  final filters = ref.watch(discoverFilterProvider);
  final trending = await service.getTrendingAllDay(
    language: lang,
    genreId: filters.selectedGenre?.id,
    year: filters.selectedYear,
    minRating: filters.minRating,
  );

  if (trending.isNotEmpty) {
    final topMovies = trending
        .where((m) => m.mediaType != 'person')
        .take(5)
        .toList();
    final svc = ref.read(tmdbServiceProvider);

    final enriched = await Future.wait(
      topMovies.map((movie) async {
        final details = movie.mediaType == 'tv'
            ? await svc.getTvDetails(movie.id, language: lang)
            : await svc.getMovieDetails(movie.id, language: lang);

        if (details == null) return movie;

        String? logoUrl;
        if (details['images'] != null) {
          final logos = List<Map<String, dynamic>>.from(
            details['images']['logos'] ?? [],
          );
          logoUrl = TmdbService.pickBestLogo(logos, lang);
        }

        String? genresStr;
        if (details['genres'] != null) {
          genresStr = List<Map<String, dynamic>>.from(
            details['genres'],
          ).take(3).map((g) => g['name']).join(' • ');
        }

        return movie.copyWith(
          logoUrl: logoUrl,
          tags: genresStr != null ? [genresStr] : null,
        );
      }),
    );

    return enriched;
  }
  return [];
});



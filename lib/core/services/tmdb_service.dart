import '../domain/entity/multimedia_item.dart';
import 'package:dio/dio.dart';
import '../models/tmdb_genre.dart';
import '../config/tmdb_config.dart';

class TmdbService {
  static final _yearRegex = RegExp(r'\b(19|20)\d{2}\b');
  final Dio _dio;

  TmdbService(Dio baseDio)
    : _dio = Dio(baseDio.options.copyWith(baseUrl: TmdbConfig.baseUrl)) {
    _dio.interceptors.addAll(baseDio.interceptors);
  }

  Future<List<TmdbGenre>> getGenres({String language = 'en-US'}) async {
    final response = await _dio.get(
      '/genre/movie/list',
      queryParameters: {
        'api_key': TmdbConfig.apiKey,
        'language': language,
      }, // Always English per user request
    );
    if (response.statusCode == 200) {
      return (response.data['genres'] as List)
          .map((i) => TmdbGenre.fromJson(i))
          .toList();
    }
    return [];
  }

  /// Shared pattern: use discover endpoint when filters are active, otherwise
  /// fall back to the simpler direct endpoint.
  Future<List<MultimediaItem>> _fetchWithFilterFallback({
    required String discoverPath,
    required String directPath,
    required String sortBy,
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
    Map<String, dynamic>? additionalParams,
  }) async {
    final hasFilters = language != 'en-US' ||
        genreId != null ||
        year != null ||
        minRating != null;
    if (hasFilters) {
      return _getDiscoveryResults(
        discoverPath, language, sortBy,
        genreId: genreId, year: year, minRating: minRating,
        page: page, additionalParams: additionalParams,
      );
    }
    return _getResults(directPath, language: language, page: page);
  }

  Future<List<MultimediaItem>> getTrending({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/movie', directPath: '/trending/all/day',
    sortBy: 'popularity.desc', language: language,
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getPopularMovies({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _getDiscoveryResults(
    '/discover/movie', language, 'popularity.desc',
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getTopRated({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _getDiscoveryResults(
    '/discover/movie', language, 'vote_average.desc',
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getNowPlayingMovies({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) {
    final today = DateTime.now().toString().split(' ')[0];
    final extra = <String, dynamic>{'release_date.lte': today};
    if (genreId != null || year != null || minRating != null || language != 'en-US') {
      return _getDiscoveryResults(
        '/discover/movie', language, 'release_date.desc',
        genreId: genreId, year: year, minRating: minRating,
        page: page, additionalParams: extra,
      );
    }
    return _getResults('/movie/now_playing', language: language, page: page);
  }

  Future<List<MultimediaItem>> getTrendingMovies({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/movie', directPath: '/trending/movie/week',
    sortBy: 'popularity.desc', language: language,
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getTrendingAllDay({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/movie', directPath: '/trending/all/day',
    sortBy: 'popularity.desc', language: language,
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getOnTheAirTV({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/tv', directPath: '/tv/on_the_air',
    sortBy: 'popularity.desc', language: language,
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getPopularTV({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _getDiscoveryResults(
    '/discover/tv', language, 'popularity.desc',
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getTopRatedTV({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _getDiscoveryResults(
    '/discover/tv', language, 'vote_average.desc',
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> getAiringTodayTV({
    String language = 'en-US', int? genreId, int? year,
    double? minRating, int page = 1,
  }) => _fetchWithFilterFallback(
    discoverPath: '/discover/tv', directPath: '/tv/airing_today',
    sortBy: 'first_air_date.desc', language: language,
    genreId: genreId, year: year, minRating: minRating, page: page,
  );

  Future<List<MultimediaItem>> multiSearch({
    required String query,
    String language = 'en-US',
    int page = 1,
  }) async {
    // --- Advanced Search Parsing ---
    String cleanQuery = query;
    int? filterYear;
    String? filterLanguageCode;

    final yearMatch = _yearRegex.firstMatch(cleanQuery);
    if (yearMatch != null) {
      filterYear = int.tryParse(yearMatch.group(0)!);
      // Remove year from query to improve search relevance
      cleanQuery = cleanQuery
          .replaceAll(yearMatch.group(0)!, '')
          .replaceAll('()', '')
          .trim();
    }

    // 2. Extract Language (e.g., "Kannada", "Tamil")
    final languageMap = {
      'kannada': 'kn',
      'tamil': 'ta',
      'telugu': 'te',
      'hindi': 'hi',
      'malayalam': 'ml',
      'english': 'en',
      'korean': 'ko',
      'japanese': 'ja',
    };

    for (final key in languageMap.keys) {
      if (cleanQuery.toLowerCase().contains(key)) {
        filterLanguageCode = languageMap[key];
        // Remove language name using case-insensitive replace
        cleanQuery = cleanQuery
            .replaceAll(RegExp(key, caseSensitive: false), '')
            .trim();
        break; // Assume single language filter
      }
    }

    // If query became empty (e.g. user just typed "2023"), revert to original but keep filters
    if (cleanQuery.isEmpty) cleanQuery = query;

    // Clean up double spaces
    cleanQuery = cleanQuery.replaceAll(RegExp(r'\s+'), ' ');

    final response = await _dio.get(
      '/search/multi',
      queryParameters: {
        'api_key': TmdbConfig.apiKey,
        'language': language,
        'query': cleanQuery,
        'page': page,
        'include_adult': false,
      },
    );

    if (response.statusCode == 200) {
      final rawResults = List<Map<String, dynamic>>.from(
        response.data['results'],
      );

      final List<Map<String, dynamic>> processedResults = [];

      // Process results to handle 'person' type and flatten 'known_for'
      for (final item in rawResults) {
        final mediaType = item['media_type'];

        if (mediaType == 'person') {
          // Hero Search: Extract movies from person's known_for
          if (item['known_for'] != null) {
            final knownFor = List<Map<String, dynamic>>.from(item['known_for']);
            for (final known in knownFor) {
              // known_for items often miss media_type, infer if possible or default to movie
              known['media_type'] ??= 'movie';
              processedResults.add(known);
            }
          }
        } else if (mediaType == 'movie' || mediaType == 'tv') {
          processedResults.add(item);
        }
      }
      final today = DateTime.now();

      final finalResults = processedResults.where((item) {
        final mediaType = item['media_type'];
        if (mediaType != 'movie' && mediaType != 'tv') return false;

        // --- Filter 1: Release Status (Existing logic) ---
        String? dateStr;
        if (mediaType == 'movie') {
          dateStr = item['release_date'];
        } else if (mediaType == 'tv') {
          dateStr = item['first_air_date'];
        }
        if (dateStr == null || dateStr.isEmpty) return false;

        // --- Filter 2: Year (New) ---
        if (filterYear != null) {
          try {
            final date = DateTime.parse(dateStr);
            // Allow +/- 1 year tolerance or exact match
            // Actually strict year match is better for "Mark 2025"
            if (date.year != filterYear) return false;
          } catch (_) {
            return false;
          }
        }

        // --- Filter 3: Language (New) ---
        if (filterLanguageCode != null) {
          final originalLang = item['original_language'];
          if (originalLang != filterLanguageCode) return false;
        }

        // Future date check
        try {
          final date = DateTime.parse(dateStr);
          return date.isBefore(today);
        } catch (e) {
          return false;
        }
      }).toList();

      // Deduplicate results based on ID (Person's known_for might duplicate direct search results)
      final seenParams = <String>{}; // unique key: id + type
      final uniqueResults = <Map<String, dynamic>>[];
      for (final item in finalResults) {
        final key = '${item['id']}_${item['media_type']}';
        if (!seenParams.contains(key)) {
          seenParams.add(key);
          uniqueResults.add(item);
        }
      }

      return uniqueResults.map((i) => MultimediaItem.fromTmdbJson(i)).toList();
    }
    return [];
  }

  Future<List<MultimediaItem>> _getDiscoveryResults(
    String path,
    String fullLanguageCode,
    String sortBy, {
    Map<String, dynamic>? additionalParams,
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    final isoCode = fullLanguageCode.split('-')[0];
    final today = DateTime.now().toString().split(' ')[0];
    final isMovie = path.contains('movie');

    final query = <String, dynamic>{
      'api_key': TmdbConfig.apiKey,
      'language': 'en-US', // Always show titles in English per user request
      'sort_by': sortBy,
      'page': page,
      'include_null_first_air_dates': false,
      'vote_count.gte': 100, // Basic filter to avoid garbage with 1 vote
      // Content Filter: Original Language
      if (fullLanguageCode != 'en-US') 'with_original_language': isoCode,
      // Content Filter: Released Only (Fix for user request)
      if (isMovie) 'release_date.lte': today,
      if (!isMovie) 'first_air_date.lte': today,
      ...?additionalParams,
    };

    // Add nullable filters
    if (genreId != null) query['with_genres'] = genreId;
    if (year != null) {
      query[isMovie ? 'primary_release_year' : 'first_air_date_year'] = year;
    }
    if (minRating != null) query['vote_average.gte'] = minRating;

    final response = await _dio.get(path, queryParameters: query);

    if (response.statusCode == 200) {
      return (response.data['results'] as List)
          .map((i) => MultimediaItem.fromTmdbJson(i as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Helper to reduce boilerplate
  Future<List<MultimediaItem>> _getResults(
    String path, {
    String language = 'en-US',
    int page = 1,
  }) async {
    final response = await _dio.get(
      path,
      queryParameters: {
        'api_key': TmdbConfig.apiKey,
        'language': language,
        'page': page,
      },
    );
    if (response.statusCode == 200) {
      return (response.data['results'] as List)
          .map((i) => MultimediaItem.fromTmdbJson(i as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<String?> getBestLogo(
    int id, {
    String language = 'en',
    String mediaType = 'movie',
  }) async {
    final response = await _dio.get(
      '/$mediaType/$id/images',
      queryParameters: {
        'api_key': TmdbConfig.apiKey,
        'include_image_language': '$language,null,en',
      },
    );

    if (response.statusCode == 200) {
      final data = response.data;
      final logos = List<Map<String, dynamic>>.from(data['logos'] ?? []);
      return pickBestLogo(logos, language);
    }
    return null;
  }

  /// Reusable logic to pick the best logo from a list of TMDB logo objects.
  static String? pickBestLogo(
    List<Map<String, dynamic>> logos,
    String language,
  ) {
    if (logos.isEmpty) return null;

    // Normalize language (e.g., 'en-US' -> 'en')
    final langCode = language.split('-')[0];

    // Helper to find logo matching criteria
    Map<String, dynamic> findLogo(bool Function(Map<String, dynamic>) test) {
      return logos.firstWhere(test, orElse: () => {});
    }

    var bestLogo = <String, dynamic>{};

    // --- Priority 1: Exact Language Match (PNG > SVG) ---
    bestLogo = findLogo(
      (l) =>
          l['iso_639_1'] == langCode &&
          l['file_path'].toString().endsWith('.png'),
    );
    if (bestLogo.isEmpty) {
      bestLogo = findLogo(
        (l) =>
            l['iso_639_1'] == langCode &&
            l['file_path'].toString().endsWith('.svg'),
      );
    }

    // --- Priority 2: English (PNG > SVG) ---
    // Moved above Textless because usually we want a readable title if exact match fails
    if (bestLogo.isEmpty && langCode != 'en') {
      bestLogo = findLogo(
        (l) =>
            l['iso_639_1'] == 'en' &&
            l['file_path'].toString().endsWith('.png'),
      );
    }
    if (bestLogo.isEmpty && langCode != 'en') {
      bestLogo = findLogo(
        (l) =>
            l['iso_639_1'] == 'en' &&
            l['file_path'].toString().endsWith('.svg'),
      );
    }

    // --- Priority 3: International / Textless (iso_639_1 == null) (PNG > SVG) ---
    if (bestLogo.isEmpty) {
      bestLogo = findLogo(
        (l) =>
            l['iso_639_1'] == null &&
            l['file_path'].toString().endsWith('.png'),
      );
    }
    if (bestLogo.isEmpty) {
      bestLogo = findLogo(
        (l) =>
            l['iso_639_1'] == null &&
            l['file_path'].toString().endsWith('.svg'),
      );
    }

    // --- Priority 4: Any Wide PNG ---
    if (bestLogo.isEmpty) {
      bestLogo = findLogo((l) => (l['aspect_ratio'] ?? 0) > 1);
    }

    // --- Fallback ---
    if (bestLogo.isEmpty) {
      bestLogo = logos.first;
    }

    if (bestLogo.isNotEmpty && bestLogo['file_path'] != null) {
      return '${TmdbConfig.imageBaseUrl}${bestLogo['file_path']}';
    }
    return null;
  }

  Future<Map<String, dynamic>?> getMovieDetails(
    int movieId, {
    String language = 'en-US',
  }) async {
    final response = await _dio.get(
      '/movie/$movieId',
      queryParameters: {
        'api_key': TmdbConfig.apiKey,
        'language': language,
        'append_to_response':
            'credits,videos,images,release_dates,translations',
        'include_image_language': '$language,null,en',
      },
    );
    if (response.statusCode == 200) {
      return response.data;
    }
    return null;
  }

  /// Helper to fetch specific credits if not using append_to_response
  Future<Map<String, dynamic>?> getCredits(
    int movieId, {
    String language = 'en-US',
  }) async {
    final response = await _dio.get(
      '/movie/$movieId/credits',
      queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
    );
    if (response.statusCode == 200) {
      return response.data;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getTvDetails(
    int tvId, {
    String language = 'en-US',
  }) async {
    final response = await _dio.get(
      '/tv/$tvId',
      queryParameters: {
        'api_key': TmdbConfig.apiKey,
        'language': language,
        'append_to_response':
            'credits,videos,images,content_ratings,translations',
        'include_image_language': '$language,null,en',
      },
    );
    if (response.statusCode == 200) {
      return response.data;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getTvSeasonDetails(
    int tvId,
    int seasonNumber, {
    String language = 'en-US',
  }) async {
    final response = await _dio.get(
      '/tv/$tvId/season/$seasonNumber',
      queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
    );
    if (response.statusCode == 200) {
      return response.data;
    }
    return null;
  }
}

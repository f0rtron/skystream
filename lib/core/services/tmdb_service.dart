import 'package:dio/dio.dart';
import '../config/tmdb_config.dart';

class TmdbService {
  final Dio _dio;

  TmdbService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: TmdbConfig.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

  Future<List<Map<String, dynamic>>> getGenres({
    String language = 'en-US',
  }) async {
    try {
      final response = await _dio.get(
        '/genre/movie/list',
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': 'en-US',
        }, // Always English per user request
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['genres']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Use discovery endpoint to enforce filters (e.g. valid release dates)
  Future<List<Map<String, dynamic>>> getTrending({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    if (language != 'en-US' ||
        genreId != null ||
        year != null ||
        minRating != null) {
      return _getDiscoveryResults(
        '/discover/movie',
        language,
        'popularity.desc',
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
      );
    }
    return _getResults('/trending/all/day', language: language, page: page);
  }

  Future<List<Map<String, dynamic>>> getPopularMovies({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    return _getDiscoveryResults(
      '/discover/movie',
      language,
      'popularity.desc',
      genreId: genreId,
      year: year,
      minRating: minRating,
      page: page,
    );
  }

  Future<List<Map<String, dynamic>>> getTopRated({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    return _getDiscoveryResults(
      '/discover/movie',
      language,
      'vote_average.desc',
      genreId: genreId,
      year: year,
      minRating: minRating,
      page: page,
    );
  }

  Future<List<Map<String, dynamic>>> getNowPlayingMovies({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    if (genreId != null || year != null || minRating != null) {
      return _getDiscoveryResults(
        '/discover/movie',
        language,
        'release_date.desc',
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
        additionalParams: {
          'release_date.lte': DateTime.now().toString().split(' ')[0],
        },
      );
    }
    // Standard endpoint but filtering language if needed
    if (language != 'en-US') {
      return _getDiscoveryResults(
        '/discover/movie',
        language,
        'release_date.desc',
        page: page,
        additionalParams: {
          'release_date.lte': DateTime.now().toString().split(' ')[0],
        },
      );
    }
    return _getResults('/movie/now_playing', language: language, page: page);
  }

  Future<List<Map<String, dynamic>>> getTrendingMovies({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    if (language != 'en-US' ||
        genreId != null ||
        year != null ||
        minRating != null) {
      return _getDiscoveryResults(
        '/discover/movie',
        language,
        'popularity.desc',
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
      );
    }
    return _getResults('/trending/movie/week', language: language, page: page);
  }

  Future<List<Map<String, dynamic>>> getTrendingAllDay({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    if (language != 'en-US' ||
        genreId != null ||
        year != null ||
        minRating != null) {
      return _getDiscoveryResults(
        '/discover/movie',
        language,
        'popularity.desc',
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
      );
    }
    return _getResults('/trending/all/day', language: language, page: page);
  }

  Future<List<Map<String, dynamic>>> getOnTheAirTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    if (genreId != null ||
        year != null ||
        language != 'en-US' ||
        minRating != null) {
      return _getDiscoveryResults(
        '/discover/tv',
        language,
        'popularity.desc',
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
      );
    }
    return _getResults('/tv/on_the_air', language: language, page: page);
  }

  Future<List<Map<String, dynamic>>> getPopularTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    return _getDiscoveryResults(
      '/discover/tv',
      language,
      'popularity.desc',
      genreId: genreId,
      year: year,
      minRating: minRating,
      page: page,
    );
  }

  Future<List<Map<String, dynamic>>> getTopRatedTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    return _getDiscoveryResults(
      '/discover/tv',
      language,
      'vote_average.desc',
      genreId: genreId,
      year: year,
      minRating: minRating,
      page: page,
    );
  }

  Future<List<Map<String, dynamic>>> getAiringTodayTV({
    String language = 'en-US',
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    if (genreId != null ||
        year != null ||
        language != 'en-US' ||
        minRating != null) {
      return _getDiscoveryResults(
        '/discover/tv',
        language,
        'first_air_date.desc',
        genreId: genreId,
        year: year,
        minRating: minRating,
        page: page,
      );
    }
    return _getResults('/tv/airing_today', language: language, page: page);
  }

  Future<List<Map<String, dynamic>>> multiSearch({
    required String query,
    String language = 'en-US',
    int page = 1,
  }) async {
    try {
      // --- Advanced Search Parsing ---
      String cleanQuery = query;
      int? filterYear;
      String? filterLanguageCode;

      // 1. Extract Year (e.g., "2023", "(2023)")
      // Matches 19xx or 20xx surrounded by word boundaries
      final yearRegex = RegExp(r'\b(19|20)\d{2}\b');
      final yearMatch = yearRegex.firstMatch(cleanQuery);
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
              final knownFor = List<Map<String, dynamic>>.from(
                item['known_for'],
              );
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

        var finalResults = processedResults.where((item) {
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

        return uniqueResults;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getDiscoveryResults(
    String path,
    String fullLanguageCode,
    String sortBy, {
    Map<String, dynamic>? additionalParams,
    int? genreId,
    int? year,
    double? minRating,
    int page = 1,
  }) async {
    try {
      final isoCode = fullLanguageCode.split('-')[0];
      final today = DateTime.now().toString().split(' ')[0];
      final isMovie = path.contains('movie');

      final query = {
        'api_key': TmdbConfig.apiKey,
        'language': 'en-US', // Always show titles in English per user request
        'sort_by': sortBy,
        'page': page,
        'include_null_first_air_dates': false,
        'vote_count.gte': 100, // Basic filter to avoid garbage with 1 vote
        // Content Filter: Original Language
        if (fullLanguageCode != 'en-US') 'with_original_language': isoCode,
        // Content Filter: Genre
        if (genreId != null) 'with_genres': genreId,
        // Content Filter: Year
        if (year != null)
          (isMovie ? 'primary_release_year' : 'first_air_date_year'): year,
        // Content Filter: Rating
        if (minRating != null) 'vote_average.gte': minRating,
        // Content Filter: Released Only (Fix for user request)
        if (isMovie) 'release_date.lte': today,
        if (!isMovie) 'first_air_date.lte': today,
        ...?additionalParams,
      };

      final response = await _dio.get(path, queryParameters: query);

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['results']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Helper to reduce boilerplate
  Future<List<Map<String, dynamic>>> _getResults(
    String path, {
    String language = 'en-US',
    int page = 1,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: {
          'api_key': TmdbConfig.apiKey,
          'language': language,
          'page': page,
        },
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['results']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<String?> getBestLogo(
    int id, {
    String language = 'en',
    String mediaType = 'movie',
  }) async {
    try {
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
    } catch (e) {
      return null;
    }
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
    try {
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
    } catch (e) {
      return null;
    }
  }

  /// Helper to fetch specific credits if not using append_to_response
  Future<Map<String, dynamic>?> getCredits(
    int movieId, {
    String language = 'en-US',
  }) async {
    try {
      final response = await _dio.get(
        '/movie/$movieId/credits',
        queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTvDetails(
    int tvId, {
    String language = 'en-US',
  }) async {
    try {
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
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTvSeasonDetails(
    int tvId,
    int seasonNumber, {
    String language = 'en-US',
  }) async {
    try {
      final response = await _dio.get(
        '/tv/$tvId/season/$seasonNumber',
        queryParameters: {'api_key': TmdbConfig.apiKey, 'language': language},
      );
      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

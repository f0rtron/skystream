import 'package:html_unescape/html_unescape.dart';
import '../domain/entity/multimedia_item.dart';
import '../utils/image_fallbacks.dart';

// Reuse unescape from parent or create local
final _unescape = HtmlUnescape();

class TmdbDetails extends MultimediaItem {
  final int runtime;
  final String certification;
  final String director;
  final List<TmdbSeason> seasons;
  final List<TmdbCast> tmdbCast;
  final List<String> genres;
  final List<TmdbVideo> tmdbTrailers;
  final List<TmdbProductionCompany> productionCompanies;
  final String tmdbStatus;
  final int budget;
  final int revenue;
  final String tagline;
  final String originCountry;
  final String originalLanguage;
  final String releaseDateFull;

  TmdbDetails({
    required int id,
    required String mediaType,
    required super.title,
    String? posterPath,
    String? backdropPath,
    required String releaseDate,
    required double voteAverage,
    required String overview,
    super.logoUrl,
    String? genresStr,
    dynamic sourceItem,
    required this.runtime,
    required this.certification,
    required this.director,
    required this.seasons,
    required this.tmdbCast,
    required this.genres,
    required this.tmdbTrailers,
    required this.productionCompanies,
    required this.tmdbStatus,
    required this.budget,
    required this.revenue,
    required this.tagline,
    required this.originCountry,
    required this.originalLanguage,
    required this.releaseDateFull,
  }) : super(
          url: '', // Resolved via provider
          posterUrl: posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : '',
          bannerUrl: backdropPath != null ? 'https://image.tmdb.org/t/p/original$backdropPath' : null,
          description: overview,
          contentType: MultimediaItem.parseContentType(mediaType),
          tmdbId: id,
          score: voteAverage,
          tags: genresStr?.split(' | '),
        );

  factory TmdbDetails.fromJson(Map<String, dynamic> json, String languageCode) {
    // Determine media type
    final String mType =
        json['media_type'] ?? (json['title'] != null ? 'movie' : 'tv');
    final isMovie = mType == 'movie';

    var title = json['title'] != null || json['name'] != null
        ? _unescape.convert(json['title'] ?? json['name'])
        : 'Unknown';
    var overview = json['overview'] != null
        ? _unescape.convert(json['overview'])
        : '';

    // Use English translation if available to avoid empty fields
    if (json['translations'] != null) {
      final translations = List<Map<String, dynamic>>.from(
        json['translations']['translations'] ?? [],
      );
      final enTrans = translations.firstWhere(
        (t) => t['iso_639_1'] == 'en',
        orElse: () => <String, dynamic>{},
      );
      if (enTrans.isNotEmpty && enTrans['data'] != null) {
        final enTitle = enTrans['data']['title'] ?? enTrans['data']['name'];
        if (enTitle != null && enTitle.toString().isNotEmpty) {
          title = _unescape.convert(enTitle);
        }
        final enOverview = enTrans['data']['overview'];
        if (enOverview != null && enOverview.toString().isNotEmpty) {
          overview = _unescape.convert(enOverview);
        }
      }
    }

    final date = json['release_date'] ?? json['first_air_date'] ?? '';
    final voteAvg = (json['vote_average'] as num?)?.toDouble() ?? 0.0;

    final runtime = isMovie
        ? (json['runtime'] ?? 0)
        : ((json['episode_run_time'] as List?)?.isNotEmpty == true
              ? json['episode_run_time'][0]
              : 0);

    // Determine Certification
    String certification = isMovie ? "PG-13" : "TV-14";
    if (isMovie) {
      final releaseDates = json['release_dates'] != null
          ? json['release_dates']['results'] as List
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
      final contentRatings = json['content_ratings'] != null
          ? json['content_ratings']['results'] as List
          : [];
      if (contentRatings.isNotEmpty) {
        final usRating = contentRatings.firstWhere(
          (r) => r['iso_3166_1'] == 'US',
          orElse: () => null,
        );
        if (usRating != null) certification = usRating['rating'];
      }
    }

    final genresList = List<Map<String, dynamic>>.from(json['genres'] ?? []);
    final genres = genresList.map((g) => g['name'].toString()).toList();
    final genresStr = genres.join(' | ');

    final seasons = !isMovie
        ? List<Map<String, dynamic>>.from(
            json['seasons'] ?? [],
          ).map((s) => TmdbSeason.fromJson(s)).toList()
        : <TmdbSeason>[];

    final credits = json['credits'] ?? {};
    final castList = List<Map<String, dynamic>>.from(credits['cast'] ?? []);
    final cast = castList.map((c) => TmdbCast.fromJson(c)).toList();

    // Find Director / Creator
    String director = "Unknown";
    final crew = List<Map<String, dynamic>>.from(credits['crew'] ?? []);
    if (isMovie) {
      final dir = crew.firstWhere(
        (m) => m['job'] == 'Director',
        orElse: () => <String, dynamic>{'name': 'Unknown'},
      );
      director = dir['name'];
    } else {
      final creators = json['created_by'] as List?;
      if (creators != null && creators.isNotEmpty) {
        director = creators.map((c) => c['name']).join(', ');
      }
    }

    final videos = List<Map<String, dynamic>>.from(
      json['videos'] != null ? json['videos']['results'] : [],
    );
    final tmdbTrailers = videos
        .where(
          (v) =>
              v['site'] == 'YouTube' &&
              (v['type'] == 'Trailer' || v['type'] == 'Teaser'),
        )
        .map((v) => TmdbVideo.fromJson(v))
        .toList();

    final productionCompaniesList = List<Map<String, dynamic>>.from(
      json['production_companies'] ?? [],
    );
    final productionCompanies = productionCompaniesList
        .map((p) => TmdbProductionCompany.fromJson(p))
        .toList();

    final tmdbStatus = json['status'] ?? 'Unknown';
    final budget = json['budget'] as num? ?? 0;
    final revenue = json['revenue'] as num? ?? 0;
    final tagline = json['tagline'] ?? '';
    final originCountry = (json['origin_country'] as List?)?.join(', ') ?? 'US';
    final originalLanguage =
        (json['original_language'] as String?)?.toUpperCase() ?? 'EN';

    return TmdbDetails(
      id: json['id'] as int? ?? 0,
      mediaType: mType,
      title: title,
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      releaseDate: date,
      voteAverage: voteAvg,
      overview: overview,
      logoUrl: json['logo_url'], // Might be populated before/after this
      genresStr: genresStr,
      runtime: (runtime as num).toInt(),
      certification: certification,
      director: director,
      seasons: seasons,
      tmdbCast: cast,
      genres: genres,
      tmdbTrailers: tmdbTrailers,
      productionCompanies: productionCompanies,
      tmdbStatus: tmdbStatus,
      budget: budget.toInt(),
      revenue: revenue.toInt(),
      tagline: tagline,
      originCountry: originCountry,
      originalLanguage: originalLanguage,
      releaseDateFull: date,
    );
  }
}

class TmdbSeason {
  final int seasonNumber;
  final String name;
  final String? posterPath;
  final int episodeCount;
  final String? airDate;

  TmdbSeason({
    required this.seasonNumber,
    required this.name,
    this.posterPath,
    required this.episodeCount,
    this.airDate,
  });

  factory TmdbSeason.fromJson(Map<String, dynamic> json) {
    return TmdbSeason(
      seasonNumber: json['season_number'] ?? 0,
      name: json['name'] != null ? _unescape.convert(json['name']) : '',
      posterPath: json['poster_path'],
      episodeCount: json['episode_count'] ?? 0,
      airDate: json['air_date'],
    );
  }

  String get posterImageUrl =>
      AppImageFallbacks.tmdbPoster(posterPath, label: name);
}

class TmdbCast {
  final String name;
  final String character;
  final String? profilePath;

  TmdbCast({required this.name, required this.character, this.profilePath});

  factory TmdbCast.fromJson(Map<String, dynamic> json) {
    return TmdbCast(
      name: json['name'] != null ? _unescape.convert(json['name']) : 'Unknown',
      character: json['character'] != null
          ? _unescape.convert(json['character'])
          : '',
      profilePath: json['profile_path'],
    );
  }

  String get profileImageUrl =>
      AppImageFallbacks.tmdbProfile(profilePath, label: name);
}

class TmdbVideo {
  final String key;
  final String type;
  final String name;

  TmdbVideo({required this.key, required this.type, required this.name});

  factory TmdbVideo.fromJson(Map<String, dynamic> json) {
    return TmdbVideo(
      key: json['key'] ?? '',
      type: json['type'] ?? '',
      name: json['name'] ?? 'Trailer',
    );
  }
}

class TmdbProductionCompany {
  final String name;
  final String? logoPath;

  TmdbProductionCompany({required this.name, this.logoPath});

  factory TmdbProductionCompany.fromJson(Map<String, dynamic> json) {
    return TmdbProductionCompany(
      name: json['name'] ?? '',
      logoPath: json['logo_path'],
    );
  }

  String get logoImageUrl => AppImageFallbacks.tmdbLogo(logoPath, label: name);
}

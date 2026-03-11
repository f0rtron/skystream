import 'package:html_unescape/html_unescape.dart';
import '../domain/entity/multimedia_item.dart';
import '../utils/image_fallbacks.dart';

class TmdbItem {
  static final _unescape = HtmlUnescape();
  final int id;
  final String mediaType;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final double voteAverage;
  final String overview;
  final String? logoUrl;
  final String? genresStr;
  final MultimediaItem? sourceItem;

  TmdbItem({
    required this.id,
    required this.mediaType,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.releaseDate,
    required this.voteAverage,
    required this.overview,
    this.logoUrl,
    this.genresStr,
    this.sourceItem,
  });

  factory TmdbItem.fromJson(Map<String, dynamic> json) {
    // Determine media type
    final String mType =
        json['media_type'] ?? (json['title'] != null ? 'movie' : 'tv');

    // Extract title (with HTML entity unescaping)
    final String title = _unescape.convert(
      json['title'] ?? json['name'] ?? 'Unknown',
    );

    // Extract date
    final String date = json['release_date'] ?? json['first_air_date'] ?? '';

    // Extract vote average
    final double voteAvg = (json['vote_average'] as num?)?.toDouble() ?? 0.0;

    // Extract overview (with HTML entity unescaping)
    final String overview = _unescape.convert(json['overview'] ?? '');

    return TmdbItem(
      id: json['id'] as int? ?? 0,
      mediaType: mType,
      title: title,
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      releaseDate: date,
      voteAverage: voteAvg,
      overview: overview,
      logoUrl: json['logo_url'],
      genresStr: json['genres_str'],
    );
  }

  TmdbItem copyWith({String? logoUrl, String? genresStr}) {
    return TmdbItem(
      id: id,
      mediaType: mediaType,
      title: title,
      posterPath: posterPath,
      backdropPath: backdropPath,
      releaseDate: releaseDate,
      voteAverage: voteAverage,
      overview: overview,
      logoUrl: logoUrl ?? this.logoUrl,
      genresStr: genresStr ?? this.genresStr,
      sourceItem: sourceItem, // Keep original
    );
  }

  // Convert back to map if needed for backward compatibility temporarily
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'media_type': mediaType,
      'title': title,
      'name': title, // Add both for compatibility
      'poster_path': posterPath,
      'backdrop_path': backdropPath,
      'release_date': releaseDate,
      'first_air_date': releaseDate,
      'vote_average': voteAverage,
      'overview': overview,
    };
  }

  String get posterImageUrl =>
      AppImageFallbacks.tmdbPoster(posterPath, label: title);

  String get thumbnailImageUrl =>
      AppImageFallbacks.tmdbThumbnail(posterPath, label: title);

  String get backdropImageUrl =>
      AppImageFallbacks.tmdbBackdrop(backdropPath ?? posterPath, label: title);
}

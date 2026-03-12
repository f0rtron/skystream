import 'package:html_unescape/html_unescape.dart';

enum MultimediaContentType { movie, series, anime, livestream, other }

class MultimediaItem {
  static final _unescape = HtmlUnescape();
  final String title;
  final String url;

  /// Raw poster URL; apply [AppImageFallbacks.poster] at the UI edge when displaying.
  final String posterUrl;

  /// Raw banner URL; apply [AppImageFallbacks.optional] at the UI edge when displaying.
  final String? bannerUrl;
  final String? description;
  final MultimediaContentType contentType;
  final List<Episode>? episodes;
  final String? provider;
  final Map<String, String>? headers;

  MultimediaItem({
    required this.title,
    required this.url,
    required this.posterUrl,
    this.bannerUrl,
    this.description,
    this.contentType = MultimediaContentType.movie,
    this.episodes,
    this.provider,
    this.headers,
  });

  factory MultimediaItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'] != null ? _unescape.convert(json['title']) : '';

    // Determine content type
    final String? typeStr = json['type'] ?? json['contentType'];
    final MultimediaContentType type = MultimediaItem.parseContentType(typeStr);

    return MultimediaItem(
      title: title,
      url: json['url'] ?? '',
      posterUrl: json['posterUrl'] ?? '',
      bannerUrl: json['backgroundPosterUrl'] ?? json['bannerUrl'],
      description: json['description'] != null
          ? _unescape.convert(json['description'])
          : null,
      contentType: type,
      episodes: json['episodes'] != null
          ? (json['episodes'] as List)
                .map((e) => Episode.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : null,
      provider: json['provider'],
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'])
          : null,
    );
  }

  static MultimediaContentType parseContentType(String? raw) {
    if (raw == null) return MultimediaContentType.movie;
    switch (raw.toLowerCase()) {
      case 'movie':
        return MultimediaContentType.movie;
      case 'series':
      case 'tv':
        return MultimediaContentType.series;
      case 'anime':
        return MultimediaContentType.anime;
      case 'livestream':
      case 'live':
      case 'iptv':
        return MultimediaContentType.livestream;
      default:
        return MultimediaContentType.other;
    }
  }

  MultimediaItem copyWith({
    String? title,
    String? url,
    String? posterUrl,
    String? bannerUrl,
    String? description,
    MultimediaContentType? contentType,
    List<Episode>? episodes,
    String? provider,
    Map<String, String>? headers,
  }) {
    return MultimediaItem(
      title: title ?? this.title,
      url: url ?? this.url,
      posterUrl: posterUrl ?? this.posterUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      description: description ?? this.description,
      contentType: contentType ?? this.contentType,
      episodes: episodes ?? this.episodes,
      provider: provider ?? this.provider,
      headers: headers ?? this.headers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'posterUrl': posterUrl,
      'bannerUrl': bannerUrl,
      'description': description,
      'type': contentType.name,
      'episodes': episodes?.map((e) => e.toJson()).toList(),
      'provider': provider,
      'headers': headers,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultimediaItem &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          title == other.title &&
          posterUrl == other.posterUrl &&
          provider == other.provider;

  @override
  int get hashCode =>
      url.hashCode ^ title.hashCode ^ posterUrl.hashCode ^ (provider?.hashCode ?? 0);
}

class Episode {
  static final _unescape = HtmlUnescape();
  final String name;
  final String url;
  final int season;
  final int episode;
  final String? description;
  final String? posterUrl;
  final Map<String, String>? headers;

  /// Raw poster URL; apply [AppImageFallbacks.poster] at the UI edge when displaying.
  Episode({
    required this.name,
    required this.url,
    this.season = 0,
    this.episode = 0,
    this.description,
    this.posterUrl,
    this.headers,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    final name = json['name'] != null ? _unescape.convert(json['name']) : '';
    return Episode(
      name: name,
      url: json['url'] ?? '',
      season: json['season'] ?? 0,
      episode: json['episode'] ?? 0,
      description: json['description'] != null
          ? _unescape.convert(json['description'])
          : null,
      posterUrl: json['posterUrl'],
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'season': season,
      'episode': episode,
      'description': description,
      'posterUrl': posterUrl,
      'headers': headers,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Episode &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          season == other.season &&
          episode == other.episode;

  @override
  int get hashCode => url.hashCode ^ season.hashCode ^ episode.hashCode;
}

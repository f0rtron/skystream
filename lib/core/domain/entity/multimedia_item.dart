import 'package:html_unescape/html_unescape.dart';

enum MultimediaContentType { movie, series, anime, livestream, other }

enum VpnStatus { none, mightBeNeeded, torrent }

enum ShowStatus { completed, ongoing, upcoming }

enum DubStatus { none, dubbed, subbed }

class Actor {
  final String name;
  final String? image;
  final String? role;
  final Actor? voiceActor;

  Actor({required this.name, this.image, this.role, this.voiceActor});

  factory Actor.fromJson(Map<String, dynamic> json) {
    return Actor(
      name: json['name'] ?? '',
      image: json['image'],
      role: json['role'] ?? json['roleString'],
      voiceActor: json['voiceActor'] != null
          ? Actor.fromJson(Map<String, dynamic>.from(json['voiceActor']))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'image': image,
      'role': role,
      'voiceActor': voiceActor?.toJson(),
    };
  }
}

class Trailer {
  final String url;
  final Map<String, String>? headers;

  Trailer({required this.url, this.headers});

  factory Trailer.fromJson(Map<String, dynamic> json) {
    return Trailer(
      url: json['url'] ?? json['extractorUrl'] ?? '',
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {'url': url, 'headers': headers};
  }
}

class NextAiring {
  final int episode;
  final int unixTime;
  final int? season;

  NextAiring({required this.episode, required this.unixTime, this.season});

  factory NextAiring.fromJson(Map<String, dynamic> json) {
    return NextAiring(
      episode: json['episode'] ?? 0,
      unixTime: json['unixTime'] ?? 0,
      season: json['season'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'episode': episode, 'unixTime': unixTime, 'season': season};
  }
}

class MultimediaItem {
  static final _unescape = HtmlUnescape();
  final String title;
  final String url;
  final String posterUrl;
  final String? bannerUrl;
  final String? logoUrl;
  final String? description;
  final MultimediaContentType contentType;
  final List<Episode>? episodes;
  final String? provider;
  final Map<String, String>? headers;

  // New parity fields
  final int? year;
  final double? score;
  final int? duration;
  final ShowStatus status;
  final List<String>? tags;
  final String? contentRating;
  final List<Actor>? cast;
  final List<Trailer>? trailers;
  final List<MultimediaItem>? recommendations;
  final Map<String, String>? syncData;
  final VpnStatus vpnStatus;
  final bool isAdult;
  final NextAiring? nextAiring;

  MultimediaItem({
    required this.title,
    required this.url,
    required this.posterUrl,
    this.bannerUrl,
    this.logoUrl,
    this.description,
    this.contentType = MultimediaContentType.movie,
    this.episodes,
    this.provider,
    this.headers,
    this.year,
    this.score,
    this.duration,
    this.status = ShowStatus.ongoing,
    this.tags,
    this.contentRating,
    this.cast,
    this.trailers,
    this.recommendations,
    this.syncData,
    this.vpnStatus = VpnStatus.none,
    this.isAdult = false,
    this.nextAiring,
  });

  factory MultimediaItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'] != null ? _unescape.convert(json['title']) : '';

    final String? typeStr = json['type'] ?? json['contentType'];
    final MultimediaContentType type = MultimediaItem.parseContentType(typeStr);

    return MultimediaItem(
      title: title,
      url: json['url'] ?? '',
      posterUrl: json['posterUrl'] ?? '',
      bannerUrl: json['backgroundPosterUrl'] ?? json['bannerUrl'],
      logoUrl: json['logoUrl'],
      description: json['description'] != null
          ? _unescape.convert(json['description'])
          : null,
      contentType: type,
      episodes: json['episodes'] != null
          ? (json['episodes'] as List)
                .map<Episode>(
                  (e) => Episode.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : null,
      provider: json['provider'],
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'])
          : null,
      year: json['year'],
      score: (json['score'] as num?)?.toDouble(),
      duration: json['duration'],
      status: _parseShowStatus(json['status'] ?? json['showStatus']),
      tags: json['tags'] != null ? List<String>.from(json['tags']) : null,
      contentRating: json['contentRating'],
      cast: json['cast'] != null || json['actors'] != null
          ? ((json['cast'] ?? json['actors']) as List)
                .map<Actor>((a) => Actor.fromJson(Map<String, dynamic>.from(a)))
                .toList()
          : null,
      trailers: json['trailers'] != null
          ? (json['trailers'] as List)
                .map<Trailer>(
                  (t) => Trailer.fromJson(Map<String, dynamic>.from(t)),
                )
                .toList()
          : null,
      recommendations: json['recommendations'] != null
          ? (json['recommendations'] as List)
                .map<MultimediaItem>(
                  (r) => MultimediaItem.fromJson(Map<String, dynamic>.from(r)),
                )
                .toList()
          : null,
      syncData: json['syncData'] != null
          ? Map<String, String>.from(json['syncData'])
          : null,
      vpnStatus: _parseVpnStatus(json['vpnStatus']),
      isAdult: json['isAdult'] ?? false,
      nextAiring: json['nextAiring'] != null
          ? NextAiring.fromJson(Map<String, dynamic>.from(json['nextAiring']))
          : null,
    );
  }

  static ShowStatus _parseShowStatus(dynamic raw) {
    if (raw == null) return ShowStatus.ongoing;
    final str = raw.toString().toLowerCase();
    if (str.contains('completed')) return ShowStatus.completed;
    if (str.contains('upcoming') || str.contains('soon'))
      return ShowStatus.upcoming;
    return ShowStatus.ongoing;
  }

  static VpnStatus _parseVpnStatus(dynamic raw) {
    if (raw == null) return VpnStatus.none;
    final str = raw.toString().toLowerCase();
    if (str.contains('needed') || str.contains('might'))
      return VpnStatus.mightBeNeeded;
    if (str.contains('torrent')) return VpnStatus.torrent;
    return VpnStatus.none;
  }

  static MultimediaContentType parseContentType(String? raw) {
    if (raw == null) return MultimediaContentType.movie;
    switch (raw.toLowerCase()) {
      case 'movie':
        return MultimediaContentType.movie;
      case 'series':
      case 'tvseries':
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
    String? logoUrl,
    String? description,
    MultimediaContentType? contentType,
    List<Episode>? episodes,
    String? provider,
    Map<String, String>? headers,
    int? year,
    double? score,
    int? duration,
    ShowStatus? status,
    List<String>? tags,
    String? contentRating,
    List<Actor>? cast,
    List<Trailer>? trailers,
    List<MultimediaItem>? recommendations,
    Map<String, String>? syncData,
    VpnStatus? vpnStatus,
    bool? isAdult,
    NextAiring? nextAiring,
  }) {
    return MultimediaItem(
      title: title ?? this.title,
      url: url ?? this.url,
      posterUrl: posterUrl ?? this.posterUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      description: description ?? this.description,
      contentType: contentType ?? this.contentType,
      episodes: episodes ?? this.episodes,
      provider: provider ?? this.provider,
      headers: headers ?? this.headers,
      year: year ?? this.year,
      score: score ?? this.score,
      duration: duration ?? this.duration,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      contentRating: contentRating ?? this.contentRating,
      cast: cast ?? this.cast,
      trailers: trailers ?? this.trailers,
      recommendations: recommendations ?? this.recommendations,
      syncData: syncData ?? this.syncData,
      vpnStatus: vpnStatus ?? this.vpnStatus,
      isAdult: isAdult ?? this.isAdult,
      nextAiring: nextAiring ?? this.nextAiring,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'posterUrl': posterUrl,
      'bannerUrl': bannerUrl,
      'logoUrl': logoUrl,
      'description': description,
      'type': contentType.name,
      'episodes': episodes?.map((e) => e.toJson()).toList(),
      'provider': provider,
      'headers': headers,
      'year': year,
      'score': score,
      'duration': duration,
      'status': status.name,
      'tags': tags,
      'contentRating': contentRating,
      'cast': cast?.map((a) => a.toJson()).toList(),
      'trailers': trailers?.map((t) => t.toJson()).toList(),
      'recommendations': recommendations?.map((r) => r.toJson()).toList(),
      'syncData': syncData,
      'vpnStatus': vpnStatus.name,
      'isAdult': isAdult,
      'nextAiring': nextAiring?.toJson(),
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
      url.hashCode ^
      title.hashCode ^
      posterUrl.hashCode ^
      (provider?.hashCode ?? 0);
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

  // Parity fields
  final double? rating;
  final int? runtime;
  final String? airDate;
  final DubStatus dubStatus;

  Episode({
    required this.name,
    required this.url,
    this.season = 0,
    this.episode = 0,
    this.description,
    this.posterUrl,
    this.headers,
    this.rating,
    this.runtime,
    this.airDate,
    this.dubStatus = DubStatus.none,
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
      rating: (json['rating'] as num?)?.toDouble(),
      runtime: json['runtime'] ?? json['duration'],
      airDate: json['airDate'],
      dubStatus: _parseDubStatus(json['dubStatus']),
    );
  }

  static DubStatus _parseDubStatus(dynamic raw) {
    if (raw == null) return DubStatus.none;
    final str = raw.toString().toLowerCase();
    if (str.contains('dub')) return DubStatus.dubbed;
    if (str.contains('sub')) return DubStatus.subbed;
    return DubStatus.none;
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
      'rating': rating,
      'runtime': runtime,
      'airDate': airDate,
      'dubStatus': dubStatus.name,
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

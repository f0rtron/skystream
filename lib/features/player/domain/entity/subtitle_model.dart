import 'package:dio/dio.dart';

class OnlineSubtitle {
  final String id;
  final String name;
  final String language;
  final String source; // e.g., "OpenSubtitles", "SubDL", "SubSource"
  final String downloadUrl;
  final bool isHearingImpaired;
  final Map<String, dynamic>? metadata;

  const OnlineSubtitle({
    required this.id,
    required this.name,
    required this.language,
    required this.source,
    required this.downloadUrl,
    this.isHearingImpaired = false,
    this.metadata,
  });

  factory OnlineSubtitle.fromJson(Map<String, dynamic> json) {
    return OnlineSubtitle(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      language: json['language'] ?? 'English',
      source: json['source'] ?? 'Unknown',
      downloadUrl: json['downloadUrl'] ?? '',
      isHearingImpaired: json['isHearingImpaired'] ?? false,
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'language': language,
      'source': source,
      'downloadUrl': downloadUrl,
      'isHearingImpaired': isHearingImpaired,
      'metadata': metadata,
    };
  }
}

abstract class SubtitleProvider {
  String get name;
  String get idPrefix;

  static const Map<String, String> commonHeaders = {
    'User-Agent': 'Cloudstream3 v0.2',
    'Accept': 'application/json',
  };

  Future<List<OnlineSubtitle>> search({
    required String query,
    String? imdbId,
    int? tmdbId,
    int? season,
    int? episode,
    String? language,
    CancelToken? cancelToken,
  });

  Future<String?> getDownloadUrl(OnlineSubtitle subtitle);
}

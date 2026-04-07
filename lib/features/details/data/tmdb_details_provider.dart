import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../discover/data/language_provider.dart';
import '../../discover/data/tmdb_provider.dart';
import '../../../core/models/tmdb_details.dart';
import '../../../core/services/tmdb_service.dart';

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
    FutureProvider.family<TmdbDetails?, MovieDetailsParams>((
      ref,
      params,
    ) async {
      final service = ref.watch(tmdbServiceProvider);
      final language = ref.watch(languageProvider);

      // Wrap in timeout to prevent infinite loading when connection is stale
      // This ensures error UI is shown instead of forever-loading spinner
      try {
        Map<String, dynamic>? data;
        Map<String, dynamic>? extra;

        if (params.type == 'tv') {
          final results = await Future.wait([
            service.getTvDetails(params.id, language: language),
            service.getTvExtra(params.id, language: language),
          ]).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('Request timed out'),
          );
          data = results[0];
          extra = results[1];
        } else {
          final results = await Future.wait([
            service.getMovieDetails(params.id, language: language),
            service.getMovieExtra(params.id, language: language),
          ]).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('Request timed out'),
          );
          data = results[0];
          extra = results[1];
        }

        if (data == null) return null;

        // Merge extra data into primary data
        if (extra != null) {
          data.addAll(extra);
        }

        // Ensure logoUrl is processed
        String? logoUrl = data['logo_url'];
        if (logoUrl == null) {
          final images = data['images'];
          if (images != null) {
            final logos = List<Map<String, dynamic>>.from(images['logos'] ?? []);
            logoUrl = TmdbService.pickBestLogo(logos, language);
          }
          data['logo_url'] = logoUrl;
        }

        return TmdbDetails.fromJson(data, language);
      } on TimeoutException {
        rethrow; // Let error handler show retry UI
      }
    });

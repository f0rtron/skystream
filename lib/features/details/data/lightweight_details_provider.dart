import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../discover/data/language_provider.dart';
import '../../discover/data/tmdb_provider.dart';
import '../../../core/models/tmdb_details.dart';
import '../../../core/services/tmdb_service.dart';
import './tmdb_details_provider.dart';

final lightweightMovieDetailsProvider =
    FutureProvider.family<TmdbDetails?, MovieDetailsParams>((
      ref,
      params,
    ) async {
      final service = ref.watch(tmdbServiceProvider);
      final language = ref.watch(languageProvider);

      try {
        final data = await service
            .getDetailsForCarousel(params.id, params.type, language: language)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('Fast-load timed out'),
            );

        if (data == null) return null;

        // Process logoUrl
        String? logoUrl;
        final images = data['images'];
        if (images != null) {
          final logos = List<Map<String, dynamic>>.from(images['logos'] ?? []);
          logoUrl = TmdbService.pickBestLogo(logos, language);
        }
        data['logo_url'] = logoUrl;

        return TmdbDetails.fromJson(data, language);
      } catch (_) {
        return null; // Fallback to heavy provider if fast-path fails
      }
    });

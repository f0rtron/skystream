import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/dio_client_provider.dart';
import '../data/subtitle_providers.dart';
import '../domain/entity/subtitle_model.dart';
import '../../settings/presentation/player_settings_provider.dart';

part 'subtitle_search_provider.g.dart';

const Map<String, String> subtitleLanguages = {
  'English': 'en',
  'Hindi': 'hi',
  'Bengali': 'bn',
  'Telugu': 'te',
  'Marathi': 'mr',
  'Tamil': 'ta',
  'Gujarati': 'gu',
  'Kannada': 'kn',
  'Malayalam': 'ml',
  'Punjabi': 'pa',
  'Arabic': 'ar',
  'Assamese': 'as',
  'Belarusian': 'be',
  'Bulgarian': 'bg',
  'Czech': 'cs',
  'German': 'de',
  'Greek': 'el',
  'Spanish': 'es',
  'French': 'fr',
  'Hebrew': 'he',
  'Croatian': 'hr',
  'Hungarian': 'hu',
  'Indonesian': 'id',
  'Italian': 'it',
  'Japanese': 'ja',
  'Korean': 'ko',
  'Latvian': 'lv',
  'Macedonian': 'mk',
  'Dutch': 'nl',
  'Polish': 'pl',
  'Portuguese': 'pt',
  'Romanian': 'ro',
  'Russian': 'ru',
  'Swedish': 'sv',
  'Turkish': 'tr',
  'Ukrainian': 'uk',
  'Urdu': 'ur',
  'Vietnamese': 'vi',
  'Chinese': 'zh',
};

@riverpod
class SubtitleSearch extends _$SubtitleSearch {
  late List<SubtitleProvider> _providers;
  CancelToken? _cancelToken;
  int _activeSearchId = 0;

  @override
  FutureOr<List<OnlineSubtitle>?> build() {
    ref.onDispose(() {
      _cancelToken?.cancel();
    });
    
    // Watch settings to update providers if they change
    ref.listen(playerSettingsProvider, (previous, next) {
      if (next.hasValue) {
        _initializeProviders();
      }
    });

    _initializeProviders();
    return null;
  }

  void _initializeProviders() {
    final dio = ref.read(dioClientProvider);
    final settings = ref.read(playerSettingsProvider).asData?.value ?? const PlayerSettings();
    
    _providers = [
      OpenSubtitlesProvider(
        dio, 
        username: settings.osUsername, 
        password: settings.osPassword,
        apiKey: settings.osApiKey,
      ),
      SubDLProvider(dio, apiKey: settings.subdlApiKey),
      SubSourceProvider(dio, apiKey: settings.subsourceApiKey),
    ];
  }

  Future<void> search({
    required String query,
    String? imdbId,
    int? tmdbId,
    int? season,
    int? episode,
    String? language,
  }) async {
    // 1. Cancel previous search
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    
    // 2. Increment search ID to ignore late results from previous calls
    final searchId = ++_activeSearchId;

    if (kDebugMode) {
      print("🔍 [SubtitleSearch] Starting search #$searchId for: $query (IMDB: $imdbId)");
    }
    state = const AsyncLoading();
    
    final List<OnlineSubtitle> allResults = [];
    final lang = language ?? ref.read(subtitleLanguageProvider);
    int completedProviders = 0;

    for (final provider in _providers) {
      provider.search(
        query: query,
        imdbId: imdbId,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        language: lang,
        cancelToken: _cancelToken,
      ).then((results) {
        if (!ref.mounted || searchId != _activeSearchId) return;
        
        if (results.isNotEmpty) {
          allResults.addAll(results);
          state = AsyncData(List.from(allResults));
        }
      }).catchError((Object e) {
        if (e is DioException && e.type == DioExceptionType.cancel) return;
        if (kDebugMode) print("${provider.name} search failed: $e");
      }).whenComplete(() {
        if (!ref.mounted || searchId != _activeSearchId) return;
        
        completedProviders++;
        // If all finished and no results found, ensure we transition from loading to empty data
        if (completedProviders == _providers.length && allResults.isEmpty) {
          state = const AsyncData([]);
        }
      });
    }
  }

  Future<String?> downloadAndPrepare(OnlineSubtitle subtitle) async {
    _initializeProviders();
    final dio = ref.read(dioClientProvider);
    final provider = _providers.firstWhere((p) => p.name == subtitle.source);
    
    String? url = subtitle.downloadUrl;
    if (url.isEmpty) {
      url = await provider.getDownloadUrl(subtitle) ?? "";
    }
    
    if (url.isEmpty) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = p.join(tempDir.path, "temp_sub_${DateTime.now().millisecondsSinceEpoch}");
      
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: SubtitleProvider.commonHeaders,
        ),
      );

      final List<int> bytes = response.data!;
      
      if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          if (file.isFile && (file.name.endsWith('.srt') || file.name.endsWith('.vtt'))) {
            final subFile = File(p.join(tempDir.path, file.name));
            await subFile.writeAsBytes(file.content as List<int>);
            return subFile.path;
          }
        }
      } else {
        final subFile = File("$savePath.srt");
        await subFile.writeAsBytes(bytes);
        return subFile.path;
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}

@riverpod
class SubtitleLanguage extends _$SubtitleLanguage {
  @override
  String build() => 'en';

  void set(String lang) => state = lang;
}

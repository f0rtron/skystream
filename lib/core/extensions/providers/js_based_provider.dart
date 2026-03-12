import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode

import '../../domain/entity/multimedia_item.dart';
import '../base_provider.dart';
import '../engine/js_engine.dart';
import '../../services/local_proxy_service.dart';

class JsBasedProvider extends SkyStreamProvider {
  final JsEngineService _jsEngine;
  final String _scriptPath;
  String get scriptPath => _scriptPath;
  // Include ID
  final String _id;
  @override
  String get id => _id;

  final String? _namespace;
  String? get namespace => _namespace; // Expose namespace
  final String? _forcedName;

  late Future<void> _initFuture;
  final Map<String, dynamic>? _initialManifest;

  // Update constructor
  JsBasedProvider(
    this._jsEngine,
    this._scriptPath, {
    required String id,
    String? namespace,
    String? forcedName,
    Map<String, dynamic>? manifest,
  }) : _id = id,
       _namespace = namespace,
       _forcedName = forcedName,
       _initialManifest = manifest {
    _initFuture = _init();
  }

  Future<void> get waitForInit => _initFuture;

  Map<String, dynamic> _manifest = {};
  String? _error;

  Future<void> _init() async {
    String? script;
    try {
      if (_scriptPath.startsWith('assets/')) {
        script = await rootBundle.loadString(_scriptPath);
      } else {
        final file = File(_scriptPath);
        if (await file.exists()) {
          script = await file.readAsString();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Error reading JS script ($_scriptPath): $e");
      _error = "Read: $e";
    }

    if (script != null) {
      // 1. Ensure manifest is populated BEFORE evaluation
      if (_initialManifest != null && _initialManifest!.isNotEmpty) {
        _manifest = _initialManifest!;
      }

      final manifestJson = jsonEncode(_manifest);

      // 2. Enforce IIFE wrapping for namespaced execution (Plugin v2 Standard)
      if (_namespace != null) {
        script = """
          (function() {
              // Standard v2: Every plugin strictly uses the injected manifest.
              const manifest = $manifestJson;

              var exports = (function() {
                  $script
                  
                  return {
                      getHome: (typeof getHome !== 'undefined') ? getHome : (typeof globalThis.getHome !== 'undefined' ? globalThis.getHome : undefined),
                      search: (typeof search !== 'undefined') ? search : (typeof globalThis.search !== 'undefined' ? globalThis.search : undefined),
                      load: (typeof load !== 'undefined') ? load : (typeof globalThis.load !== 'undefined' ? globalThis.load : undefined),
                      loadStreams: (typeof loadStreams !== 'undefined') ? loadStreams : (typeof globalThis.loadStreams !== 'undefined' ? globalThis.loadStreams : undefined),
                  };
              })();
              globalThis['$_namespace'] = exports;

              // Final Cleanup: If the plugin polluted globalThis (old style), we clean it up 
              // after capturing it into the namespace.
              if (globalThis.getHome) delete globalThis.getHome;
              if (globalThis.search) delete globalThis.search;
              if (globalThis.load) delete globalThis.load;
              if (globalThis.loadStreams) delete globalThis.loadStreams;
          })();
          """;
      }

      try {
        await _jsEngine.loadScript(script);
        debugPrint("JsBasedProvider: Loaded namespaced script for $_id");
      } catch (e) {
        _error = "Eval: $e";
        debugPrint("JsBasedProvider: CRITICAL - Eval failed for $_id: $e");
      }
    } else {
      _error = "Not found";
    }
  }

  String _fn(String name) => _namespace != null ? '$_namespace.$name' : name;

  @override
  String get name {
    if (_forcedName != null) return _forcedName;
    if (_manifest['name'] != null) return _manifest['name'];
    if (_error != null) return "Err: $_error";
    return "JS Extension";
  }

  // ... (rest of simple getters)
  @override
  String get mainUrl => _manifest['baseUrl'] ?? "";

  @override
  String get version => (_manifest['version'] ?? 0).toString();

  @override
  List<String> get languages => _readManifestStringList(
    ['languages', 'language', 'lang'],
    fallback: const ['en'],
  );

  @override
  Set<ProviderType> get supportedTypes {
    final categories = _readManifestStringList([
      'categories',
      'tvTypes',
      'types',
    ]);
    if (categories.isEmpty) {
      return {ProviderType.movie};
    }

    final mapped = categories.map(_mapProviderType).toSet();
    if (mapped.isEmpty) {
      return {ProviderType.movie};
    }
    return mapped;
  }

  List<String> _readManifestStringList(
    List<String> keys, {
    List<String> fallback = const [],
  }) {
    for (final key in keys) {
      final value = _manifest[key];
      if (value is List) {
        final parsed = value.map((e) => e.toString()).toList();
        if (parsed.isNotEmpty) {
          return parsed;
        }
      }
      if (value is String && value.trim().isNotEmpty) {
        return [value];
      }
    }
    return fallback;
  }

  ProviderType _mapProviderType(String raw) {
    switch (raw.toLowerCase()) {
      case 'movie':
      case 'movies':
      case 'tvtype.movie':
        return ProviderType.movie;
      case 'tv':
      case 'series':
      case 'tvseries':
      case 'tvshow':
      case 'tvshows':
      case 'tvtype.tvseries':
        return ProviderType.series;
      case 'anime':
      case 'tvtype.anime':
        return ProviderType.anime;
      case 'livetv':
      case 'iptv':
      case 'tvtype.livetv':
        return ProviderType.iptv;
      default:
        return ProviderType.other;
    }
  }

  @override
  Future<Map<String, List<MultimediaItem>>> getHome() async {
    await _initFuture;
    if (_error != null) throw JsPluginException("INIT_ERROR", _error!);
    try {
      final result = await _jsEngine.invokeAsync(_fn('getHome'));
      if (result is Map) {
        final map = <String, List<MultimediaItem>>{};
        result.forEach((key, value) {
          if (value is List) {
            map[key.toString()] = value
                .map(
                  (e) =>
                      MultimediaItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList();
          }
        });
        return map;
      }
      throw Exception("Extension returned invalid home data (not a map).");
    } on JsPluginException catch (e) {
      if (kDebugMode) debugPrint("JsPluginException in getHome: $e");
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint("Error in getHome: $e");
      throw Exception("Failed to load home content: $e");
    }
  }

  @override
  Future<List<MultimediaItem>> search(String query) async {
    await _initFuture;
    if (_error != null) throw JsPluginException("INIT_ERROR", _error!);
    try {
      final result = await _jsEngine.invokeAsync(_fn('search'), [query]);
      if (result is List) {
        return result
            .map((e) => MultimediaItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return [];
    } on JsPluginException catch (e) {
      if (kDebugMode) debugPrint("JsPluginException in search: $e");
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint("Error in search: $e");
      return [];
    }
  }

  @override
  Future<MultimediaItem> getDetails(String url) async {
    await _initFuture;
    if (_error != null) throw JsPluginException("INIT_ERROR", _error!);
    try {
      final result = await _jsEngine.invokeAsync(_fn('load'), [url]);
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        if (map['url'] == null || map['url'].toString().isEmpty) {
          map['url'] = url;
        }
        return MultimediaItem.fromJson(map);
      }
      throw Exception("Extension returned invalid detail data.");
    } on JsPluginException catch (e) {
      if (kDebugMode) debugPrint("JsPluginException in getDetails: $e");
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint("Error in getDetails: $e");
      return MultimediaItem(
        title: "Error: $e",
        url: url,
        posterUrl: "",
      );
    }
  }

  @override
  Future<List<StreamResult>> loadStreams(String url) async {
    await _initFuture;
    if (_error != null) throw JsPluginException("INIT_ERROR", _error!);
    await LocalProxyService.instance.startServer();

    try {
      final result = await _jsEngine.invokeAsync(_fn('loadStreams'), [url]);
      if (result is List) {
        return result.map((e) {
          final map = Map<String, dynamic>.from(e);
          String finalUrl = map['url'];

          // MAGIC M3U8 HANDLING
          if (finalUrl.startsWith("magic_m3u8:")) {
            try {
              final base64Content = finalUrl.substring("magic_m3u8:".length);
              final bytes = base64Decode(base64Content);
              var m3u8Content = utf8.decode(bytes);

              // Compatibility: Replace MAGIC_PROXY_v1 with real local proxy URLs
              m3u8Content = m3u8Content.replaceAllMapped(
                RegExp(r'MAGIC_PROXY_v1([A-Za-z0-9+/=]+)'),
                (match) {
                  final b64Url = match.group(1)!;
                  try {
                    final realUrlBytes = base64Decode(b64Url);
                    final realUrl = utf8.decode(realUrlBytes);
                    return LocalProxyService.instance.getProxyUrl(realUrl);
                  } catch (e) {
                    return match.group(0)!;
                  }
                },
              );

              finalUrl = LocalProxyService.instance.serveM3u8(m3u8Content);
            } catch (err) {
              if (kDebugMode) debugPrint("Magic M3U8 Error: $err");
            }
          }
          // DIRECT PROXY URL HANDLING
          else if (finalUrl.startsWith("MAGIC_PROXY_v1")) {
            try {
              final b64Url = finalUrl.substring("MAGIC_PROXY_v1".length);
              final realUrlBytes = base64Decode(b64Url);
              final realUrl = utf8.decode(realUrlBytes);
              finalUrl = LocalProxyService.instance.getProxyUrl(realUrl);
            } catch (e) {
              if (kDebugMode) {
                debugPrint("Error decoding MAGIC_PROXY_v1 url: $e");
              }
            }
          }

          return StreamResult(
            url: finalUrl,
            quality: map['quality'] ?? "Auto",
            headers: map['headers'] != null
                ? Map<String, String>.from(map['headers'])
                : null,
            subtitles: map['subtitles'] != null
                ? (map['subtitles'] as List)
                      .map(
                        (s) =>
                            SubtitleFile.fromJson(Map<String, dynamic>.from(s)),
                      )
                      .toList()
                : null,
            drmKid: map['drmKid'],
            drmKey: map['drmKey'],
            licenseUrl: map['licenseUrl'],
          );
        }).toList();
      }
      return [];
    } on JsPluginException catch (e) {
      if (kDebugMode) debugPrint("JsPluginException in loadStreams: $e");
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint("Error in loadStreams: $e");
      return [];
    }
  }
}

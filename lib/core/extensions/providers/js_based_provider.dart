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

  // Update constructor
  JsBasedProvider(
    this._jsEngine,
    this._scriptPath, {
    required String id,
    String? namespace,
    String? forcedName,
  }) : _id = id,
       _namespace = namespace,
       _forcedName = forcedName {
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
      // Wrap script if namespace provided
      if (_namespace != null) {
        script =
            """
          globalThis['$_namespace'] = (function() {
              $script
              
              return {
                  getManifest: (typeof getManifest !== 'undefined') ? getManifest : undefined,
                  getHome: (typeof getHome !== 'undefined') ? getHome : undefined,
                  search: (typeof search !== 'undefined') ? search : undefined,
                  load: (typeof load !== 'undefined') ? load : undefined,
                  loadStreams: (typeof loadStreams !== 'undefined') ? loadStreams : undefined,
              };
          })();
          """;
      }

      try {
        await _jsEngine.loadScript(script);

        try {
          final funcName = _namespace != null
              ? '$_namespace.getManifest'
              : 'getManifest';
          final manifest = await _jsEngine.callFunction(funcName);
          // ... (rest unchanged)
          if (manifest is Map) {
            _manifest = Map<String, dynamic>.from(manifest);
          } else {
            if (kDebugMode) {
              String msg = manifest.toString();
              if (msg.length > 500)
                msg = "${msg.substring(0, 500)}... [Truncated]";
              debugPrint(
                "Error: getManifest returned non-Map: $msg for $_scriptPath",
              );
            }
            _error = "Manifest type err";
          }
        } catch (e) {
          if (kDebugMode)
            debugPrint("Error loading manifest for $_scriptPath: $e");
          _error = "Manifest: $e";
        }
      } catch (e) {
        if (kDebugMode) debugPrint("Error evaluating script $_scriptPath: $e");
        _error = "Eval: $e";
      }
    } else {
      if (kDebugMode) debugPrint("JS Script not found at $_scriptPath");
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
  String get lang => _manifest['lang'] ?? "en";

  @override
  Set<ProviderType> get supportedTypes => {ProviderType.movie};

  @override
  Future<Map<String, List<MultimediaItem>>> getHome() async {
    await _initFuture;
    final result = await _jsEngine.invokeAsync(_fn('getHome'));
    if (result is Map<String, dynamic>) {
      final map = <String, List<MultimediaItem>>{};
      result.forEach((key, value) {
        if (value is List) {
          map[key] = value
              .map((e) => MultimediaItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      });
      return map;
    }
    // Throw error if result is invalid (null or not a map) to trigger Error Screen
    throw Exception("Extension returned invalid data (null or not a map).");
  }

  @override
  Future<List<MultimediaItem>> search(String query) async {
    await _initFuture;
    final result = await _jsEngine.invokeAsync(_fn('search'), [query]);
    if (result is List) {
      return result
          .map((e) => MultimediaItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  @override
  Future<MultimediaItem> getDetails(String url) async {
    await _initFuture;
    try {
      final result = await _jsEngine.invokeAsync(_fn('load'), [url]);
      if (result is Map) {
        // ...
        final map = Map<String, dynamic>.from(result);
        if (map['url'] == null || map['url'].toString().isEmpty) {
          map['url'] = url;
        }
        return MultimediaItem.fromJson(map);
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Error in getDetails: $e");
    }
    return MultimediaItem(
      title: "Error loading details",
      url: url,
      posterUrl: "",
    );
  }

  @override
  Future<List<StreamResult>> loadStreams(String url) async {
    await _initFuture;
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

              // M3U8 Rewriting is now done by LocalProxyService recursively if we serve it,
              // BUT the JS might have pre-encoded "MAGIC_PROXY_v1" placeholders.
              // We should probably strip those or let the Proxy Service handle them?
              // Actually, the new ProxyService doesn't know about "MAGIC_PROXY_v1".
              // We need to keep the placeholder replacement OR rely on the JS to produce clean URLs.
              // The current JS produces "MAGIC_PROXY_v1".

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
              // Strip prefix
              final b64Url = finalUrl.substring("MAGIC_PROXY_v1".length);
              final realUrlBytes = base64Decode(b64Url);
              final realUrl = utf8.decode(realUrlBytes);
              finalUrl = LocalProxyService.instance.getProxyUrl(realUrl);
            } catch (e) {
              if (kDebugMode)
                debugPrint("Error decoding MAGIC_PROXY_v1 url: $e");
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
          );
        }).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Error in loadStreams: $e");
    }
    return [];
  }
}

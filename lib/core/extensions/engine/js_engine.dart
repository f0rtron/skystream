import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../../storage/extension_repository.dart';
import '../../network/cloudflare_bypass.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

import '../../network/dio_client_provider.dart';

class JsPluginException implements Exception {
  final String code;
  final String message;
  final String? pluginId;

  JsPluginException(this.code, this.message, {this.pluginId});

  @override
  String toString() => "JsPluginException[$code]: $message";
}

final jsEngineProvider = Provider.autoDispose<JsEngineService>((ref) {
  final storage = ref.read(extensionRepositoryProvider);
  final dio = ref.read(dioClientProvider);
  final service = JsEngineService(storage, dio);
  ref.onDispose(() => service.dispose());
  return service;
});

class JsEngineService {
  late JavascriptRuntime _runtime;
  final Dio _dio;
  final CookieJar _cookieJar = CookieJar(); // RAM-based cookie jar
  final ExtensionRepository _storage;

  JsEngineService(this._storage, this._dio) {
    final bool hasCookieManager = _dio.interceptors.any((i) => i is CookieManager);
    if (!hasCookieManager) {
      _dio.interceptors.add(CookieManager(_cookieJar));
    }
    // DohInterceptor is provided globally by dioClientProvider
    _runtime = getJavascriptRuntime();
    // Defer polyfill injection to avoid blocking the UI thread
    Future.microtask(() => _initPolyfills());
  }

  void _initPolyfills() {
    // Console Polyfill
    _runtime.onMessage('console_log', (dynamic args) {
      if (kDebugMode) debugPrint("[JS] ${_sanitizeLog(args)}");
    });
    _runtime.onMessage('console_error', (dynamic args) {
      if (kDebugMode) debugPrint("[JS ERROR] ${_sanitizeLog(args)}");
    });

    _runtime.evaluate("""
      var global = globalThis;
      var console = {
        log: function(msg) { sendMessage('console_log', JSON.stringify(msg)); },
        error: function(msg) { sendMessage('console_error', JSON.stringify(msg)); },
        warn: function(msg) { sendMessage('console_log', "WARN: " + JSON.stringify(msg)); }
      };
      
      // Legacy log function
      function log(msg) { console.log(msg); }
    """);

    // HTTP Polyfill (Dio Bridge)
    // CRITICAL UPDATE: Support both Promise (await http_get) and Callback (http_get(..., cb))
    _runtime.onMessage('http_request', (dynamic args) async {
      return await _handleHttp(args);
    });

    // Storage Bridge
    _runtime.onMessage('set_storage', (dynamic args) async {
      return await _handleStorage(args, true);
    });
    _runtime.onMessage('get_storage', (dynamic args) {
      return _handleStorage(args, false);
    });

    // Crypto Bridge
    _runtime.onMessage('crypto_decrypt_aes', (dynamic args) async {
      try {
        Map<String, dynamic> req;
        if (args is Map) {
          req = Map<String, dynamic>.from(args);
        } else {
          req = jsonDecode(args);
        }

        // Dart's base64 requires clean, padded strings without whitespaces
        String normalizeB64(String input) {
          String cleaned = input.replaceAll(RegExp(r'\s+'), '');
          while (cleaned.length % 4 != 0) {
            cleaned += '=';
          }
          return cleaned;
        }

        final String encryptedB64 = normalizeB64(req['data']);
        final String keyB64 = normalizeB64(req['key']);
        final String ivB64 = normalizeB64(req['iv']);

        // Uses the 'encrypt' package
        final key = encrypt_lib.Key.fromBase64(keyB64);
        final iv = encrypt_lib.IV.fromBase64(ivB64);
        final encrypter = encrypt_lib.Encrypter(
          encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
        );
        final decrypted = encrypter.decrypt64(encryptedB64, iv: iv);

        return decrypted;
      } catch (e) {
        if (kDebugMode) debugPrint("[JS Crypto Error] ${e.toString()}");
        return "";
      }
    });

    _runtime.evaluate("""
      async function _dartHttp(method, url, headers, body) {
         try {
            return await sendMessage('http_request', JSON.stringify({
              method: method,
              url: url,
              headers: headers,
              body: body
            }));
         } catch(e) {
            console.error("HTTP Bridge Error: " + e);
            throw e;
         }
      }

      function http_get(url, headers, cb) {
         var promise = _dartHttp('GET', url, headers, null);
         if (cb && typeof cb === 'function') {
            promise.then(cb).catch(function(err) { cb({status: 0, body: ""}); });
         }
         return promise; // Returns object {statusCode, body, headers}
      }
      
      // Polyfill for _fetch typically used in some plugin (returns body string)
      async function _fetch(url) {
          var res = await http_get(url, {});
          if (res.statusCode >= 200 && res.statusCode < 300) {
              return res.body; 
          } else {
              throw "HTTP Error " + res.statusCode + " fetching " + url;
          }
      }
      
      function http_post(url, headers, body, cb) {
         var promise = _dartHttp('POST', url, headers, body);
         if (cb && typeof cb === 'function') {
            promise.then(cb).catch(function(err) { cb({status: 0, body: ""}); });
         }
         return promise;
      }
    """);

    // Timer Polyfill
    // NOTE: True async timers (delay-based scheduling) cannot be implemented
    // in this synchronous JS runtime. Callbacks execute immediately.
    // Extensions that depend on real setTimeout delays may behave unexpectedly.
    _runtime.evaluate("""
      function setTimeout(callback, delay) {
         if (delay && delay > 0) {
            console.warn("setTimeout with delay=" + delay + "ms executes immediately in SkyStream runtime");
         }
         try { callback(); } catch(e) { console.error(e); }
         return 1;
      }
      function clearTimeout(id) {}
      function setInterval(cb, d) { return 1; }
      function clearInterval(id) {}

      // Storage Polyfill
      function setPreference(key, value) {
          sendMessage('set_storage', JSON.stringify({ key: key, value: value }));
      }
      async function getPreference(key) {
          return await sendMessage('get_storage', JSON.stringify({ key: key }));
      }
    """);

    // Standard Entities
    _runtime.evaluate("""
      class MultimediaItem {
        constructor({ title, url, posterUrl, type, bannerUrl, description, episodes, headers, provider }) {
          this.title = title;
          this.url = url;
          this.posterUrl = posterUrl;
          this.type = type || 'movie';
          this.bannerUrl = bannerUrl;
          this.description = description;
          this.episodes = episodes;
          this.headers = headers;
          this.provider = provider;
        }
      }

      class Episode {
        constructor({ name, url, season, episode, description, posterUrl, headers }) {
          this.name = name;
          this.url = url;
          this.season = season || 0;
          this.episode = episode || 0;
          this.description = description;
          this.posterUrl = posterUrl;
          this.headers = headers;
        }
      }

      class StreamResult {
        constructor({ url, quality, headers, subtitles, drmKid, drmKey, licenseUrl }) {
          this.url = url;
          this.quality = quality || 'Auto';
          this.headers = headers;
          this.subtitles = subtitles;
          this.drmKid = drmKid;
          this.drmKey = drmKey;
          this.licenseUrl = licenseUrl;
        }
      }

      globalThis.MultimediaItem = MultimediaItem;
      globalThis.Episode = Episode;
      globalThis.StreamResult = StreamResult;

      var CloudStream = {
         getLanguage: function() { return "en"; },
         getRegion: function() { return "US"; }
      };
      var source = {
         baseUrl: "",
         getStreamUrl: function() { return ""; }
      };
    """);
  }

  Future<Map<String, dynamic>> _handleHttp(dynamic args) async {
    final requestId =
        "req_${DateTime.now().microsecondsSinceEpoch.toString().substring(10)}";
    try {
      Map<String, dynamic> req;
      if (args is Map) {
        req = Map<String, dynamic>.from(args);
      } else {
        req = jsonDecode(args);
      }

      final String method = req['method'] ?? 'GET';
      final String url = req['url'];
      final Map<String, dynamic>? headers = req['headers'] != null
          ? Map<String, dynamic>.from(req['headers'])
          : null;
      final dynamic body = req['body'];

      debugPrint("[JS HTTP] $method $url ($requestId)");

      final response = await _dio.request(
        url,
        data: body,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );

      debugPrint("[JS HTTP] Back $url ($requestId) -> ${response.statusCode}");

      // --- Cloudflare Bypass ---
      final responseHeaders = response.headers.map.map(
        (k, v) => MapEntry(k, v.join(',')),
      );
      final responseBody = response.data.toString();

      if (CloudflareBypass.instance.isCloudflareChallenge(
        response.statusCode,
        responseHeaders,
        responseBody,
      )) {
        if (kDebugMode) {
          debugPrint(
            '[JS HTTP] CF challenge detected for $url, solving via WebView...',
          );
        }
        // Solve the challenge AND extract page HTML directly from the WebView.
        // This avoids TLS fingerprinting issues that cause Dio retries to fail.
        final cfResult = await CloudflareBypass.instance.solveAndFetch(url);
        if (cfResult != null) {
          if (kDebugMode) {
            debugPrint(
              '[JS HTTP] CF solved, got ${cfResult.body.length} chars from WebView',
            );
          }
          return {
            'code': cfResult.statusCode,
            'statusCode': cfResult.statusCode,
            'status': cfResult.statusCode,
            'body': cfResult.body,
            'headers': <String, String>{},
            'finalUrl': cfResult.finalUrl,
          };
        }
      }

      // CloudStream Callback plugin expect 'status' and 'body'.
      return {
        'code': response.statusCode,
        'statusCode': response.statusCode,
        'status': response.statusCode, // ALIAS for plugins like Ringz
        'body': responseBody,
        'headers': responseHeaders,
        'finalUrl': response.realUri.toString(),
      };
    } catch (e) {
      if (kDebugMode) debugPrint("[JS HTTP ERROR] $requestId: $e");
      return {
        'code': 0,
        'statusCode': 0,
        'status': 0,
        'body': '',
        'error': e.toString(),
      };
    }
  }

  Future<dynamic> _handleStorage(dynamic args, bool isSet) async {
    try {
      Map<String, dynamic> data;
      if (args is Map) {
        data = Map<String, dynamic>.from(args);
      } else {
        data = jsonDecode(args);
      }
      final key = data['key'];

      if (isSet) {
        final value = data['value'];
        await _storage.setExtensionData(key, value);
        return "OK";
      } else {
        return _storage.getExtensionData(key);
      }
    } catch (e) {
      if (kDebugMode) debugPrint("JS eval error: $e");
      return null;
    }
  }

  Future<void> loadScript(String script) async {
    final res = _runtime.evaluate(script);
    if (res.isError) {
      throw Exception("JS Load Error: ${res.stringResult}");
    }
  }

  /// Unified Invoke: Handles Sync Return, Promise Return, AND Callback Injection
  Future<dynamic> invokeAsync(
    String functionName, [
    List<dynamic>? args,
  ]) async {
    String argsStr = "";
    if (args != null && args.isNotEmpty) {
      argsStr = args.map((e) => jsonEncode(e)).join(', ');
    }

    final callbackId = "cb_${DateTime.now().microsecondsSinceEpoch}";
    final completer = Completer<dynamic>();

    // Listen for the result (called via cb or sendMessage)
    // Use a boolean to ensure we only resolve once (since we might hook both return and cb)
    bool isResolved = false;

    void resolve(dynamic result) {
      if (isResolved) return;
      isResolved = true;

      // Unpack standard v2 PluginResult if present
      // We skip this check for getManifest which returns metadata directly for speed.
      bool isManifestRequest = functionName.endsWith("getManifest");

      dynamic unwrapped;
      if (result is String) {
        if (result == "__dart_void__") {
          unwrapped = null;
        } else {
          try {
            unwrapped = jsonDecode(result);
          } catch (e) {
            unwrapped = result;
          }
        }
      } else if (result is Map && result.containsKey('__dart_error__')) {
        completer.completeError(result['__dart_error__']);
        return;
      } else {
        unwrapped = result;
      }

      if (!isManifestRequest && unwrapped is Map) {
        final success = unwrapped['success'] ?? false;
        if (!success) {
          final code = unwrapped['errorCode'] ?? 'UNKNOWN_ERROR';
          final message = unwrapped['message'] ?? 'An unexpected plugin error occurred';
          completer.completeError(JsPluginException(code, message));
          return;
        }
        // Success case: return the nested data
        completer.complete(unwrapped['data']);
      } else {
        completer.complete(unwrapped);
      }
    }

    _runtime.onMessage(callbackId, (dynamic result) => resolve(result));

    // The Wrapper:
    // Defines a callback function `dart_cb` that sends message.
    // Calls the target function with (...args, dart_cb).
    // Checks the RETURN value:
    //    - If Promise: .then(dart_cb)
    //    - If Value (!= undefined): dart_cb(value)
    //    - If undefined: Assume the function will call dart_cb() later (Callback pattern).

    final evalWrapper =
        """
       (function() {
          try {
             var dart_cb = function(res) {
                 sendMessage('$callbackId', res !== undefined ? JSON.stringify(res) : "__dart_void__");
             };
             
             // Dynamic call with injected callback
             // We construct the call manually to inject 'dart_cb'
             var fn = globalThis['$functionName'];
             if (typeof fn !== 'function') {
                 // Try looking in global scope directly if not explicit property (unlikely)
                 // Or maybe namespaced? user usually passes 'StreamFlix.getHome'
                 var parts = '$functionName'.split('.');
                 var target = globalThis;
                 for(var i=0; i<parts.length; i++) {
                    target = target[parts[i]];
                 }
                 fn = target;
             }
             
             if (typeof fn !== 'function') throw "Function $functionName not found";

             // Prepare args
             var args = [$argsStr];
             
             // Append callback to args
             args.push(dart_cb);
             
             var res = fn.apply(null, args);
             
             // Handle Return Value (Hybrid support)
             if (res && (typeof res.then === 'function' || res instanceof Promise)) {
                // It returned a Promise (ignore the callback we passed? or support both?)
                res.then(dart_cb).catch(function(err) {
                   sendMessage('$callbackId', JSON.stringify({'__dart_error__': err.toString()}));
                });
             } else if (res !== undefined) {
                // It returned a sync value (e.g. getManifest)
                // Treat as immediate result
                dart_cb(res);
             }
             // If res is undefined, we assume it used the 'dart_cb' we passed.
             
          } catch(e) {
             sendMessage('$callbackId', JSON.stringify({'__dart_error__': e.toString()}));
          }
       })();
     """;

    _runtime.evaluate(evalWrapper);

    // Complete only via the onMessage callback above. The JS runtime may require
    // pumping to run promise callbacks; use a timer to pump periodically
    // instead of a blocking loop so the UI stays responsive.
    Timer? pumpTimer;
    pumpTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (completer.isCompleted) {
        pumpTimer?.cancel();
        return;
      }
      _runtime.executePendingJob();
    });

    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Timeout executing $functionName');
        },
      );
    } finally {
      pumpTimer.cancel();
    }
  }

  Future<dynamic> callFunction(String name, [List<dynamic>? args]) async {
    return invokeAsync(name, args);
  }

  void dispose() {
    _runtime.dispose();
  }

  String _sanitizeLog(dynamic args) {
    final String msg = args.toString();
    // Detect HTML-like content (checking for common tags/doctypes)
    if (msg.length > 500 &&
        (msg.toLowerCase().contains("<!doctype html>") ||
            msg.toLowerCase().contains("<html") ||
            msg.contains("</div>"))) {
      return "[HTML Content Omitted - Length: ${msg.length}]";
    }
    // Truncate very long logs
    if (msg.length > 3000) {
      return "${msg.substring(0, 3000)}... [Truncated]";
    }
    return msg;
  }
}

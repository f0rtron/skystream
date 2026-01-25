import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../../storage/storage_service.dart';

final jsEngineProvider = Provider<JsEngineService>((ref) {
  final storage = ref.read(storageServiceProvider);
  final service = JsEngineService(storage);
  ref.onDispose(() => service.dispose());
  return service;
});

class JsEngineService {
  late JavascriptRuntime _runtime;
  final Dio _dio = Dio();
  final CookieJar _cookieJar = CookieJar(); // RAM-based cookie jar
  final StorageService _storage;

  JsEngineService(this._storage) {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _runtime = getJavascriptRuntime();
    _initPolyfills();
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
    _runtime.evaluate("""
      function setTimeout(callback, delay) {
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

    // CloudStream Environment Stubs
    _runtime.evaluate("""
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

      // print("[JS HTTP] $method $url ($requestId)");

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

      // print("[JS HTTP] Back $url ($requestId) -> ${response.statusCode}");

      // CloudStream Callback plugin expect 'status' and 'body'.
      return {
        'code': response.statusCode,
        'statusCode': response.statusCode,
        'status': response.statusCode, // ALIAS for plugins like Ringz
        'body': response.data.toString(),
        'headers': response.headers.map.map((k, v) => MapEntry(k, v.join(','))),
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
      if (kDebugMode) debugPrint("Storage Error: $e");
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

      if (result is String) {
        if (result == "__dart_void__") {
          completer.complete(null);
        } else {
          try {
            completer.complete(jsonDecode(result));
          } catch (e) {
            completer.complete(result);
          }
        }
      } else if (result is Map && result.containsKey('__dart_error__')) {
        completer.completeError(result['__dart_error__']);
      } else {
        completer.complete(result);
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

    // Wait for callback with timeout
    int retries = 0;
    while (!completer.isCompleted) {
      if (retries > 600) {
        // 30 seconds
        if (!completer.isCompleted) {
          completer.completeError("Timeout executing $functionName");
        }
        break;
      }
      _runtime.executePendingJob();
      await Future.delayed(const Duration(milliseconds: 50));
      retries++;
    }

    return completer.future;
  }

  Future<dynamic> callFunction(String name, [List<dynamic>? args]) async {
    return invokeAsync(name, args);
  }

  void dispose() {
    _runtime.dispose();
  }

  String _sanitizeLog(dynamic args) {
    String msg = args.toString();
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

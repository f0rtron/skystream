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
import '../services/plugin_storage_service.dart';
import '../providers.dart';

import '../../network/dio_client_provider.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

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
  final pluginStorage = ref.read(pluginStorageServiceProvider);
  final dio = ref.read(dioClientProvider);
  final service = JsEngineService(storage, pluginStorage, dio);
  ref.onDispose(() => service.dispose());
  return service;
});

class JsEngineService {
  final JavascriptRuntime _runtime;
  final Dio _dio;
  final CookieJar _cookieJar = CookieJar(); // RAM-based cookie jar
  final ExtensionRepository _storage;
  final PluginStorageService _pluginStorage;

  // Track the plugin currently being initialized to associate registerSettings calls
  String? currentPackageName;

  // Persistent callback registry to prevent memory leaks from dynamic listeners
  final Map<String, Completer<dynamic>> _pendingCallbacks = {};
  final Map<String, dynamic> _domRegistry = {};

  JsEngineService(this._storage, this._pluginStorage, this._dio) : _runtime = getJavascriptRuntime() {
    final bool hasCookieManager = _dio.interceptors.any(
      (i) => i is CookieManager,
    );
    if (!hasCookieManager) {
      _dio.interceptors.add(CookieManager(_cookieJar));
    }
    // DohInterceptor is provided globally by dioClientProvider
    // DohInterceptor is provided globally by dioClientProvider
    // Defer polyfill injection to avoid blocking the UI thread
    Future.microtask(() => _initPolyfills());
  }

  void _initPolyfills() {
    // 1. Persistent Callback Dispatcher (Receiver)
    _runtime.onMessage('js_dispatch_callback', (dynamic args) {
      try {
        Map<String, dynamic> data;
        if (args is Map) {
          data = Map<String, dynamic>.from(args);
        } else {
          data = jsonDecode(args);
        }

        final String? id = data['callbackId'];
        final dynamic result = data['result'];
        final dynamic error = data['error'];

        if (id != null) {
          final completer = _pendingCallbacks.remove(id);
          if (completer != null && !completer.isCompleted) {
            if (error != null) {
              completer.completeError(error);
            } else {
              completer.complete(result);
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint("[JS Dispatch Error] $e");
      }
    });

    // 2. Async Timer Bridge (Receiver)
    _runtime.onMessage('js_set_timeout', (dynamic args) {
      try {
        final Map<String, dynamic> data = args is Map
            ? Map<String, dynamic>.from(args)
            : jsonDecode(args);
        final id = data['id'];
        final delay = data['delay'] ?? 0;

        Future.delayed(Duration(milliseconds: delay), () {
          _runtime.evaluate(
            "if (globalThis.timeout_registry['$id']) { globalThis.timeout_registry['$id'](); }",
          );
        });
      } catch (e) {
        if (kDebugMode) debugPrint("[JS Timer Bridge Error] $e");
      }
    });

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

      // 1. Persistent Callback Dispatcher (JS Sender)
      globalThis.executeCallback = function(id, result, error) {
        sendMessage('js_dispatch_callback', JSON.stringify({
          callbackId: id,
          result: result,
          error: error
        }));
      };
    """);

    // HTTP Polyfill (Dio Bridge)
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

    _runtime.onMessage('get_preference', (dynamic args) {
      try {
        final Map<String, dynamic> data = args is Map ? Map<String, dynamic>.from(args) : jsonDecode(args.toString());
        final String packageName = data['packageName'];
        final String key = data['key'];
        return _storage.getExtensionData("$packageName:$key");
      } catch (e) {
        return null;
      }
    });

    _runtime.onMessage('set_preference', (dynamic args) async {
      try {
        final Map<String, dynamic> data = args is Map ? Map<String, dynamic>.from(args) : jsonDecode(args.toString());
        final String packageName = data['packageName'];
        final String key = data['key'];
        final dynamic value = data['value'];
        await _storage.setExtensionData("$packageName:$key", value);
        return true;
      } catch (e) {
        return false;
      }
    });

    // Base64 Bridge
    _runtime.onMessage('base64_decode', (dynamic args) {
      try {
        return utf8.decode(base64.decode(args.toString()));
      } catch (e) {
        return null;
      }
    });

    _runtime.onMessage('base64_encode', (dynamic args) {
      try {
        return base64.encode(utf8.encode(args.toString()));
      } catch (e) {
        return null;
      }
    });

    // DOM Parser Bridge
    _runtime.onMessage('dom_parse', (dynamic args) {
      try {
        final Map<String, dynamic> data = args is Map
            ? Map<String, dynamic>.from(args)
            : jsonDecode(args);
        final String html = data['html'];
        final String id = "doc_${DateTime.now().microsecondsSinceEpoch}";
        final doc = html_parser.parse(html);
        _domRegistry[id] = doc;
        return id;
      } catch (e) {
        return null;
      }
    });

    _runtime.onMessage('dom_query', (dynamic args) {
      try {
        final Map<String, dynamic> data = args is Map
            ? Map<String, dynamic>.from(args)
            : jsonDecode(args);
        final String? nodeId = data['nodeId'];
        final String? query = data['query'];
        final bool multi = data['multi'] ?? false;

        if (nodeId == null || query == null) {
           if (kDebugMode) debugPrint("[DOM Query Error] nodeId or query is null");
           return null;
        }

        final node = _domRegistry[nodeId];
        if (node == null) return null;

        if (multi) {
          final List<html_dom.Element> elements = (node is html_dom.Document) 
              ? node.querySelectorAll(query) 
              : (node as html_dom.Element).querySelectorAll(query);
          return elements.map((e) => _serializeElement(e)).toList();
        } else {
          final html_dom.Element? element = (node is html_dom.Document)
              ? node.querySelector(query)
              : (node as html_dom.Element).querySelector(query);
          return _serializeElement(element);
        }
      } catch (e) {
        if (kDebugMode) debugPrint("[DOM Query Error] $e");
        return null;
      }
    });

    _runtime.onMessage('dom_dispose', (dynamic args) {
      _domRegistry.remove(args.toString());
      return "OK";
    });

    // Native SDK Helpers
    _runtime.onMessage('register_settings', (dynamic args) async {
      if (kDebugMode) debugPrint("[JS SDK] Settings Registration: $args");
      if (currentPackageName != null) {
        try {
          final schema = args is List ? args : jsonDecode(args.toString());
          await _pluginStorage.saveSettingsSchema(currentPackageName!, schema);
        } catch (e) {
          debugPrint("Failed to save settings schema for $currentPackageName: $e");
        }
      }
    });

    _runtime.onMessage('solve_captcha', (dynamic args) async {
      if (kDebugMode) debugPrint("[JS SDK] Captcha Solve Requested: $args");
      // Placeholder: In a real implementation, this would trigger a WebView dialog
      return "mock_captcha_token";
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
            var res = await sendMessage('http_request', JSON.stringify({
              method: method,
              url: url,
              headers: headers,
              body: body
            }));
            if (typeof res === 'string') res = JSON.parse(res);
            return res;
         } catch(e) {
            console.error("HTTP Bridge Error: " + e);
            return { status: 0, statusCode: 0, body: "", error: e.toString() };
         }
      }

      function http_get(url, headers, cb) {
         var promise = _dartHttp('GET', url, headers, null).then(function(res) {
            if (cb && typeof cb === 'function') cb(res);
            return res.body;
         });
         return promise;
      }
      
      async function _fetch(url) {
          return await http_get(url, {});
      }
      
      function http_post(url, headers, body, cb) {
         var promise = _dartHttp('POST', url, headers, body).then(function(res) {
            if (cb && typeof cb === 'function') cb(res);
            return res.body;
         });
         return promise;
      }
    """);

    // 2. Timer Polyfill (Bridged)
    _runtime.evaluate("""
      globalThis.timeout_registry = {};

    function setTimeout(callback, delay) {
      var id = "t_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
      globalThis.timeout_registry[id] = function() {
        if (!globalThis.timeout_registry[id]) return;
        delete globalThis.timeout_registry[id];
        try { callback(); } catch (e) { console.error('Timeout error:', e); }
      };
      sendMessage('js_set_timeout', JSON.stringify({ id: id, delay: delay || 0 }));
      return id;
    }

    function clearTimeout(id) {
      if (id) delete globalThis.timeout_registry[id];
    }

    function setInterval(cb, d) {
      var id = "i_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
      var wrapper = function() {
        if (!globalThis.timeout_registry[id]) return;
        try { cb(); } catch (e) { console.error('Interval error:', e); }
        if (globalThis.timeout_registry[id]) {
          sendMessage('js_set_timeout', JSON.stringify({ id: id, delay: d || 0 }));
        }
      };
      globalThis.timeout_registry[id] = wrapper;
      sendMessage('js_set_timeout', JSON.stringify({ id: id, delay: d || 0 }));
      return id;
    }

    function clearInterval(id) {
      clearTimeout(id);
    }

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
      class Actor {
        constructor(params) {
          Object.assign(this, params);
        }
      }

      class Trailer {
        constructor(params) {
          Object.assign(this, params);
        }
      }

      class NextAiring {
        constructor(params) {
          Object.assign(this, params);
        }
      }

      class MultimediaItem {
        constructor(params) {
          Object.assign(this, {
            type: 'movie',
            status: 'ongoing',
            vpnStatus: 'none',
            isAdult: false,
            ...params
          });
        }
      }

      class Episode {
        constructor(params) {
          Object.assign(this, {
            season: 0,
            episode: 0,
            dubStatus: 'none',
            ...params
          });
        }
      }

      class StreamResult {
        constructor({ url, source, quality, headers, subtitles, drmKid, drmKey, licenseUrl }) {
          this.url = url;
          this.source = source || quality || 'Auto';
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
      globalThis.Actor = Actor;
      globalThis.Trailer = Trailer;
      globalThis.NextAiring = NextAiring;

      var CloudStream = {
         getLanguage: function() { return "en"; },
         getRegion: function() { return "US"; }
      };

      // Native SDK Parity Helpers
      globalThis.registerSettings = function(schema) {
         sendMessage('register_settings', JSON.stringify(schema));
      };

      globalThis.solveCaptcha = async function(siteKey, url) {
         return await sendMessage('solve_captcha', JSON.stringify({ siteKey: siteKey, url: url || "" }));
      };

      globalThis.crypto = {
         decryptAES: async function(data, key, iv) {
            return await sendMessage('crypto_decrypt_aes', JSON.stringify({ data: data, key: key, iv: iv }));
         }
      };

      // JSDOM Polyfill
      globalThis.JSDOM = class JSDOM {
        constructor(html) {
          var id = sendMessage('dom_parse', JSON.stringify({ html: html }));
          this.window = { document: new JSDocument(id) };
        }
      };

      class JSNode {
        constructor(nodeId, data) {
          this.nodeId = nodeId;
          this.data = data || {};
          this.textContent = this.data.textContent || "";
          this.innerHTML = this.data.innerHTML || "";
          this.outerHTML = this.data.outerHTML || "";
          this.tagName = this.data.tagName || "";
        }
        get className() {
          return this.getAttribute('class') || "";
        }
        getAttribute(name) {
          return this.data.attributes ? this.data.attributes[name] : null;
        }
        querySelector(query) {
          var res = sendMessage('dom_query', JSON.stringify({ nodeId: this.nodeId, query: query, multi: false }));
          if (typeof res === 'string') res = JSON.parse(res);
          return res ? new JSNode(res.nodeId, res) : null;
        }
        querySelectorAll(query) {
          var res = sendMessage('dom_query', JSON.stringify({ nodeId: this.nodeId, query: query, multi: true }));
          if (typeof res === 'string') res = JSON.parse(res);
          return (res || []).map(d => new JSNode(d.nodeId, d));
        }
      }

      class JSDocument extends JSNode {
        constructor(id) {
          super(id, { nodeId: id });
        }
        get body() {
          return this.querySelector('body');
        }
      }

      // atob/btoa polyfills using bridge
      globalThis.atob = function(str) {
        return sendMessage('base64_decode', str);
      };
      globalThis.btoa = function(str) {
        return sendMessage('base64_encode', str);
      };

      // URL Polyfill
      globalThis.URL = class URL {
        constructor(url, base) {
          this.href = url;
          if (base) {
             // Basic support for base relative URLs
             if (!url.startsWith('http')) {
                var baseObj = new URL(base);
                if (url.startsWith('/')) {
                   this.href = baseObj.origin + url;
                } else {
                   this.href = baseObj.origin + baseObj.pathname.substring(0, baseObj.pathname.lastIndexOf('/') + 1) + url;
                }
             }
          }
          
          var match = this.href.match(/^([^:/?#]+:)?(\\/\\/([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?/);
          if (!match) throw new Error("Invalid URL");
          
          this.protocol = match[1] || "";
          this.host = match[3] || "";
          this.pathname = match[4] || "/";
          this.search = match[5] || "";
          this.hash = match[7] || "";
          
          var hostParts = this.host.split(':');
          this.hostname = hostParts[0];
          this.port = hostParts[1] || "";
          this.origin = this.protocol + "//" + this.host;
        }
        toString() { return this.href; }
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

      final Map<String, dynamic> finalHeaders = headers ?? {};
      if (!finalHeaders.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        finalHeaders['User-Agent'] =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36";
      }

      debugPrint("[JS HTTP] $method $url ($requestId)");

      final response = await _dio.request(
        url,
        data: body,
        options: Options(
          method: method,
          headers: finalHeaders,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );

      debugPrint("[JS HTTP] Back $url ($requestId) -> ${response.statusCode}");

      final responseHeaders = response.headers.map.map(
        (k, v) => MapEntry(k, v.join(',')),
      );
      final responseBody = response.data.toString();

      if (CloudflareBypass.instance.isCloudflareChallenge(
        response.statusCode,
        responseHeaders,
        responseBody,
      )) {
        final cfResult = await CloudflareBypass.instance.solveAndFetch(url);
        if (cfResult != null) {
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

      return {
        'code': response.statusCode,
        'statusCode': response.statusCode,
        'status': response.statusCode,
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
    _pendingCallbacks[callbackId] = completer;

    final evalWrapper =
        """
       (function() {
          try {
             var dart_cb = function(res) {
                 executeCallback('$callbackId', res !== undefined ? res : "__dart_void__", null);
             };
             
             var fn = globalThis['$functionName'];
             if (typeof fn !== 'function') {
                 var parts = '$functionName'.split('.');
                 var target = globalThis;
                 for(var i=0; i<parts.length; i++) {
                    target = target[parts[i]];
                 }
                 fn = target;
             }
             
             if (typeof fn !== 'function') throw "Function $functionName not found";

             var args = [$argsStr];
             args.push(dart_cb);
             
             var res = fn.apply(null, args);
             
             if (res && (typeof res.then === 'function' || res instanceof Promise)) {
                res.then(dart_cb).catch(function(err) {
                   executeCallback('$callbackId', null, err.toString());
                });
             } else if (res !== undefined) {
                dart_cb(res);
             }
          } catch(e) {
             executeCallback('$callbackId', null, e.toString());
          }
       })();
     """;

    _runtime.evaluate(evalWrapper);

    Timer? pumpTimer;
    pumpTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (completer.isCompleted) {
        pumpTimer?.cancel();
        return;
      }
      _runtime.executePendingJob();
    });

    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingCallbacks.remove(callbackId);
          throw TimeoutException('Timeout executing $functionName');
        },
      );

      // --- Post-processing (Success) ---
      final bool isManifestRequest = functionName.endsWith("getManifest");
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
      } else {
        unwrapped = result;
      }

      if (!isManifestRequest && unwrapped is Map) {
        final success = unwrapped['success'] ?? false;
        if (!success) {
          final code = unwrapped['errorCode'] ?? 'UNKNOWN_ERROR';
          final message =
              unwrapped['message'] ?? 'An unexpected plugin error occurred';
          throw JsPluginException(code, message);
        }
        return unwrapped['data'];
      } else {
        return unwrapped;
      }
    } finally {
      pumpTimer.cancel();
    }
  }

  Future<dynamic> callFunction(String name, [List<dynamic>? args]) async {
    return invokeAsync(name, args);
  }

  void dispose() {
    _runtime.dispose();
    _pendingCallbacks.clear();
  }

  String _sanitizeLog(dynamic args) {
    final String msg = args.toString();
    if (msg.length > 500 &&
        (msg.toLowerCase().contains("<!doctype html>") ||
            msg.toLowerCase().contains("<html") ||
            msg.contains("</div>"))) {
      return "[HTML Content Omitted - Length: ${msg.length}]";
    }
    if (msg.length > 3000) {
      return "${msg.substring(0, 3000)}... [Truncated]";
    }
    return msg;
  }

  Map<String, dynamic>? _serializeElement(html_dom.Element? element) {
    if (element == null) return null;
    final String nodeId = "node_${DateTime.now().microsecondsSinceEpoch}_${element.hashCode}";
    _domRegistry[nodeId] = element;
    
    return {
      'nodeId': nodeId,
      'tagName': element.localName,
      'attributes': element.attributes.map((k, v) => MapEntry(k.toString(), v)),
      'textContent': element.text,
      'innerHTML': element.innerHtml,
      'outerHTML': element.outerHtml,
    };
  }
}

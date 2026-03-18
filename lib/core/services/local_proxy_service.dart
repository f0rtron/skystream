import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ProxyOptions {
  final List<String> mirrorHosts;
  final List<String> keepCookies;
  final String? referer;

  ProxyOptions({
    this.mirrorHosts = const [],
    this.keepCookies = const [],
    this.referer,
  });

  factory ProxyOptions.fromJson(Map<String, dynamic> json) {
    return ProxyOptions(
      mirrorHosts: (json['mirrorHosts'] as List?)?.map((e) => e.toString()).toList() ?? [],
      keepCookies: (json['keepCookies'] as List?)?.map((e) => e.toString()).toList() ?? [],
      referer: json['referer']?.toString(),
    );
  }
}

class LocalProxyService {
  static final LocalProxyService _instance = LocalProxyService._internal();

  static LocalProxyService get instance => _instance;

  LocalProxyService._internal();

  HttpServer? _server;
  int _serverPort = 0;
  final Map<String, String> _playlists = {};

  static const int _maxPlaylists = 50;

  int get port => _serverPort;

  Future<void> startServer() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _serverPort = _server!.port;
      if (kDebugMode) debugPrint("LocalProxyService: Started on port $_serverPort");

      _server!.listen(_handleRequest);
    } catch (e) {
      if (kDebugMode) debugPrint("LocalProxyService: Failed to start server: $e");
    }
  }

  /// Stores a generated M3U8 content and returns the local URL to access it.
  String serveM3u8(String content) {
    if (_server == null) startServer(); // Ensure started

    // Evict oldest entries if at capacity
    while (_playlists.length >= _maxPlaylists) {
      _playlists.remove(_playlists.keys.first);
    }

    final uuid =
        "${DateTime.now().millisecondsSinceEpoch}_${(content.length % 1000)}";
    _playlists[uuid] = content;
    return "http://127.0.0.1:$_serverPort/$uuid.m3u8";
  }

  /// Returns a proxied URL for the given target URL, with optional sticky headers and options.
  String getProxyUrl(String targetUrl, {Map<String, String>? headers, ProxyOptions? options}) {
    if (_server == null) startServer();
    final encoded = Uri.encodeComponent(targetUrl);
    String url = "http://127.0.0.1:$_serverPort/proxy?url=$encoded";
    
    if (headers != null && headers.isNotEmpty) {
      final headerJson = jsonEncode(headers);
      final headerB64 = base64Url.encode(utf8.encode(headerJson));
      url += "&h=$headerB64";
    }

    if (options != null) {
      final optJson = jsonEncode({
        'mirrorHosts': options.mirrorHosts,
        'keepCookies': options.keepCookies,
        'referer': options.referer,
      });
      final optB64 = base64Url.encode(utf8.encode(optJson));
      url += "&o=$optB64";
    }
    
    return url;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      // PROXY HANDLER
      if (path == '/proxy') {
        await _handleProxyRequest(request);
        return;
      }

      // M3U8 HANDLER
      // Expected path: /<uuid>.m3u8
      if (path.length > 1 && path.endsWith('.m3u8')) {
        await _handlePlaylistRequest(request, path);
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
    } catch (e) {
      if (kDebugMode) debugPrint("LocalProxyService: Server Error: $e");
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      } catch (e) {
        if (kDebugMode) debugPrint('LocalProxyService._handleRequest: error response failed: $e');
      }
    }
  }

  Future<void> _handlePlaylistRequest(HttpRequest request, String path) async {
    final uuid = path.substring(1).replaceAll(".m3u8", "");
    if (_playlists.containsKey(uuid)) {
      final content = _playlists[uuid]!;
      request.response.headers.contentType = ContentType(
        "application",
        "vnd.apple.mpegurl",
      );
      request.response.headers.add("Access-Control-Allow-Origin", "*");
      request.response.write(content);
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    request.response.close();
  }

  Future<void> _handleProxyRequest(HttpRequest request) async {
    final targetUrl = request.uri.queryParameters['url'];
    if (targetUrl == null) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.close();
      return;
    }

    // debugPrint("[PROXY] Incoming Request for: $targetUrl");

    final Map<String, String> stickyHeaders = {};
    final hBase64 = request.uri.queryParameters['h'];
    if (hBase64 != null) {
      try {
        final decoded = utf8.decode(base64Url.decode(hBase64));
        final Map<String, dynamic> map = jsonDecode(decoded);
        map.forEach((key, value) => stickyHeaders[key] = value.toString());
      } catch (e) {
        if (kDebugMode) debugPrint("[PROXY] Failed to parse sticky headers: $e");
      }
    }

    ProxyOptions? options;
    final oBase64 = request.uri.queryParameters['o'];
    if (oBase64 != null) {
      try {
        final decoded = utf8.decode(base64Url.decode(oBase64));
        options = ProxyOptions.fromJson(jsonDecode(decoded));
      } catch (e) {
        if (kDebugMode) debugPrint("[PROXY] Failed to parse options: $e");
      }
    }

    final client = HttpClient();
    client.autoUncompress = true; // Handle gzipped M3U8/Segments correctly
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final req = await client.getUrl(Uri.parse(targetUrl));
      
      // Check if this is an M3U8 request to handle Range headers and rewriting
      final isRequestM3u8 = targetUrl.toLowerCase().contains(".m3u8");

      // 1. Process incoming request headers first (Player headers)
      final Map<String, String> mergedCookies = {};
      request.headers.forEach((name, values) {
        final lowerName = name.toLowerCase();
        if (lowerName == 'cookie') {
          for (var v in values) {
            for (var pair in v.split(';')) {
              final parts = pair.split('=');
              if (parts.length >= 2) {
                mergedCookies[parts[0].trim()] = parts.sublist(1).join('=').trim();
              }
            }
          }
        } else if (lowerName == 'range' && isRequestM3u8) {
          // debugPrint("[PROXY] Stripping Range header for M3U8 request to force status 200");
          // Skip Range header for M3U8 to ensure we get the full file for rewriting
        } else if (lowerName != 'host' &&
            lowerName != 'content-length' &&
            lowerName != 'connection' &&
            lowerName != 'accept-encoding' &&
            lowerName != 'referer' && 
            lowerName != 'user-agent') {
          for (var value in values) {
            req.headers.add(name, value);
          }
        }
      });

      // 2. Process Sticky Headers (Plugin headers - Priority)
      stickyHeaders.forEach((name, value) {
        final lowerName = name.toLowerCase();
        if (lowerName == 'cookie') {
          for (var pair in value.split(';')) {
            final parts = pair.split('=');
            if (parts.length >= 2) {
              mergedCookies[parts[0].trim()] = parts.sublist(1).join('=').trim();
            }
          }
        } else {
          req.headers.set(name, value);
        }
      });

      // 3. Set Merged Cookies
      if (mergedCookies.isNotEmpty) {
        final cookieString = mergedCookies.entries.map((e) => "${e.key}=${e.value}").join("; ");
        req.headers.set("Cookie", cookieString);
        // debugPrint("[PROXY] Final Cookie String: $cookieString");
      }

      // 4. Sanitize and Default Headers
      _applySanitizedHeaders(req, targetUrl, options);

      // debugPrint("[PROXY] Fetching with headers: ${req.headers}");
      final response = await _fetchWithRedirects(client, req, targetUrl, options);
      // debugPrint("[PROXY] Response Status: ${response.statusCode}, Content-Type: ${response.headers.contentType}");

      request.response.statusCode = response.statusCode;
      
      // Copy ALL relevant headers from source response
      response.headers.forEach((name, values) {
        final lowerName = name.toLowerCase();
        if (lowerName != 'transfer-encoding' && 
            lowerName != 'access-control-allow-origin') {
          for (var value in values) {
            request.response.headers.add(name, value);
          }
        }
      });
      request.response.headers.add("Access-Control-Allow-Origin", "*");

      // RECURSIVE REWRITE for M3U8
      final isResponseM3u8 = _isM3u8(response.headers.contentType?.mimeType, targetUrl);
      // debugPrint("[PROXY] Detected isM3u8: $isResponseM3u8 for $targetUrl");

      // Allow rewriting for 200 (OK) and 206 (Partial) if it's an M3U8
      if (isResponseM3u8 && (response.statusCode == 200 || response.statusCode == 206)) {
        // debugPrint("[PROXY] Triggering M3U8 rewrite for: $targetUrl");
        // If rewriting, we must remove content-encoding and content-length 
        // because the modified body will have different length/type.
        request.response.headers.removeAll('content-encoding');
        request.response.headers.removeAll('content-length');
        await _rewriteM3u8Response(response, request, targetUrl, stickyHeaders, options);
      } else {
        // if (isResponseM3u8) debugPrint("[PROXY] Skipping rewrite (status ${response.statusCode})");
        // Pipe binary data
        await response.pipe(request.response);
      }
    } catch (e) {
      if (kDebugMode) debugPrint("LocalProxyService: Proxy Request Error: $e");
      request.response.statusCode = HttpStatus.badGateway;
      request.response.close();
    }
  }

  void _applySanitizedHeaders(HttpClientRequest req, String targetUrl, ProxyOptions? options) {
      // Default User-Agent if missing
      if (req.headers['User-Agent'] == null) {
        req.headers.set("User-Agent", "Mozilla/5.0 (Android) ExoPlayer");
      }

      // Default Referer if missing or proxy-based
      final existingReferer = req.headers['Referer']?.join("");
      if (existingReferer == null || existingReferer.contains("127.0.0.1")) {
          final uri = Uri.parse(targetUrl);
          final optReferer = options?.referer;
          if (optReferer != null) {
             req.headers.set("Referer", optReferer);
          } else {
             req.headers.set("Referer", "${uri.scheme}://${uri.host}/");
          }
      }

      // CLEANUP: If target is CDN, remove session cookies (Mirror's security requirement)
      // NOTE: For NetMirror, we actually WANT to keep cookies for their specific CDNs if possible,
      // as they sometimes validate both the 'in' param and the 't_hash_t' cookie.
      final targetUri = Uri.parse(targetUrl);
      bool isMirrorSite = false;
      if (options != null) {
          isMirrorSite = options.mirrorHosts.any((host) => targetUri.host.contains(host));
      }
      
      if (!isMirrorSite) {
          final currentCookies = req.headers['Cookie']?.join("; ") ?? "";
          if (options != null && options.keepCookies.isNotEmpty) {
             final filtered = currentCookies.split(';')
              .map((s) => s.trim())
              .where((s) {
                 final key = s.split('=')[0];
                 return options.keepCookies.contains(key);
              })
              .join("; ");
              if (filtered.isNotEmpty) {
                  req.headers.set("Cookie", filtered);
              } else {
                  req.headers.removeAll("Cookie");
              }
          } else {
             req.headers.removeAll("Cookie");
          }
      }

      // Default hd=on if keepCookies contains it
      if (options != null && options.keepCookies.contains("hd")) {
          final finalCookies = req.headers['Cookie']?.join("; ") ?? "";
          if (!finalCookies.contains("hd=on")) {
            if (finalCookies.isEmpty) {
              req.headers.set("Cookie", "hd=on");
            } else {
              req.headers.set("Cookie", "$finalCookies; hd=on");
            }
          }
      }
  }

  /// Manually follow redirects to ensure headers (Referer/User-Agent) are preserved
  Future<HttpClientResponse> _fetchWithRedirects(HttpClient client, HttpClientRequest initialRequest, String currentUrl, ProxyOptions? options) async {
    HttpClientRequest currentReq = initialRequest;
    currentReq.followRedirects = false; // We handle it
    
    int redirectCount = 0;
    const maxRedirects = 5;

    while (redirectCount < maxRedirects) {
      final response = await currentReq.close();
      
      if (response.statusCode == HttpStatus.movedPermanently || 
          response.statusCode == HttpStatus.found ||
          response.statusCode == HttpStatus.seeOther ||
          response.statusCode == HttpStatus.temporaryRedirect ||
          response.statusCode == HttpStatus.permanentRedirect) {
        
        final location = response.headers.value('location');
        if (location == null) return response;

        final nextUrl = Uri.parse(currentUrl).resolve(location).toString();
        redirectCount++;
        
        final nextReq = await client.getUrl(Uri.parse(nextUrl));
        nextReq.followRedirects = false;

        // PRESERVE CRITICAL HEADERS
        initialRequest.headers.forEach((name, values) {
          final lowerName = name.toLowerCase();
          if (lowerName != 'host' && lowerName != 'content-length' && lowerName != 'connection') {
            for (var v in values) {
              nextReq.headers.add(name, v);
            }
          }
        });
        
        // RE-APPLY SANITIZATION for the nextHop (especially cleaning cookies for CDNs)
        _applySanitizedHeaders(nextReq, nextUrl, options);

        currentReq = nextReq;
        currentUrl = nextUrl;
      } else {
        return response;
      }
    }
    
    throw Exception("Too many redirects");
  }

  bool _isM3u8(String? mimeType, String url) {
    return (mimeType == "application/vnd.apple.mpegurl" ||
        mimeType == "application/x-mpegurl" ||
        mimeType == "audio/x-mpegurl" ||
        mimeType == "video/x-mpegurl" ||
        url.contains(".m3u8") ||
        url.contains(".m3u"));
  }

  Future<void> _rewriteM3u8Response(
    HttpClientResponse sourceResponse,
    HttpRequest clientRequest,
    String originalUrl,
    Map<String, String> stickyHeaders,
    ProxyOptions? options,
  ) async {
    final contentBytes = await sourceResponse.toList();
    final allBytes = contentBytes.expand((x) => x).toList();

    if (!_isValidM3u8(allBytes)) {
      // debugPrint("[PROXY] M3U8 Validation Failed for: $originalUrl");
      // Fallback to binary pipe
      clientRequest.response.add(allBytes);
      await clientRequest.response.close();
      return;
    }

    final content = utf8.decode(allBytes, allowMalformed: true);
    // debugPrint("[PROXY] Rewriting M3U8 content (${content.length} chars)");
    final baseUrl = Uri.parse(originalUrl);

    final rewritten = content
        .split('\n')
        .map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return line;

          if (trimmed.startsWith("#")) {
            if (trimmed.contains('URI="')) {
              return trimmed.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (
                match,
              ) {
                final uri = match.group(1)!;
                final r = _rewriteUrl(uri, baseUrl, stickyHeaders, options);
                // debugPrint("[PROXY] Rewrote Tag URI: $uri");
                return 'URI="$r"';
              });
            }
            return line;
          }

          // Segment URL
          final r = _rewriteUrl(trimmed, baseUrl, stickyHeaders, options, isSegment: true);
          // debugPrint("[PROXY] Rewrote Segment: $trimmed");
          return r;
        })
        .join('\n');

    clientRequest.response.write(rewritten);
    await clientRequest.response.close();
    // debugPrint("[PROXY] M3U8 Rewrite Complete for: $originalUrl");
  }

  bool _isValidM3u8(List<int> bytes) {
    try {
      if (bytes.length > 7) {
        // final prefix = utf8.decode(bytes.take(20).toList(), allowMalformed: true).trim();
        // debugPrint("[PROXY] M3U8 Prefix Check: '$prefix'");
        return utf8.decode(bytes.take(7).toList(), allowMalformed: true).contains("#EXT");
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LocalProxyService._isValidM3u8: $e');
    }
    return false;
  }

  String _rewriteUrl(String uri, Uri baseUrl, Map<String, String> stickyHeaders, ProxyOptions? options, {bool isSegment = false}) {
    try {
      Uri resolved = baseUrl.resolve(uri);
      
      // Generic Mirror Security: If the resolved URL is relative (same host) OR on a mirror host
      // and has no query, it MUST inherit the query params from the parent playlist.
      bool isHostMatch = false;
      if (options != null) {
          isHostMatch = options.mirrorHosts.any((host) => resolved.host.contains(host));
      }
      
      if (resolved.query.isEmpty && baseUrl.query.isNotEmpty && (resolved.host == baseUrl.host || isHostMatch)) {
          resolved = resolved.replace(query: baseUrl.query);
      }
      return getProxyUrl(resolved.toString(), headers: stickyHeaders, options: options); // Recursive proxy with headers and options
    } catch (e) {
      return uri;
    }
  }
}

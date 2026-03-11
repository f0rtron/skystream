import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
      debugPrint("LocalProxyService: Started on port $_serverPort");

      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint("LocalProxyService: Failed to start server: $e");
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

  /// Returns a proxied URL for the given target URL.
  String getProxyUrl(String targetUrl) {
    if (_server == null) startServer();
    final encoded = Uri.encodeComponent(targetUrl);
    return "http://127.0.0.1:$_serverPort/proxy?url=$encoded";
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
      debugPrint("LocalProxyService: Server Error: $e");
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      } catch (e) {
        debugPrint('LocalProxyService._handleRequest: error response failed: $e');
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

    final client = HttpClient();
    client.autoUncompress = true;
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final req = await client.getUrl(Uri.parse(targetUrl));
      // Hardcoded headers for Disney+ (Legacy support)
      req.headers.add("Cookie", "hd=on");
      req.headers.add("Referer", "https://net51.cc/home");
      req.headers.add(
        "User-Agent",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36",
      );

      final response = await req.close();

      request.response.statusCode = response.statusCode;
      final contentTypeHeader = response.headers.contentType;
      final mimeType = contentTypeHeader?.mimeType.toLowerCase();

      request.response.headers.add("Access-Control-Allow-Origin", "*");
      if (contentTypeHeader != null) {
        request.response.headers.contentType = contentTypeHeader;
      }

      // RECURSIVE REWRITE for M3U8
      final isM3u8 = _isM3u8(mimeType, targetUrl);

      // debugPrint("Proxy: $targetUrl | $mimeType | isM3u8: $isM3u8");

      if (isM3u8 && response.statusCode == 200) {
        await _rewriteM3u8Response(response, request, targetUrl);
      } else {
        // Pipe binary data
        await response.pipe(request.response);
      }
    } catch (e) {
      debugPrint("LocalProxyService: Proxy Request Error: $e");
      request.response.statusCode = HttpStatus.badGateway;
      request.response.close();
    }
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
  ) async {
    final contentBytes = await sourceResponse.toList();
    final allBytes = contentBytes.expand((x) => x).toList();

    if (!_isValidM3u8(allBytes)) {
      // Fallback to binary pipe
      clientRequest.response.add(allBytes);
      await clientRequest.response.close();
      return;
    }

    final content = utf8.decode(allBytes, allowMalformed: true);
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
                return _rewriteUrl(uri, baseUrl);
              });
            }
            return line;
          }

          // Segment URL
          return _rewriteUrl(trimmed, baseUrl, isSegment: true);
        })
        .join('\n');

    clientRequest.response.write(rewritten);
    await clientRequest.response.close();
  }

  bool _isValidM3u8(List<int> bytes) {
    try {
      if (bytes.length > 7) {
        final prefix = utf8.decode(bytes.take(7).toList());
        return prefix.startsWith("#EXT");
      }
    } catch (e) {
      debugPrint('LocalProxyService._isValidM3u8: $e');
    }
    return false;
  }

  String _rewriteUrl(String uri, Uri baseUrl, {bool isSegment = false}) {
    try {
      final absoluteUrl = baseUrl.resolve(uri).toString();
      return getProxyUrl(absoluteUrl); // Recursive proxy
    } catch (e) {
      return uri;
    }
  }
}

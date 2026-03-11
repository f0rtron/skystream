import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Cross-platform Cloudflare JS challenge bypass.
///
/// Strategy: When a CF challenge is detected, load the URL in a headless
/// WebView. The WebView's browser engine solves the challenge automatically.
/// Once solved, extract the page HTML directly from the WebView DOM —
/// avoiding TLS fingerprinting issues that occur when retrying with Dio.
class CloudflareBypass {
  CloudflareBypass._();
  static final instance = CloudflareBypass._();

  static const _tag = '[CF Bypass]';
  static const _cfErrorCodes = [403, 503];
  static const _cfServers = ['cloudflare-nginx', 'cloudflare'];
  static const _timeout = Duration(seconds: 60);
  static const _pollInterval = Duration(milliseconds: 200);

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  /// Returns true if the response is a Cloudflare JS challenge.
  bool isCloudflareChallenge(
    int? statusCode,
    Map<String, dynamic> headers,
    String body,
  ) {
    if (statusCode == null || !_cfErrorCodes.contains(statusCode)) return false;

    // Check server header
    final server = _headerValue(headers, 'server');
    if (server == null ||
        !_cfServers.any((s) => server.toLowerCase().contains(s))) {
      return false;
    }

    // Check for CF challenge markers in body
    return body.contains('Just a moment') ||
        body.contains('cf-mitigated') ||
        body.contains('_cf_chl_opt') ||
        body.contains('challenge-platform');
  }

  // ---------------------------------------------------------------------------
  // Solver — returns the actual page HTML, not just cookies
  // ---------------------------------------------------------------------------

  /// Whether a solve is currently in progress for a given host
  final Map<String, Completer<CfResult?>> _activeSolves = {};

  /// Solves the CF challenge and returns the actual page HTML + response info.
  ///
  /// Instead of extracting cookies and retrying with Dio (which fails due to
  /// TLS fingerprinting), we extract the HTML directly from the WebView DOM.
  Future<CfResult?> solveAndFetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host;

    // If already solving for this host, wait for the existing solve
    if (_activeSolves.containsKey(host)) {
      if (kDebugMode) debugPrint('$_tag Already solving for $host, waiting...');
      return _activeSolves[host]!.future;
    }

    final completer = Completer<CfResult?>();
    _activeSolves[host] = completer;

    try {
      final result = await _fetchViaWebView(url);
      if (result != null) {
        if (kDebugMode) {
          debugPrint('$_tag Solved for $host, got ${result.body.length} chars');
        }
      } else {
        if (kDebugMode) debugPrint('$_tag Failed to solve for $host');
      }
      completer.complete(result);
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('$_tag Error solving for $host: $e');
      completer.complete(null);
      return null;
    } finally {
      _activeSolves.remove(host);
    }
  }

  // ---------------------------------------------------------------------------
  // HeadlessInAppWebView — solve challenge & extract HTML
  // ---------------------------------------------------------------------------

  Future<CfResult?> _fetchViaWebView(String url) async {
    if (kDebugMode) debugPrint('$_tag Starting headless WebView for $url');

    // Linux doesn't support HeadlessInAppWebView
    if (!kIsWeb && Platform.isLinux) {
      if (kDebugMode) debugPrint('$_tag Linux: headless WebView not supported');
      return null;
    }

    HeadlessInAppWebView? headless;
    CfResult? result;
    bool solved = false;
    String? finalUrl;

    try {
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          // Don't set custom user-agent — CF checks for consistency
          // Allow mixed content
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
        onLoadStop: (controller, loadedUrl) async {
          finalUrl = loadedUrl?.toString() ?? url;

          // Check if we're still on the challenge page
          final title = await controller.getTitle();
          if (title == 'Just a moment...' || title == null || title.isEmpty) {
            // Still on challenge page — wait for redirect
            if (kDebugMode) debugPrint('$_tag Still on challenge page...');
            return;
          }

          // Challenge solved! Extract the page HTML from DOM
          try {
            final html = await controller.evaluateJavascript(
              source: 'document.documentElement.outerHTML',
            );
            if (html != null && html.toString().isNotEmpty) {
              final body = html.toString();
              // Verify it's the real page, not the challenge
              if (!body.contains('_cf_chl_opt') &&
                  !body.contains('Just a moment')) {
                result = CfResult(
                  body: body,
                  statusCode: 200,
                  finalUrl: finalUrl ?? url,
                );
                solved = true;
                if (kDebugMode) {
                  debugPrint('$_tag Page title: "$title" — extracted HTML');
                }
              }
            }
          } catch (e) {
            if (kDebugMode) debugPrint('$_tag HTML extraction error: $e');
          }
        },
        onReceivedError: (controller, request, error) {
          if (kDebugMode) {
            debugPrint('$_tag WebView error: ${error.description}');
          }
        },
      );

      await headless.run();

      // Poll until solved or timeout
      final deadline = DateTime.now().add(_timeout);
      while (!solved && DateTime.now().isBefore(deadline)) {
        await Future.delayed(_pollInterval);
      }

      if (!solved) {
        if (kDebugMode) {
          debugPrint('$_tag Timed out after ${_timeout.inSeconds}s');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('$_tag HeadlessWebView error: $e');
    } finally {
      try {
        await headless?.dispose();
      } catch (e) {
        debugPrint('CloudflareBypass: headless dispose error: $e');
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String? _headerValue(Map<String, dynamic> headers, String key) {
    final value = headers[key] ?? headers[key.toLowerCase()];
    if (value == null) return null;
    if (value is List) return value.isNotEmpty ? value.first.toString() : null;
    return value.toString();
  }
}

/// Result from a CF bypass — contains the actual page HTML.
class CfResult {
  final String body;
  final int statusCode;
  final String finalUrl;

  const CfResult({
    required this.body,
    required this.statusCode,
    required this.finalUrl,
  });
}

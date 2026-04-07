import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Cross-platform Cloudflare JS challenge bypass.
class CloudflareBypass {
  CloudflareBypass._();
  static final instance = CloudflareBypass._();

  static const _tag = '[CF Bypass]';
  static const _cfErrorCodes = [403, 503];
  static const _cfServers = ['cloudflare-nginx', 'cloudflare'];
  static const _timeout = Duration(seconds: 60);
  static const _navTimeout = Duration(seconds: 20);
  static const _pollInterval = Duration(milliseconds: 200);

  // ---------------------------------------------------------------------------
  // State Management
  // ---------------------------------------------------------------------------

  /// Active background WebView sessions indexed by normalized host.
  final Map<String, _HostWebView> _hostWebViews = {};

  /// Futures for in-progress operations (solves or navigations) to prevent concurrency issues.
  final Map<String, Future<dynamic>> _locks = {};

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  bool isCloudflareChallenge(
    int? statusCode,
    Map<String, dynamic> headers,
    String body,
  ) {
    if (statusCode == null || !_cfErrorCodes.contains(statusCode)) return false;

    final server = _headerValue(headers, 'server');
    if (server == null ||
        !_cfServers.any((s) => server.toLowerCase().contains(s))) {
      return false;
    }

    return body.contains('Just a moment') ||
        body.contains('cf-mitigated') ||
        body.contains('_cf_chl_opt') ||
        body.contains('challenge-platform');
  }

  // ---------------------------------------------------------------------------
  // Solver
  // ---------------------------------------------------------------------------

  /// Solves the CF challenge and returns the actual page HTML.
  Future<CfResult?> solveAndFetch(
    String url, {
    Future<void> Function(String host)? onSolved,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final rawHost = uri.host;
    if (rawHost.isEmpty) return null;
    final host = _normalizeHost(rawHost);

    // Serialize all operations for this host to avoid race conditions.
    final prevLock = _locks[host] ?? Future.value();
    final completer = Completer<void>();
    _locks[host] = completer.future;

    try {
      await prevLock;

      // 1. Try reusing an existing session
      final existingView = _hostWebViews[host];
      if (existingView != null) {
        if (kDebugMode) debugPrint('$_tag Reusing WebView for $host → $url');
        try {
          final html = await existingView.navigate(url);
          if (html != null) {
            if (!html.contains('_cf_chl_opt') &&
                !html.contains('Just a moment')) {
              return CfResult(body: html, statusCode: 200, finalUrl: url);
            } else {
              if (kDebugMode)
                debugPrint('$_tag Challenge recurred for $host, disposing');
              await _disposeHostSession(host);
            }
          } else {
            // Reused session failed (timeout or dead engine).
            // Proactively dispose and FALL THROUGH to Fresh Solve.
            if (kDebugMode)
              debugPrint('$_tag Reused WebView failed/timed out, falling back');
            await _disposeHostSession(host);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('$_tag Reused WebView error: $e');
          await _disposeHostSession(host);
        }
      }

      // 2. Fresh Solve
      final result = await _fetchViaWebView(url, host);
      if (result != null && onSolved != null) {
        await onSolved(host);
      }
      return result;
    } finally {
      completer.complete();
      if (_locks[host] == completer.future) _locks.remove(host);
    }
  }

  Future<void> _disposeHostSession(String host) async {
    final view = _hostWebViews.remove(host);
    if (view != null) {
      await view.dispose();
    }
  }

  Future<CfResult?> _fetchViaWebView(String url, String host) async {
    if (kDebugMode) debugPrint('$_tag Starting fresh solve for $url');

    final holder = _ViewHolder();
    CfResult? result;
    bool solved = false;
    InAppWebViewController? capturedController;

    Future<void> checkSolved(
      InAppWebViewController controller,
      String? currentUrl,
    ) async {
      try {
        final html = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        final body = html?.toString();

        if (body != null &&
            !body.contains('_cf_chl_opt') &&
            !body.contains('Just a moment')) {
          holder.hostView?.onLoaded(body);
        }

        if (solved) return;
        final title = await controller.getTitle();
        if (title == null ||
            title.isEmpty ||
            title.toLowerCase().contains('cloudflare') ||
            title.contains('Just a moment'))
          return;

        if (body != null &&
            body.isNotEmpty &&
            !body.contains('_cf_chl_opt') &&
            !body.contains('Just a moment')) {
          result = CfResult(
            body: body,
            statusCode: 200,
            finalUrl: currentUrl ?? url,
          );
          solved = true;
        }
      } catch (_) {}
    }

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
      onWebViewCreated: (c) => capturedController = c,
      onLoadStop: (c, u) => checkSolved(c, u?.toString()),
      onTitleChanged: (c, t) {
        if (!solved) checkSolved(c, null);
      },
      onProgressChanged: (c, p) {
        if (p == 100) checkSolved(c, null);
      },
      onReceivedError: (c, r, e) {
        final isCancel =
            e.type == -999 ||
            e.description.contains('-999') ||
            e.description.toLowerCase().contains('cancel');
        if (isCancel) return;
        holder.hostView?.onLoaded(null);
      },
    );

    try {
      await headless.run();
      final deadline = DateTime.now().add(_timeout);
      while (!solved && DateTime.now().isBefore(deadline)) {
        await Future.delayed(_pollInterval);
      }

      if (!solved) {
        await headless.dispose();
        return null;
      }

      final hostView = _HostWebView(host, headless, capturedController);
      holder.hostView = hostView;
      _hostWebViews[host] = hostView;
      hostView.startIdleTimer();

      if (kDebugMode) debugPrint('$_tag WebView session ready for $host');
      return result;
    } catch (e) {
      await headless.dispose();
      return null;
    }
  }

  static String _normalizeHost(String host) {
    var h = host.toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  String? _headerValue(Map<String, dynamic> headers, String key) {
    final value = headers[key] ?? headers[key.toLowerCase()];
    if (value == null) return null;
    if (value is List) return value.isNotEmpty ? value.first.toString() : null;
    return value.toString();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _HostWebView {
  final String host;
  final HeadlessInAppWebView _headless;
  final InAppWebViewController? _controller;

  Completer<String?>? _pending;
  bool _disposed = false;
  Timer? _idleTimer;

  static const _idleTimeout = Duration(minutes: 5);

  _HostWebView(this.host, this._headless, this._controller);

  void startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      if (!_disposed) {
        try {
          dispose();
        } catch (e) {
          if (kDebugMode)
            debugPrint('${CloudflareBypass._tag} Idle timer dispose error: $e');
        }
      }
    });
  }

  Future<String?> navigate(String url, {int retries = 1}) async {
    if (_disposed || _controller == null) return null;
    startIdleTimer();

    if (_pending != null && !_pending!.isCompleted) {
      await _pending!.future.catchError((_) => null);
    }

    _pending = Completer<String?>();
    try {
      await _controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      final html = await _pending!.future.timeout(CloudflareBypass._navTimeout);

      if (html == null && retries > 0) {
        await Future.delayed(const Duration(milliseconds: 500));
        return navigate(url, retries: retries - 1);
      }
      return html;
    } on TimeoutException {
      if (!(_pending?.isCompleted ?? true)) _pending!.complete(null);
      return null;
    } catch (e) {
      return null;
    }
  }

  void onLoaded(String? html) {
    if (_pending != null && !_pending!.isCompleted) _pending!.complete(html);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    if (_pending != null && !_pending!.isCompleted) {
      if (kDebugMode)
        debugPrint('${CloudflareBypass._tag} $host: Cancelling active navigation and disposing');
      _pending!.complete(null);
    }
    try {
      if (CloudflareBypass.instance._hostWebViews[host] == this) {
        CloudflareBypass.instance._hostWebViews.remove(host);
      }
      await _headless.dispose();
    } catch (_) {}
  }
}

class _ViewHolder {
  _HostWebView? hostView;
}

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

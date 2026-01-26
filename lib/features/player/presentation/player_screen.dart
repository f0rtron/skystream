import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/storage/storage_service.dart';
import '../../library/presentation/history_provider.dart';
import 'widgets/skystream_player_controls.dart';
import '../../../../features/settings/presentation/player_settings_provider.dart';
import '../../../../core/services/torrent_service.dart';
import '../../../../core/models/torrent_status.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../shared/widgets/tv_input_widgets.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final String videoUrl;

  const PlayerScreen({super.key, required this.item, required this.videoUrl});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  String? _errorMessage;
  bool _isLoading = true;
  // ignore: prefer_typing_uninitialized_variables
  var _historyNotifier;

  late String _playerTitle;
  String? _streamSubtitle;
  List<StreamResult> _streams = [];
  StreamResult? _currentStream; // Current active stream
  StreamResult? _previousStream; // Last active stream before manual switch
  bool _isManualSwitch = false; // Flag to track manual switching
  List<SubtitleFile> _externalSubtitles = [];
  BoxFit _videoFit = BoxFit.contain;
  bool _controlsVisible = true;

  final GlobalKey<SkyStreamPlayerControlsState> _controlsKeyFinal = GlobalKey();

  Timer? _progressTimer;
  bool _isTv = false;
  String? _cachedProviderId;

  late final FocusNode _skipFocusNode;

  @override
  void initState() {
    super.initState();
    _skipFocusNode = FocusNode(onKeyEvent: _handleSkipFocusKey);
    MediaKit.ensureInitialized();
    //...
    _historyNotifier = ref.read(watchHistoryProvider.notifier);
    _isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;
    _cachedProviderId = ref.read(activeProviderStateProvider)?.id;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _playerTitle = widget.item.title;

    // Resolve Episode Title if Series
    if (widget.item.episodes != null && widget.item.episodes!.isNotEmpty) {
      if (widget.item.episodes!.length > 1) {
        try {
          final ep = widget.item.episodes!.firstWhere(
            (e) => e.url == widget.videoUrl,
            orElse: () => widget.item.episodes!.first,
          );

          if (ep.url == widget.videoUrl) {
            String epTitle = "";
            if (ep.season > 0 && ep.episode > 0) {
              epTitle = "S${ep.season}:E${ep.episode}";
            } else if (ep.episode > 0) {
              epTitle = "E${ep.episode}";
            }

            if (ep.name.isNotEmpty && ep.name != "Episode ${ep.episode}") {
              epTitle = "$epTitle - ${ep.name}";
            }

            if (epTitle.isNotEmpty) {
              if (epTitle.startsWith(" - ")) epTitle = epTitle.substring(3);
              _playerTitle = "${widget.item.title} $epTitle";
            }
          }
        } catch (_) {}
      }
    }

    // Initialize player with larger buffer for torrent streaming
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024, // 128MB
        logLevel: MPVLogLevel.info, // Enable logging for debugging
      ),
    );

    // Increase network timeout to allow TorrServer to pre-buffer
    if (_player.platform is NativePlayer) {
      (_player.platform as NativePlayer).setProperty('network-timeout', '100');
    }
    _videoController = VideoController(_player);

    final settings = ref.read(playerSettingsProvider);
    if (settings.defaultResizeMode == "Zoom") {
      _videoFit = BoxFit.cover;
    } else if (settings.defaultResizeMode == "Stretch")
      _videoFit = BoxFit.fill;

    _initPlayer();

    // Hide loading when video is ready
    _player.stream.videoParams.listen((args) {
      if (args.w != null && args.w! > 0) {
        if (mounted && _isLoading) {
          setState(() => _isLoading = false);
        }
      }
    });

    // Auto-skip on player error
    _player.stream.error.listen((error) {
      debugPrint("Player Error: $error");

      // Ignore errors during intentional stream changes or minor interruptions
      if (_isOpeningStream) return;
      if (error.toString().toLowerCase().contains("abort")) return;

      if (mounted && _isLoading) {
        if (_isManualSwitch) {
          _revertToPreviousStream("Stream failed. Reverting...");
        } else {
          _retryNextStream();
        }
      }
    });

    // Periodic progress save (every 10 seconds)
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveProgress();
    });
  }

  KeyEventResult _handleSkipFocusKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _controlsKeyFinal.currentState?.focusBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int _currentStreamIndex = 0;
  bool _forceShowControls = false;

  TorrentStatus? _torrentStatus;
  Timer? _torrentPollTimer;

  void _startTorrentPolling([String? activeStreamUrl]) {
    _torrentPollTimer?.cancel();

    Future<void> poll() async {
      if (!mounted) return;
      final status = await TorrentService().getCurrentStatus();
      if (mounted && status != null) {
        // Try to update title if we are playing a file
        final urlToCheck = activeStreamUrl ?? _currentStream?.url;
        if (urlToCheck?.contains("index=") ?? false) {
          try {
            final uri = Uri.parse(urlToCheck!);
            final indexStr = uri.queryParameters['index'];
            if (indexStr != null) {
              final index = int.tryParse(indexStr);
              final files = status.data['file_stats'] as List<dynamic>?;
              final file = files?.firstWhere(
                (f) => f['id'] == index,
                orElse: () => null,
              );
              if (file != null) {
                final name = (file['path'] as String).split('/').last;
                if (_playerTitle != name) {
                  setState(() => _playerTitle = name);
                }
              }
            }
          } catch (_) {}
        }

        setState(() {
          _torrentStatus = status;
        });
      }
    }

    poll(); // Run immediately
    _torrentPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => poll(),
    );
  }

  Future<void> _initPlayer() async {
    // 1. Handle Special Providers (Local, Torrent, Remote)
    if (await _handleSpecialProviders()) return;

    // Resolve Active Provider
    final activeProvider = _resolveProvider();
    if (activeProvider == null) {
      if (mounted) {
        setState(() {
          _errorMessage = "No provider selected.";
          _isLoading = false;
        });
      }
      return;
    }

    try {
      if (widget.videoUrl.isNotEmpty) {
        // Fallback: Check if URL looks like a torrent
        if (await _handleFallbackTorrent()) return;

        // Load Streams from Provider
        final streams = await activeProvider.loadStreams(widget.videoUrl);
        if (streams.isNotEmpty) {
          int initialIndex = _findSavedStreamIndex(streams);

          if (mounted) {
            _streams = streams;
            _currentStreamIndex = initialIndex;
            _loadStreamAtIndex(initialIndex);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading streams: $e");
    }

    // Handle Failure
    if (mounted) {
      setState(() {
        _errorMessage = "No streams found.";
        _isLoading = false;
      });
    }
  }

  /// Handles Local, Torrent, and Remote providers directly.
  /// Returns true if handled, false otherwise.
  Future<bool> _handleSpecialProviders() async {
    if (widget.item.provider == 'Remote' ||
        widget.item.provider == 'Local' ||
        widget.item.provider == 'Torrent') {
      final isTorrent =
          widget.item.provider == 'Torrent' ||
          widget.videoUrl.startsWith("magnet:") ||
          widget.videoUrl.endsWith(".torrent");

      final stream = StreamResult(
        url: widget.videoUrl,
        quality: isTorrent ? "Torrent" : "Video",
        headers: {},
      );

      if (mounted) {
        setState(() {
          _streams = [stream];
          _currentStreamIndex = 0;
        });
        _loadStreamAtIndex(0);
      }
      return true;
    }
    return false;
  }

  /// Handles cases where provider is standard but URL is a torrent/magnet.
  Future<bool> _handleFallbackTorrent() async {
    if (widget.videoUrl.startsWith("magnet:") ||
        widget.videoUrl.endsWith(".torrent")) {
      // Treated as torrent
      if (mounted) {
        // Update state directly, _loadStreamAtIndex will trigger the UI rebuild via setState
        _streams = [
          StreamResult(url: widget.videoUrl, quality: "Torrent", headers: {}),
        ];
        _currentStreamIndex = 0;
        _loadStreamAtIndex(0);
      }
      return true;
    }
    return false;
  }

  SkyStreamProvider? _resolveProvider() {
    final activeState = ref.read(activeProviderStateProvider);
    final manager = ref.read(extensionManagerProvider.notifier);

    if (widget.item.provider != null) {
      try {
        final val = widget.item.provider!;
        return manager.getAllProviders().firstWhere(
          (p) => p.id == val || p.name == val,
        );
      } catch (_) {}
    }
    return activeState;
  }

  int _findSavedStreamIndex(List<StreamResult> streams) {
    int initialIndex = 0;
    try {
      final storage = ref.read(storageServiceProvider);
      final lastUrl = storage.getLastStreamUrl(widget.item.url);
      if (lastUrl != null) {
        final foundIndex = streams.indexWhere((s) => s.url == lastUrl);
        if (foundIndex != -1) {
          initialIndex = foundIndex;
        }
      }
    } catch (e) {
      debugPrint("Error checking saved stream quality: $e");
    }
    return initialIndex;
  }

  Future<void> _applyPlaybackProperties(Map<String, String> headers) async {
    if (_player.platform is! NativePlayer) {
      return;
    }
    final native = _player.platform as NativePlayer;

    if (headers.containsKey('user-agent')) {
      final ua = headers['user-agent']!;
      await native.setProperty('user-agent', ua);
    }

    // Set Referrer (Native property)
    if (headers.containsKey('referer')) {
      final ref = headers['referer']!;
      await native.setProperty('referrer', ref);
    }

    // Set Cookie File for stateful handling (Important for HLS segments)
    try {
      final tempDir = await getTemporaryDirectory();
      final cookieFile = File('${tempDir.path}/mpv_cookies.txt');
      // Ensure file exists (touched)
      if (!await cookieFile.exists()) {
        await cookieFile.create();
      }
      await native.setProperty('cookies-file', cookieFile.path);

      // Also enable cookie-leaking to allow cross-site redirects if needed
      await native.setProperty('cookies-file-access', 'read+write');
    } catch (e) {
      debugPrint("Failed to set cookies-file: $e");
    }

    // Determine Cookie (Case Insensitive Check)
    String? cookieKey;
    for (var k in headers.keys) {
      if (k.toLowerCase() == 'cookie') {
        cookieKey = k;
        break;
      }
    }
  }

  Future<String?> _resolveStreamUrl(StreamResult stream) async {
    // 1. Handle Data URI (Fixed M3U8 from JS)
    // if (stream.url.startsWith("data:")) {
    //   try {
    //     final uri = Uri.parse(stream.url);
    //     final content = uri.data?.contentAsBytes();
    //     if (content != null) {
    //       final tempDir = await getTemporaryDirectory();
    //       final file = File(
    //         '${tempDir.path}/playlist_${DateTime.now().millisecondsSinceEpoch}.m3u8',
    //       );
    //       await file.writeAsBytes(content);
    //       // debugPrint("Resolved Data URI to file: ${file.path}");
    //       return file.path;
    //     }
    //   } catch (e) {
    //     debugPrint("Failed to resolve Data URI: $e");
    //   }
    // }
    // 2. Fallback to existing logic
    return _getPlayableUrl(stream);
  }

  Future<String?> _getPlayableUrl(StreamResult stream) async {
    // Only use TorrentService for actual torrents or magnet links
    // Ordinary local files (starting with /) should NOT go here unless they are .torrent
    if (stream.url.startsWith("magnet:") ||
        stream.url.endsWith(".torrent") ||
        (stream.url.startsWith("/") && stream.quality.contains("Torrent"))) {
      setState(() => _streamSubtitle = "Initializing Torrent Engine...");
      final torrentUrl = await TorrentService().getStreamUrl(stream.url);
      if (torrentUrl != null) {
        // _startTorrentPolling(torrentUrl) - moved to caller to control flow
        return torrentUrl;
      }
      return null;
    }
    return stream.url;
  }

  Future<void> _loadStreamAtIndex(int index) async {
    if (index < 0 || index >= _streams.length) return;

    final stream = _streams[index];
    final rawProviderName =
        widget.item.provider ??
        ref.read(activeProviderStateProvider)?.name ??
        "Unknown";
    final providerName = _getProviderDisplayName(rawProviderName);

    setState(() {
      _currentStreamIndex = index;
      _currentStream = stream;
      _isLoading = true;
      _streamSubtitle = "$providerName - ${stream.quality}";
      _externalSubtitles = stream.subtitles ?? [];
    });

    try {
      final playUrl = await _resolveStreamUrl(stream);
      if (playUrl == null) throw Exception("Failed to resolve stream URL");

      // Start polling with the resolved URL (which has the index)
      if (playUrl.contains("index=")) {
        _startTorrentPolling(playUrl);
      }

      // RESTORE SUBTITLE: It might have been overwritten by "Initializing..."
      setState(() {
        _streamSubtitle = "$providerName - ${stream.quality}";
      });

      final headers = stream.headers ?? {};
      debugPrint("OPENING PLAYER with URL: $playUrl");
      debugPrint("FINAL HEADERS Map: $headers");
      if (headers.containsKey('sec-ch-ua')) {
        debugPrint("SEC-CH-UA check: ${headers['sec-ch-ua']}");
      }

      // Ensure MPV uses these headers for sub-requests (playlists segments)
      await _applyPlaybackProperties(headers);

      await _player.open(Media(playUrl, httpHeaders: headers));

      // Resume logic: Check if we have history for this item
      final storage = ref.read(storageServiceProvider);
      final savedPos = storage.getPosition(widget.item.url);

      if (savedPos > 0) {
        debugPrint("Resuming from position: $savedPos ms");
        await _safeSeekTo(savedPos);
      }
    } catch (e) {
      debugPrint("Stream $index failed: $e");
      // Try next stream
      _retryNextStream();
    }
  }

  void _retryNextStream() {
    if (_currentStreamIndex < _streams.length - 1) {
      _loadStreamAtIndex(_currentStreamIndex + 1);
    } else {
      setState(() {
        _errorMessage = "All streams failed.";
        _isLoading = false;
      });
    }
  }

  bool _isReverting = false; // Prevent double reverts
  bool _isOpeningStream = false; // Guard for transient errors during open

  void _revertToPreviousStream(String reason) {
    if (_previousStream == null || _isReverting) {
      if (_previousStream == null) {
        setState(() {
          _errorMessage = "Stream failed. No fallback available.";
          _isLoading = false;
          _isManualSwitch = false;
        });
      }
      return;
    }

    _isReverting = true;

    // Calculate margins to center the toast with a fixed width of approx 300px
    final screenWidth = MediaQuery.of(context).size.width;
    final double toastWidth = 300.0;
    final double horizontalMargin = (screenWidth > toastWidth)
        ? (screenWidth - toastWidth) / 2
        : 16.0;

    ScaffoldMessenger.of(context).clearSnackBars(); // Clear existing
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reason,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF333333), // Neutral dark grey
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.only(
          left: horizontalMargin,
          right: horizontalMargin,
          bottom: 20,
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    debugPrint("Reverting to previous stream: ${_previousStream?.quality}");
    _changeStream(_previousStream!, isRevert: true);
  }

  Future<void> _changeStream(
    StreamResult stream, {
    bool isRevert = false,
    bool resetPosition = false,
  }) async {
    if (!isRevert) {
      _previousStream = _currentStream;
      _isManualSwitch = true;
    }

    setState(() {
      _isLoading = true;
      _currentStream = stream;
      _externalSubtitles = stream.subtitles ?? [];

      // OPTIMISTIC UPDATE: Update subtitle immediately to reflect target stream
      final rawPName =
          widget.item.provider ??
          ref.read(activeProviderStateProvider)?.name ??
          'Unknown';
      final pName = _getProviderDisplayName(rawPName);
      _streamSubtitle = "$pName - ${stream.quality}";
    });

    final oldPos = _player.state.position;
    _isOpeningStream = true; // Start ignoring transient errors

    try {
      final playUrl = await _resolveStreamUrl(stream);
      if (playUrl == null) throw Exception("Failed to resolve stream URL");

      // Start polling with the resolved URL
      if (playUrl.contains("index=")) {
        _startTorrentPolling(playUrl);
      }

      // RESTORE SUBTITLE
      setState(() {
        final rawPName =
            widget.item.provider ??
            ref.read(activeProviderStateProvider)?.name ??
            'Unknown';
        final pName = _getProviderDisplayName(rawPName);
        _streamSubtitle = "$pName - ${stream.quality}";
      });

      final headers = stream.headers ?? {};

      // Ensure MPV uses these headers for sub-requests (playlists segments)
      await _applyPlaybackProperties(headers);

      await _player.open(Media(playUrl, httpHeaders: headers));

      if (oldPos > Duration.zero && !resetPosition) {
        await _safeSeekTo(oldPos.inMilliseconds);
      } else if (resetPosition) {
        await _player.seek(Duration.zero);
      }

      setState(() {
        _isLoading = false;
        if (isRevert) {
          _isManualSwitch = false;
          _isReverting = false;
        }
      });

      if (!isRevert) _isManualSwitch = false;
    } catch (e) {
      debugPrint("Change stream failed: $e");
      if (isRevert) {
        setState(() {
          _errorMessage = "Revert failed: $e";
          _isReverting = false;
        });
      } else {
        _revertToPreviousStream("Switch failed. Reverting...");
      }
    } finally {
      _isOpeningStream = false; // Resume error listening
    }
  }

  void _updateResizeMode(BoxFit mode) {
    if (mounted) setState(() => _videoFit = mode);
  }

  Future<void> _onTorrentFileSelected(int index) async {
    setState(() => _isLoading = true);
    try {
      final url = await TorrentService().getStreamUrlForFileIndex(index);
      if (url != null && _currentStream != null && mounted) {
        String fileLabel = "Torrent File $index";
        try {
          final files = _torrentStatus?.data['file_stats'] as List<dynamic>?;
          final file = files?.firstWhere(
            (f) => f['id'] == index,
            orElse: () => null,
          );
          if (file != null) {
            fileLabel = (file['path'] as String).split('/').last;
            setState(() => _playerTitle = fileLabel);
          }
        } catch (_) {}

        final newStream = StreamResult(
          url: url,
          quality: "Torrent ($fileLabel)",
          headers: {},
        );
        // ignore: use_build_context_synchronously
        _changeStream(newStream, resetPosition: true);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Failed to switch file: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _saveProgress() {
    try {
      final pos = _player.state.position.inMilliseconds;
      final dur = _player.state.duration.inMilliseconds;

      // Android Logic:
      // Minimum Duration: Must be at least 30 seconds
      if (dur < 30000) {
        return;
      }

      // Calculate percentage
      final double progress = (pos / dur) * 100;

      // Mark as Watched logic
      bool isSeries =
          widget.item.episodes != null && widget.item.episodes!.length > 1;

      // Only remove from history if it's a Movie (or single episode) and finished
      if (progress >= 95 && !isSeries) {
        _historyNotifier.removeFromHistory(widget.item.url);
        return;
      }

      // Save Progress if > 1% or if it's a Series (to track last episode even if just started)
      if (progress > 1 || isSeries) {
        final pId =
            widget.item.provider ??
            _cachedProviderId ?? // Use Cached ID
            'Unknown';
        final itemToSave = widget.item.copyWith(provider: pId);
        _historyNotifier.saveProgress(
          itemToSave,
          pos,
          dur,
          lastStreamUrl: _currentStream?.url,
          lastEpisodeUrl: widget.videoUrl, // Save the Episode URL
        );
      }
    } catch (e) {
      debugPrint("History save failed: $e");
    }
  }

  @override
  void dispose() {
    _torrentPollTimer?.cancel();
    _progressTimer?.cancel();
    _saveProgress(); // Final save on exit

    // Stop torrent server/streaming to release resources
    TorrentService().stop();

    _player.dispose(); // Ensure audio stops
    _skipFocusNode.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (_isTv) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        windowManager.setFullScreen(false);
        if (Platform.isWindows || Platform.isLinux) {
          windowManager.setTitleBarStyle(TitleBarStyle.normal);
        }
      } catch (_) {}
    }
    super.dispose();
  }

  void _togglePlay() {
    _player.playOrPause();
  }

  Future<void> _safeSeekTo(int position) async {
    if (position <= 0) return;

    // Wait for player to know the duration
    try {
      await _player.stream.duration
          .firstWhere((d) => d != Duration.zero)
          .timeout(const Duration(seconds: 10));

      if (_player.state.duration.inMilliseconds > position) {
        await _player.seek(Duration(milliseconds: position));
      } else {
        debugPrint(
          "Saved position ($position) > Duration (${_player.state.duration.inMilliseconds}), ignoring.",
        );
      }
    } catch (e) {
      debugPrint("Timeout waiting for duration or seek failed: $e");
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;

    // TV Navigation Logic
    if (isTv) {
      // If controls are visible, let the focus system handle navigation and selection
      if (_controlsVisible) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
      } else {
        // If controls hidden:
        // Up/Down: Show controls
        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() {
            _controlsVisible = true;
            _forceShowControls = true;
          });
          // Reset force flag after a moment to allow properties to handle visibility
          Future.delayed(
            const Duration(milliseconds: 200),
            () => setState(() => _forceShowControls = false),
          );
          return KeyEventResult.handled;
        }
      }
    }

    // Intercept standard playback keys
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      if (!_controlsVisible) {
        setState(() => _forceShowControls = true);
        Future.delayed(
          const Duration(milliseconds: 100),
          () => setState(() => _forceShowControls = false),
        );
      }
      return KeyEventResult.handled;
    }

    // Toggle Mute
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      _controlsKeyFinal.currentState?.toggleMute();
      return KeyEventResult.handled;
    }

    // Cycle resize modes
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      _controlsKeyFinal.currentState?.cycleResize();
      return KeyEventResult.handled;
    }

    // Toggle Fullscreen
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _controlsKeyFinal.currentState?.toggleFullscreen();
      return KeyEventResult.handled;
    }

    // Volume control (Disable on TV)
    if (!isTv) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _controlsKeyFinal.currentState?.changeVolume(0.05);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _controlsKeyFinal.currentState?.changeVolume(-0.05);
        return KeyEventResult.handled;
      }
    }

    // Seek with arrow keys
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _controlsKeyFinal.currentState?.triggerSeek(true);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _controlsKeyFinal.currentState?.triggerSeek(false);
      return KeyEventResult.handled;
    }

    // Hide controls on Escape
    if (_controlsVisible && event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }

    // Pass through other keys
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        // backgroundColor: Colors.black, // Inherit from Theme (Scaffold is Black)
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Go Back"),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_controlsVisible,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_controlsVisible) {
          _controlsKeyFinal.currentState?.hideControls();
        }
      },
      child: Scaffold(
        // backgroundColor: Colors.black, // Inherit from Theme (Scaffold is Black)
        body: MouseRegion(
          cursor: _controlsVisible
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          onHover: (_) {
            if (!_controlsVisible) {
              setState(() => _controlsVisible = true);
            }
            _controlsKeyFinal.currentState?.onUserInteraction();
          },
          child: Focus(
            autofocus: false,
            onKeyEvent: _handleKey,
            child: Stack(
              children: [
                Center(
                  child: Video(
                    controller: _videoController,
                    fit: _videoFit,
                    subtitleViewConfiguration: const SubtitleViewConfiguration(
                      visible: false,
                    ),
                    controls: (state) => const SizedBox.shrink(),
                  ),
                ),

                // Custom Subtitles Position
                Positioned(
                  bottom: _controlsVisible ? 120 : 20,
                  left: 20,
                  right: 20,
                  child: SubtitleView(
                    controller: _videoController,
                    configuration: SubtitleViewConfiguration(
                      style: TextStyle(
                        fontSize: ref
                            .watch(playerSettingsProvider)
                            .subtitleSize,
                        color: Color(
                          ref.watch(playerSettingsProvider).subtitleColor,
                        ),
                        backgroundColor: Color(
                          ref
                              .watch(playerSettingsProvider)
                              .subtitleBackgroundColor,
                        ),
                        shadows: [
                          const Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Colors.black,
                          ),
                        ],
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),

                // Custom Controls Overlay
                SkyStreamPlayerControls(
                  key: _controlsKeyFinal,
                  isLoading: _isLoading,
                  forceShowControls: _forceShowControls,
                  player: _player,
                  title: _playerTitle,
                  subtitle: _streamSubtitle,
                  streams: _streams,
                  currentStream: _currentStream,
                  externalSubtitles: _externalSubtitles,
                  torrentStatus: _torrentStatus, // Added
                  onStreamSelected: _changeStream,
                  onTorrentFileSelected: _onTorrentFileSelected,
                  onResize: _updateResizeMode,
                  onVisibilityChanged: (v) {
                    if (mounted) setState(() => _controlsVisible = v);
                  },
                ),

                // Loading overlay on top for interactivity
                if (_isLoading && !_forceShowControls)
                  _buildSkipButtonOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getProviderDisplayName(String providerName) {
    try {
      final manager = ref.read(extensionManagerProvider.notifier);
      final p = manager.getAllProviders().firstWhere(
        (p) => p.id == providerName || p.name == providerName,
      );

      final isDebug = p.isDebug;
      if (isDebug) return "${p.name} [DEBUG]";
      return p.name;
    } catch (_) {}
    return providerName;
  }

  Widget _buildSkipButtonOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: () {
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
            _controlsKeyFinal.currentState?.toggleFullscreen();
          }
        },
        child: Stack(
          children: [
            Positioned(
              bottom: 160,
              left: 0,
              right: 0,
              child: Center(
                child: _isManualSwitch
                    ? const SizedBox.shrink()
                    : TvButton(
                        isPrimary: false,
                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                        focusNode: _skipFocusNode,
                        autofocus: true,
                        onPressed: () =>
                            setState(() => _forceShowControls = true),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.skip_next),
                            const SizedBox(width: 8),
                            Text(
                              "Skip Loading (${_currentStreamIndex + 1}/${_streams.length})",
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

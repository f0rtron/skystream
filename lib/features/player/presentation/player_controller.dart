import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/extensions/providers.dart';
import '../../../../core/models/torrent_status.dart';
import '../../library/presentation/history_provider.dart';

class PlayerState {
  final bool isLoading;
  final String? errorMessage;
  final String playerTitle;
  final String? streamSubtitle;
  final List<StreamResult> streams;
  final int currentStreamIndex;
  final StreamResult? currentStream;
  final StreamResult? previousStream;
  final TorrentStatus? torrentStatus;
  final List<SubtitleFile> externalSubtitles;
  final bool isManualSwitch;
  final bool isOpeningStream;
  final bool isReverting;

  const PlayerState({
    this.isLoading = true,
    this.errorMessage,
    this.playerTitle = '',
    this.streamSubtitle,
    this.streams = const [],
    this.currentStreamIndex = 0,
    this.currentStream,
    this.previousStream,
    this.torrentStatus,
    this.externalSubtitles = const [],
    this.isManualSwitch = false,
    this.isOpeningStream = false,
    this.isReverting = false,
  });

  PlayerState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? playerTitle,
    String? streamSubtitle,
    List<StreamResult>? streams,
    int? currentStreamIndex,
    StreamResult? currentStream,
    StreamResult? previousStream,
    TorrentStatus? torrentStatus,
    List<SubtitleFile>? externalSubtitles,
    bool? isManualSwitch,
    bool? isOpeningStream,
    bool? isReverting,
  }) {
    return PlayerState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage, // nullable
      playerTitle: playerTitle ?? this.playerTitle,
      streamSubtitle: streamSubtitle, // nullable
      streams: streams ?? this.streams,
      currentStreamIndex: currentStreamIndex ?? this.currentStreamIndex,
      currentStream: currentStream ?? this.currentStream,
      previousStream: previousStream ?? this.previousStream,
      torrentStatus: torrentStatus ?? this.torrentStatus,
      externalSubtitles: externalSubtitles ?? this.externalSubtitles,
      isManualSwitch: isManualSwitch ?? this.isManualSwitch,
      isOpeningStream: isOpeningStream ?? this.isOpeningStream,
      isReverting: isReverting ?? this.isReverting,
    );
  }
}

class PlayerController extends Notifier<PlayerState> {
  late Player _player;
  late MultimediaItem _item;
  late String _videoUrl;
  Timer? _torrentPollTimer;
  bool _isPolling = false;

  // Track last saved position for threshold-based saving
  Duration _lastSavedPosition = Duration.zero;
  static const double _saveThresholdPercent = 0.05; // 5% of video

  // Subscriptions to prevent leaks
  StreamSubscription? _videoParamsSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _positionSub;

  @override
  PlayerState build() {
    ref.keepAlive();
    return const PlayerState();
  }

  Future<void> init({
    required Player player,
    required MultimediaItem item,
    required String videoUrl,
  }) async {
    state = const PlayerState(); // Reset stale state
    _player = player;
    _item = item;
    _videoUrl = videoUrl;

    String initialTitle = item.title;
    // Resolve Episode Title if Series
    if (item.episodes != null && item.episodes!.isNotEmpty) {
      if (item.episodes!.length > 1) {
        try {
          final ep = item.episodes!.firstWhere(
            (e) => e.url == videoUrl,
            orElse: () => item.episodes!.first,
          );

          if (ep.url == videoUrl) {
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
              initialTitle = "${item.title} $epTitle";
            }
          }
        } catch (e) {
          debugPrint('PlayerController.init: $e');
        }
      }
    }

    state = state.copyWith(playerTitle: initialTitle);

    _setupEventDrivenProgressSaving();
    _setupErrorListener();
    _setupVideoParamsListener();

    await _initStream();
  }

  void _setupVideoParamsListener() {
    _videoParamsSub = _player.stream.videoParams.listen((args) {
      if (args.w != null && args.w! > 0) {
        if (state.isLoading) {
          state = state.copyWith(isLoading: false);
        }
      }
    });
  }

  void _setupErrorListener() {
    _errorSub = _player.stream.error.listen((error) {
      debugPrint("Player Error: $error");
      if (state.isOpeningStream) return;
      if (error.toString().toLowerCase().contains("abort")) return;

      if (state.isLoading) {
        if (state.isManualSwitch) {
          revertToPreviousStream("Stream failed. Reverting...");
        } else {
          retryNextStream();
        }
      }
    });
  }

  void _setupEventDrivenProgressSaving() {
    _playingSub = _player.stream.playing.listen((isPlaying) {
      if (!isPlaying) {
        saveProgress();
        _torrentPollTimer?.cancel();
        _torrentPollTimer = null;
      } else if (isPlaying &&
          state.torrentStatus != null &&
          _torrentPollTimer == null) {
        startTorrentPolling();
      }
    });

    _positionSub = _player.stream.position.listen((pos) {
      final duration = _player.state.duration;
      if (duration == Duration.zero) return;

      final currentPct = pos.inMilliseconds / duration.inMilliseconds;
      final lastPct =
          _lastSavedPosition.inMilliseconds / duration.inMilliseconds;

      if ((currentPct - lastPct).abs() >= _saveThresholdPercent) {
        saveProgress();
        _lastSavedPosition = pos;
      }
    });
  }

  Future<void> _initStream() async {
    if (await _handleSpecialProviders()) return;

    final activeProvider = _resolveProvider();
    if (activeProvider == null) {
      state = state.copyWith(
        errorMessage: "No provider selected.",
        isLoading: false,
      );
      return;
    }

    try {
      if (_videoUrl.isNotEmpty) {
        if (await _handleFallbackTorrent()) return;

        final streams = await activeProvider.loadStreams(_videoUrl);
        if (streams.isNotEmpty) {
          final initialIndex = _findSavedStreamIndex(streams);
          state = state.copyWith(
            streams: streams,
            currentStreamIndex: initialIndex,
          );
          await loadStreamAtIndex(initialIndex);
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading streams: $e");
    }

    state = state.copyWith(errorMessage: "No streams found.", isLoading: false);
  }

  Future<bool> _handleSpecialProviders() async {
    if (_item.provider == 'Remote' ||
        _item.provider == 'Local' ||
        _item.provider == 'Torrent') {
      final isTorrent =
          _item.provider == 'Torrent' ||
          _videoUrl.startsWith("magnet:") ||
          _videoUrl.endsWith(".torrent");

      final stream = StreamResult(
        url: _videoUrl,
        quality: isTorrent ? "Torrent" : "Video",
        headers: {},
      );

      state = state.copyWith(streams: [stream], currentStreamIndex: 0);
      await loadStreamAtIndex(0);
      return true;
    }
    return false;
  }

  Future<bool> _handleFallbackTorrent() async {
    if (_videoUrl.startsWith("magnet:") || _videoUrl.endsWith(".torrent")) {
      final stream = StreamResult(
        url: _videoUrl,
        quality: "Torrent",
        headers: {},
      );
      state = state.copyWith(streams: [stream], currentStreamIndex: 0);
      await loadStreamAtIndex(0);
      return true;
    }
    return false;
  }

  SkyStreamProvider? _resolveProvider() {
    final activeState = ref.read(activeProviderStateProvider);
    final manager = ref.read(extensionManagerProvider.notifier);

    if (_item.provider != null) {
      try {
        final val = _item.provider!;
        return manager.getAllProviders().firstWhere(
          (p) => p.id == val || p.name == val,
        );
      } catch (e) {
        debugPrint('PlayerController._resolveProvider: $e');
      }
    }
    return activeState;
  }

  int _findSavedStreamIndex(List<StreamResult> streams) {
    try {
      final historyList = ref.read(watchHistoryProvider);
      final previousState = historyList.firstWhere(
        (h) => h.item.url == _item.url,
        orElse: () => HistoryItem(
          item: _item,
          position: 0,
          duration: 0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final lastUrl = previousState.lastStreamUrl;
      if (lastUrl != null) {
        final foundIndex = streams.indexWhere((s) => s.url == lastUrl);
        if (foundIndex != -1) return foundIndex;
      }
    } catch (e) {
      debugPrint("Error checking saved stream quality: $e");
    }
    return 0;
  }

  Future<void> loadStreamAtIndex(int index) async {
    if (index < 0 || index >= state.streams.length) return;

    final stream = state.streams[index];
    final rawProviderName =
        _item.provider ??
        ref.read(activeProviderStateProvider)?.name ??
        "Unknown";
    final providerName = _getProviderDisplayName(rawProviderName);

    state = state.copyWith(
      currentStreamIndex: index,
      currentStream: stream,
      isLoading: true,
      streamSubtitle: "$providerName - ${stream.quality}",
      externalSubtitles: stream.subtitles ?? [],
    );

    try {
      final playUrl = await _resolveStreamUrl(stream);
      if (playUrl == null) throw Exception("Failed to resolve stream URL");

      if (playUrl.contains("index=")) {
        startTorrentPolling(playUrl);
      } else {
        stopTorrentPolling();
      }

      state = state.copyWith(
        streamSubtitle: "$providerName - ${stream.quality}",
      );

      final headers = stream.headers ?? {};
      await _applyPlaybackProperties(headers);

      final extras = <String, String>{};
      if (stream.drmKid != null && stream.drmKey != null) {
        extras['demuxer-lavf-o'] =
            'decryption_key=${stream.drmKid}:${stream.drmKey}';
      }

      await _player.open(Media(playUrl, httpHeaders: headers, extras: extras));

      final historyList = ref.read(watchHistoryProvider);
      final savedPos = historyList
          .firstWhere(
            (h) => h.item.url == _item.url,
            orElse: () => HistoryItem(
              item: _item,
              position: 0,
              duration: 0,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          )
          .position;

      if (savedPos > 0) {
        await _safeSeekTo(savedPos);
      }
    } catch (e) {
      debugPrint("Stream $index failed: $e");
      retryNextStream();
    }
  }

  Future<void> changeStream(
    StreamResult stream, {
    bool isRevert = false,
    bool resetPosition = false,
  }) async {
    if (!isRevert) {
      state = state.copyWith(
        previousStream: state.currentStream,
        isManualSwitch: true,
      );
    }

    state = state.copyWith(
      isLoading: true,
      currentStream: stream,
      externalSubtitles: stream.subtitles ?? [],
    );

    final rawPName =
        _item.provider ??
        ref.read(activeProviderStateProvider)?.name ??
        'Unknown';
    final pName = _getProviderDisplayName(rawPName);
    state = state.copyWith(streamSubtitle: "$pName - ${stream.quality}");

    final oldPos = _player.state.position;
    state = state.copyWith(isOpeningStream: true);

    try {
      final playUrl = await _resolveStreamUrl(stream);
      if (playUrl == null) throw Exception("Failed to resolve stream URL");

      if (playUrl.contains("index=")) {
        startTorrentPolling(playUrl);
      } else {
        stopTorrentPolling();
      }

      state = state.copyWith(streamSubtitle: "$pName - ${stream.quality}");

      final headers = stream.headers ?? {};
      await _applyPlaybackProperties(headers);

      final extras = <String, String>{};
      if (stream.drmKid != null && stream.drmKey != null) {
        extras['demuxer-lavf-o'] =
            'decryption_key=${stream.drmKid}:${stream.drmKey}';
      }

      await _player.open(Media(playUrl, httpHeaders: headers, extras: extras));

      if (oldPos > Duration.zero && !resetPosition) {
        await _safeSeekTo(oldPos.inMilliseconds);
      } else if (resetPosition) {
        await _player.seek(Duration.zero);
      }

      state = state.copyWith(
        isLoading: false,
        isReverting: isRevert ? false : state.isReverting,
        isManualSwitch: isRevert ? false : false,
      );
    } catch (e) {
      debugPrint("Change stream failed: $e");
      if (isRevert) {
        state = state.copyWith(
          errorMessage: "Revert failed: $e",
          isReverting: false,
        );
      } else {
        revertToPreviousStream("Switch failed. Reverting...");
      }
    } finally {
      state = state.copyWith(isOpeningStream: false);
    }
  }

  void retryNextStream() {
    if (state.currentStreamIndex < state.streams.length - 1) {
      loadStreamAtIndex(state.currentStreamIndex + 1);
    } else {
      state = state.copyWith(
        errorMessage: "All streams failed.",
        isLoading: false,
      );
    }
  }

  void revertToPreviousStream(String reason) {
    if (state.previousStream == null || state.isReverting) {
      if (state.previousStream == null) {
        state = state.copyWith(
          errorMessage: "Stream failed. No fallback available.",
          isLoading: false,
          isManualSwitch: false,
        );
      }
      return;
    }

    state = state.copyWith(isReverting: true);
    // Note: Revert toast / SnackBar will need to be handled by the UI
    // The UI can listen to state changes or errors, but for now we just change the stream
    changeStream(state.previousStream!, isRevert: true);
  }

  Future<void> onTorrentFileSelected(int index) async {
    state = state.copyWith(isLoading: true);
    try {
      final url = await ref.read(torrentServiceProvider).getStreamUrlForFileIndex(index);
      if (url != null && state.currentStream != null) {
        String fileLabel = "Torrent File $index";
        try {
          final files =
              state.torrentStatus?.data['file_stats'] as List<dynamic>?;
          final file = files?.firstWhere(
            (f) => f['id'] == index,
            orElse: () => null,
          );
          if (file != null) {
            fileLabel = (file['path'] as String).split('/').last;
            state = state.copyWith(playerTitle: fileLabel);
          }
        } catch (e) {
          debugPrint('PlayerController.onTorrentFileSelected: $e');
        }

        final newStream = StreamResult(
          url: url,
          quality: "Torrent ($fileLabel)",
          headers: {},
        );
        changeStream(newStream, resetPosition: true);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint("Failed to switch file: $e");
      state = state.copyWith(isLoading: false);
    }
  }

  void saveProgress() {
    try {
      final pos = _player.state.position.inMilliseconds;
      final dur = _player.state.duration.inMilliseconds;

      if (dur < 30000) return;

      final double progress = (pos / dur) * 100;
      final bool isSeries =
          _item.episodes != null && _item.episodes!.length > 1;
      final historyNotifier = ref.read(watchHistoryProvider.notifier);

      if (progress >= 95 && !isSeries) {
        historyNotifier.removeFromHistory(_item.url);
        return;
      }

      if (progress > 1 || isSeries) {
        final pId =
            _item.provider ??
            ref.read(activeProviderStateProvider)?.id ??
            'Unknown';
        final itemToSave = _item.copyWith(provider: pId);
        historyNotifier.saveProgress(
          itemToSave,
          pos,
          dur,
          lastStreamUrl: state.currentStream?.url,
          lastEpisodeUrl: _videoUrl,
        );
      }
    } catch (e) {
      debugPrint("History save failed: $e");
    }
  }

  void startTorrentPolling([String? activeStreamUrl]) {
    _torrentPollTimer?.cancel();

    Future<void> poll() async {
      if (_isPolling) return;
      _isPolling = true;
      try {
        final status = await ref.read(torrentServiceProvider).getCurrentStatus();
        if (status != null) {
          final urlToCheck = activeStreamUrl ?? state.currentStream?.url;
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
                  if (state.playerTitle != name) {
                    state = state.copyWith(playerTitle: name);
                  }
                }
              }
            } catch (e) {
              debugPrint('PlayerController.startTorrentPolling: $e');
            }
          }
          state = state.copyWith(torrentStatus: status);
        }
      } finally {
        _isPolling = false;
      }
    }

    poll();
    _torrentPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => poll(),
    );
  }

  void stopTorrentPolling() {
    _torrentPollTimer?.cancel();
    _torrentPollTimer = null;
    if (state.torrentStatus != null) {
      state = PlayerState(
        isLoading: state.isLoading,
        errorMessage: state.errorMessage,
        playerTitle: state.playerTitle,
        streamSubtitle: state.streamSubtitle,
        streams: state.streams,
        currentStreamIndex: state.currentStreamIndex,
        currentStream: state.currentStream,
        previousStream: state.previousStream,
        torrentStatus: null,
        externalSubtitles: state.externalSubtitles,
        isManualSwitch: state.isManualSwitch,
        isOpeningStream: state.isOpeningStream,
        isReverting: state.isReverting,
      );
    }
  }

  Future<void> disposeController() async {
    _torrentPollTimer?.cancel();
    _torrentPollTimer = null;

    _videoParamsSub?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();

    saveProgress();
    ref.read(torrentServiceProvider).stop();
    Future.microtask(() {
      state = const PlayerState();
    });
  }

  String _getProviderDisplayName(String providerName) {
    try {
      final manager = ref.read(extensionManagerProvider.notifier);
      final p = manager.getAllProviders().firstWhere(
        (p) => p.id == providerName || p.name == providerName,
      );
      if (p.isDebug) return "${p.name} [DEBUG]";
      return p.name;
    } catch (e) {
      debugPrint('PlayerController._getProviderDisplayName: $e');
    }
    return providerName;
  }

  Future<String?> _resolveStreamUrl(StreamResult stream) async {
    if (stream.url.startsWith("magnet:") ||
        stream.url.endsWith(".torrent") ||
        (stream.url.startsWith("/") && stream.quality.contains("Torrent"))) {
      state = state.copyWith(streamSubtitle: "Initializing Torrent Engine...");
      final torrentUrl = await ref.read(torrentServiceProvider).getStreamUrl(stream.url);
      if (torrentUrl != null) return torrentUrl;
      return null;
    }
    return stream.url;
  }

  Future<void> _applyPlaybackProperties(Map<String, String> headers) async {
    if (_player.platform is! NativePlayer) return;
    final native = _player.platform as NativePlayer;

    final lowerHeaders = headers.map((k, v) => MapEntry(k.toLowerCase(), v));

    if (lowerHeaders.containsKey('user-agent')) {
      await native.setProperty('user-agent', lowerHeaders['user-agent']!);
    }
    if (lowerHeaders.containsKey('referer')) {
      await native.setProperty('referrer', lowerHeaders['referer']!);
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final cookieFile = File('${tempDir.path}/mpv_cookies.txt');
      if (!await cookieFile.exists()) {
        await cookieFile.create();
      }
      await native.setProperty('cookies-file', cookieFile.path);
      await native.setProperty('cookies-file-access', 'read+write');
    } catch (e) {
      debugPrint("Failed to set cookies-file: $e");
    }
  }

  Future<void> _safeSeekTo(int position) async {
    if (position <= 0) return;
    try {
      await _player.stream.duration
          .firstWhere((d) => d != Duration.zero)
          .timeout(const Duration(seconds: 10));

      if (_player.state.duration.inMilliseconds > position) {
        await _player.seek(Duration(milliseconds: position));
      }
    } catch (e) {
      debugPrint("Timeout waiting for duration or seek failed: $e");
    }
  }
}

final playerControllerProvider =
    NotifierProvider.autoDispose<PlayerController, PlayerState>(
      PlayerController.new,
    );

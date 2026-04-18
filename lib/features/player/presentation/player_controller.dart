import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:video_view/video_view.dart'
    show VideoController, SubtitleTrackConfig, VideoControllerPlaybackState;

import '../../../../core/services/download_service.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/extensions/providers.dart';
import '../../../../core/models/torrent_status.dart';
import '../../../../core/storage/history_repository.dart';
import '../../library/presentation/history_provider.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../core/utils/app_utils.dart';
import '../../settings/presentation/player_settings_provider.dart';
import '../../../../core/services/local_proxy_service.dart';
import '../../../../core/utils/stream_quality_sorter.dart';

// Sentinel so copyWith can distinguish "not passed" from "explicitly null".
const Object _keep = Object();

enum PlaybackUiPhaseKind {
  idle,
  bootstrapping,
  fetchingSources,
  checkingSources,
  openingSource,
  switchingEngine,
  bufferingInitial,
  bufferingRuntime,
  switchingSource,
  reconnectingLive,
  loadingNextEpisode,
  manualSourcePick,
  error,
}

enum SourceAttemptStatus { pending, trying, failed, selected, playing }

class SourceAttemptEntry {
  final int index;
  final String label;
  final SourceAttemptStatus status;
  final bool isCurrent;

  const SourceAttemptEntry({
    required this.index,
    required this.label,
    this.status = SourceAttemptStatus.pending,
    this.isCurrent = false,
  });

  SourceAttemptEntry copyWith({
    int? index,
    String? label,
    SourceAttemptStatus? status,
    bool? isCurrent,
  }) {
    return SourceAttemptEntry(
      index: index ?? this.index,
      label: label ?? this.label,
      status: status ?? this.status,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }
}

class PlaybackUiPhase {
  final PlaybackUiPhaseKind kind;
  final String title;
  final String? subtitle;
  final String? detail;
  final bool fullscreenBlocking;
  final bool preserveCurrentFrame;
  final bool showGoLive;
  final int? attemptIndex;
  final int? attemptTotal;

  const PlaybackUiPhase({
    required this.kind,
    this.title = '',
    this.subtitle,
    this.detail,
    this.fullscreenBlocking = false,
    this.preserveCurrentFrame = false,
    this.showGoLive = false,
    this.attemptIndex,
    this.attemptTotal,
  });

  const PlaybackUiPhase.idle() : this(kind: PlaybackUiPhaseKind.idle);

  bool get showsInlineSourcePanel =>
      fullscreenBlocking &&
      const {
        PlaybackUiPhaseKind.checkingSources,
        PlaybackUiPhaseKind.openingSource,
        PlaybackUiPhaseKind.bufferingInitial,
        PlaybackUiPhaseKind.error,
      }.contains(kind);

  bool get allowsInlineSourceSelection => const {
    PlaybackUiPhaseKind.checkingSources,
    PlaybackUiPhaseKind.openingSource,
    PlaybackUiPhaseKind.bufferingInitial,
    PlaybackUiPhaseKind.manualSourcePick,
    PlaybackUiPhaseKind.error,
  }.contains(kind);

  bool get isIdle => kind == PlaybackUiPhaseKind.idle;

  PlaybackUiPhase copyWith({
    PlaybackUiPhaseKind? kind,
    Object? title = _keep,
    Object? subtitle = _keep,
    Object? detail = _keep,
    bool? fullscreenBlocking,
    bool? preserveCurrentFrame,
    bool? showGoLive,
    Object? attemptIndex = _keep,
    Object? attemptTotal = _keep,
  }) {
    return PlaybackUiPhase(
      kind: kind ?? this.kind,
      title: title == _keep ? this.title : title as String,
      subtitle: subtitle == _keep ? this.subtitle : subtitle as String?,
      detail: detail == _keep ? this.detail : detail as String?,
      fullscreenBlocking: fullscreenBlocking ?? this.fullscreenBlocking,
      preserveCurrentFrame: preserveCurrentFrame ?? this.preserveCurrentFrame,
      showGoLive: showGoLive ?? this.showGoLive,
      attemptIndex: attemptIndex == _keep
          ? this.attemptIndex
          : attemptIndex as int?,
      attemptTotal: attemptTotal == _keep
          ? this.attemptTotal
          : attemptTotal as int?,
    );
  }
}

class PlayerState {
  final String? errorMessage;
  final String playerTitle;
  final String? streamSubtitle;
  final List<StreamResult> streams;
  final int currentStreamIndex;
  final StreamResult? currentStream;
  final StreamResult? previousStream;
  final TorrentStatus? torrentStatus;
  final List<SubtitleFile> externalSubtitles;
  final bool showNextEpisodeOverlay;
  final String? nextEpisodeTitle;
  final bool isAdaptiveBufferingActive;
  final bool showEpisodeList;
  final double playbackSpeed;
  final bool isLive;
  final double subtitleDelay;
  final String? imdbId;
  final int? tmdbId;

  /// Whether the active engine is video_view (ExoPlayer/AVPlayer) instead of media_kit.
  final bool useExoPlayer;
  final bool isSeekable;
  final PlaybackUiPhase uiPhase;
  final List<SourceAttemptEntry> sourceAttempts;
  final int? currentAttemptIndex;
  final int sourceSessionId;

  /// Non-null when a saved position was found; shows resume prompt instead of seeking silently.
  final int? resumePromptPosition;
  final bool userSkippedOverlay;

  const PlayerState({
    this.errorMessage,
    this.playerTitle = '',
    this.streamSubtitle,
    this.streams = const [],
    this.currentStreamIndex = 0,
    this.currentStream,
    this.previousStream,
    this.torrentStatus,
    this.externalSubtitles = const [],
    this.showNextEpisodeOverlay = false,
    this.nextEpisodeTitle,
    this.isAdaptiveBufferingActive = false,
    this.showEpisodeList = false,
    this.playbackSpeed = 1.0,
    this.isLive = false,
    this.isSeekable = false,
    this.subtitleDelay = 0.0,
    this.imdbId,
    this.tmdbId,
    this.useExoPlayer = false,
    this.uiPhase = const PlaybackUiPhase(
      kind: PlaybackUiPhaseKind.bootstrapping,
      fullscreenBlocking: true,
    ),
    this.sourceAttempts = const [],
    this.currentAttemptIndex,
    this.sourceSessionId = 0,
    this.resumePromptPosition,
    this.userSkippedOverlay = false,
  });

  // Derived from uiPhase — no separate field needed.
  bool get isLoading => const {
    PlaybackUiPhaseKind.bootstrapping,
    PlaybackUiPhaseKind.fetchingSources,
    PlaybackUiPhaseKind.checkingSources,
    PlaybackUiPhaseKind.openingSource,
    PlaybackUiPhaseKind.bufferingInitial,
  }.contains(uiPhase.kind);

  bool get isBuffering => uiPhase.kind == PlaybackUiPhaseKind.bufferingRuntime;

  bool get canSeek => !useExoPlayer || isSeekable;
  bool get supportsPlaybackSpeed => !isLive;
  double get maxPlaybackSpeed => useExoPlayer ? 2.0 : 3.0;
  bool get supportsVolumeBoost => !useExoPlayer;
  bool get supportsSubtitleDelay => !useExoPlayer;
  bool get supportsSubtitleStyling => !useExoPlayer;
  bool get supportsExternalSubtitleLoading =>
      !useExoPlayer || Platform.isAndroid;

  PlayerState copyWith({
    String? errorMessage,
    String? playerTitle,
    String? streamSubtitle,
    List<StreamResult>? streams,
    int? currentStreamIndex,
    StreamResult? currentStream,
    StreamResult? previousStream,
    Object? torrentStatus = _keep,
    List<SubtitleFile>? externalSubtitles,
    bool? showNextEpisodeOverlay,
    String? nextEpisodeTitle,
    bool? isAdaptiveBufferingActive,
    bool? showEpisodeList,
    double? playbackSpeed,
    bool? isLive,
    bool? isSeekable,
    double? subtitleDelay,
    String? imdbId,
    int? tmdbId,
    bool? useExoPlayer,
    PlaybackUiPhase? uiPhase,
    List<SourceAttemptEntry>? sourceAttempts,
    Object? currentAttemptIndex = _keep,
    int? sourceSessionId,
    Object? resumePromptPosition = _keep,
    bool? userSkippedOverlay,
  }) {
    return PlayerState(
      errorMessage: errorMessage ?? this.errorMessage,
      playerTitle: playerTitle ?? this.playerTitle,
      streamSubtitle: streamSubtitle ?? this.streamSubtitle,
      streams: streams ?? this.streams,
      currentStreamIndex: currentStreamIndex ?? this.currentStreamIndex,
      currentStream: currentStream ?? this.currentStream,
      previousStream: previousStream ?? this.previousStream,
      torrentStatus: torrentStatus == _keep
          ? this.torrentStatus
          : torrentStatus as TorrentStatus?,
      externalSubtitles: externalSubtitles ?? this.externalSubtitles,
      showNextEpisodeOverlay:
          showNextEpisodeOverlay ?? this.showNextEpisodeOverlay,
      nextEpisodeTitle: nextEpisodeTitle ?? this.nextEpisodeTitle,
      isAdaptiveBufferingActive:
          isAdaptiveBufferingActive ?? this.isAdaptiveBufferingActive,
      showEpisodeList: showEpisodeList ?? this.showEpisodeList,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      isLive: isLive ?? this.isLive,
      isSeekable: isSeekable ?? this.isSeekable,
      subtitleDelay: subtitleDelay ?? this.subtitleDelay,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      useExoPlayer: useExoPlayer ?? this.useExoPlayer,
      uiPhase: uiPhase ?? this.uiPhase,
      sourceAttempts: sourceAttempts ?? this.sourceAttempts,
      currentAttemptIndex: currentAttemptIndex == _keep
          ? this.currentAttemptIndex
          : currentAttemptIndex as int?,
      sourceSessionId: sourceSessionId ?? this.sourceSessionId,
      resumePromptPosition: resumePromptPosition == _keep
          ? this.resumePromptPosition
          : resumePromptPosition as int?,
      userSkippedOverlay: userSkippedOverlay ?? this.userSkippedOverlay,
    );
  }
}

class PlayerTrackOption {
  final String id;
  final String label;
  final String? subtitle;
  final bool selected;

  const PlayerTrackOption({
    required this.id,
    required this.label,
    this.subtitle,
    this.selected = false,
  });
}

class PlayerTrackSelectionSnapshot {
  final List<PlayerTrackOption> audioTracks;
  final List<PlayerTrackOption> subtitleTracks;
  final bool subtitlesOffSelected;

  const PlayerTrackSelectionSnapshot({
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.subtitlesOffSelected = true,
  });
}

class PlayerController extends Notifier<PlayerState> {
  late Player _player;
  VideoController? _videoViewController;
  late MultimediaItem _item;
  late String _videoUrl;
  Episode? _episode;
  Timer? _torrentPollTimer;
  bool _isPolling = false;
  bool _isInitialized = false;
  bool _isDisposed = false;

  Player get player => _player;
  VideoController? get videoViewController => _videoViewController;
  bool get isDisposed => _isDisposed;
  PlayerState get currentState => state;
  List<SubtitleFile> get userAddedExternalSubtitles => _userAddedExternalSubtitles;

  Set<String>? get pendingVideoViewSubtitleIdsBeforeReload => _pendingVideoViewSubtitleIdsBeforeReload;
  set pendingVideoViewSubtitleIdsBeforeReload(Set<String>? values) => _pendingVideoViewSubtitleIdsBeforeReload = values;

  bool get selectNewestVideoViewSubtitleAfterReload => _selectNewestVideoViewSubtitleAfterReload;
  set selectNewestVideoViewSubtitleAfterReload(bool value) => _selectNewestVideoViewSubtitleAfterReload = value;

  void updateState(PlayerState Function(PlayerState s) update) {
    state = update(state);
  }

  bool _isDashStreamUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mpd') ||
        lower.contains('manifest.mpd') ||
        lower.contains('/dash/') ||
        lower.contains('format=mpd') ||
        lower.contains('type=mpd');
  }

  bool _streamRequiresNativeDrm(StreamResult stream) {
    return stream.drmKey != null ||
        stream.drmKid != null ||
        stream.licenseUrl != null;
  }

  bool _detectResolvedLiveState(String url) {
    return _item.contentType == MultimediaContentType.livestream ||
        _isLiveStream(url);
  }

  bool _canUseVideoViewForStream(
    String playUrl,
    StreamResult stream, {
    required bool isLive,
  }) {
    // Preserve the current product behavior: video_view is the native live path.
    if (_videoViewController == null || Platform.isLinux || !isLive) {
      return false;
    }

    // AVPlayer/Windows native backends do not handle DASH playback reliably here.
    // Check both the resolved URL and the original stream URL to catch proxied
    // or query-param-based MPD streams that lack a .mpd extension in the resolved URL.
    if ((Platform.isMacOS || Platform.isIOS || Platform.isWindows) &&
        (_isDashStreamUrl(playUrl) || _isDashStreamUrl(stream.url))) {
      return false;
    }

    // Only Android currently implements the video_view DRM path end-to-end.
    if (!Platform.isAndroid && _streamRequiresNativeDrm(stream)) {
      return false;
    }

    return true;
  }

  bool get _videoViewSupportsMergedExternalSubtitles => Platform.isAndroid;

  // Track last saved position for threshold-based saving
  Duration _lastSavedPosition = Duration.zero;
  static const double _saveThresholdPercent = 0.05; // 5% of video

  // Subscriptions to prevent leaks
  StreamSubscription<dynamic>? _videoParamsSub;
  StreamSubscription<dynamic>? _errorSub;
  StreamSubscription<dynamic>? _playingSub;
  StreamSubscription<dynamic>? _positionSub;
  StreamSubscription<dynamic>? _durationSub;
  StreamSubscription<dynamic>? _bufferingSub;
  StreamSubscription<dynamic>? _completedSub;
  StreamSubscription<dynamic>? _rateSub;
  StreamSubscription<dynamic>? _logSub;

  // Stall Watchdog state
  Duration? _lastPosition;
  DateTime? _lastPositionUpdateTime;
  bool _isRecoveringFromStall = false;

  final List<DateTime> _bufferDepletionTimes = [];
  Timer? _stallTimer;
  int? _pendingResumeSeekPosition;
  bool _isApplyingPendingResumeSeek = false;
  double _lastNonZeroVolumeLevel = 1.0;
  final List<SubtitleFile> _userAddedExternalSubtitles = [];
  Set<String>? _pendingVideoViewSubtitleIdsBeforeReload;
  bool _selectNewestVideoViewSubtitleAfterReload = false;
  bool _hasConfirmedPlaybackFrame = false;
  bool _suppressNextEpisodeDetection = false;
  bool _manualSelectionPending = false;

  String _phaseTitle([String? fallback]) {
    if (state.playerTitle.isNotEmpty) return state.playerTitle;
    if (_isInitialized) return _item.title;
    return fallback ?? '';
  }

  String? _phaseSubtitle([String? fallback]) {
    return fallback ?? state.streamSubtitle;
  }

  PlaybackUiPhase _composeUiPhase({
    required PlaybackUiPhaseKind kind,
    String? title,
    String? subtitle,
    String? detail,
    bool? fullscreenBlocking,
    bool? preserveCurrentFrame,
    bool? showGoLive,
    int? attemptIndex,
    int? attemptTotal,
  }) {
    // Error phase always blocks — even after a frame was confirmed — so the
    // user sees a clear "all sources failed" screen and can navigate back.
    // All other phases never block once a frame has been confirmed.
    final bool effectiveFullscreenBlocking;
    if (kind == PlaybackUiPhaseKind.error) {
      effectiveFullscreenBlocking = fullscreenBlocking ?? true;
    } else if (_hasConfirmedPlaybackFrame) {
      effectiveFullscreenBlocking = false;
    } else if (state.userSkippedOverlay && kind != PlaybackUiPhaseKind.idle) {
      effectiveFullscreenBlocking = false;
    } else {
      effectiveFullscreenBlocking = fullscreenBlocking ?? true;
    }

    return PlaybackUiPhase(
      kind: kind,
      title: title ?? _phaseTitle(),
      subtitle: subtitle ?? _phaseSubtitle(),
      detail: detail,
      fullscreenBlocking: effectiveFullscreenBlocking,
      preserveCurrentFrame: preserveCurrentFrame ?? _hasConfirmedPlaybackFrame,
      showGoLive: showGoLive ?? false,
      attemptIndex: attemptIndex,
      attemptTotal: attemptTotal,
    );
  }

  void _setUiPhase(PlaybackUiPhase phase) {
    state = state.copyWith(uiPhase: phase);
  }

  void _setIdlePhase() {
    if (!state.uiPhase.isIdle) {
      state = state.copyWith(uiPhase: const PlaybackUiPhase.idle());
    }
  }

  void _enterStartupPhase({
    required PlaybackUiPhaseKind kind,
    String? title,
    String? subtitle,
    String? detail,
    int? attemptIndex,
    int? attemptTotal,
  }) {
    _setUiPhase(
      _composeUiPhase(
        kind: kind,
        title: title,
        subtitle: subtitle,
        detail: detail,
        fullscreenBlocking: true,
        preserveCurrentFrame: false,
        attemptIndex: attemptIndex,
        attemptTotal: attemptTotal,
      ),
    );
  }

  void _enterRuntimePhase({
    required PlaybackUiPhaseKind kind,
    String? title,
    String? subtitle,
    String? detail,
  }) {
    _setUiPhase(
      _composeUiPhase(
        kind: kind,
        title: title,
        subtitle: subtitle,
        detail: detail,
        fullscreenBlocking: false,
        preserveCurrentFrame: true,
      ),
    );
  }

  void _enterAllSourcesFailedPhase({String? detail}) {
    _setUiPhase(
      _composeUiPhase(
        kind: PlaybackUiPhaseKind.error,
        title: "Playback Error",
        subtitle: detail ?? "All sources failed.",
        detail:
            "None of the available sources could be played. "
            "Try again later",
        fullscreenBlocking: true,
        preserveCurrentFrame: true,
        attemptIndex: null,
        attemptTotal: null,
      ),
    );
  }

  int _beginSourceSession({bool resetAttempts = false}) {
    final nextSessionId = state.sourceSessionId + 1;
    state = state.copyWith(
      sourceSessionId: nextSessionId,
      currentAttemptIndex: null,
      sourceAttempts: resetAttempts ? const [] : state.sourceAttempts,
      userSkippedOverlay: false,
    );
    return nextSessionId;
  }

  bool _isCurrentSourceSession(int sessionId) =>
      state.sourceSessionId == sessionId;

  void _setSourceAttemptsFromStreams(
    List<StreamResult> streams, {
    int? activeIndex,
    SourceAttemptStatus? activeStatus,
  }) {
    final attempts = <SourceAttemptEntry>[
      for (int i = 0; i < streams.length; i++)
        SourceAttemptEntry(
          index: i,
          label: streams[i].source,
          status: i == activeIndex
              ? (activeStatus ?? SourceAttemptStatus.pending)
              : SourceAttemptStatus.pending,
          isCurrent: i == activeIndex,
        ),
    ];
    state = state.copyWith(
      sourceAttempts: attempts,
      currentAttemptIndex: activeIndex,
    );
  }

  void _markSourceAttempt(
    int index,
    SourceAttemptStatus status, {
    bool isCurrent = true,
  }) {
    if (index < 0 || index >= state.sourceAttempts.length) return;

    final updated = [
      for (final entry in state.sourceAttempts)
        if (entry.index == index)
          entry.copyWith(status: status, isCurrent: isCurrent)
        else if (isCurrent)
          entry.copyWith(isCurrent: false)
        else
          entry,
    ];

    state = state.copyWith(
      sourceAttempts: updated,
      currentAttemptIndex: isCurrent
          ? index
          : (state.currentAttemptIndex == index
                ? null
                : state.currentAttemptIndex),
    );
  }

  void _confirmPlaybackStarted() {
    _hasConfirmedPlaybackFrame = true;
    _manualSelectionPending = false; // source played — no longer pending
    // Do NOT reset _suppressNextEpisodeDetection here. At the moment position
    // first exceeds zero, _player.state.duration may still hold the previous
    // episode's value (mpv resets it asynchronously). Resetting here would
    // cause the next-episode detection to see remaining ≈ 0 and show the
    // overlay for the newly loaded episode. It is reset in _setupDurationListener
    // once a valid non-zero duration for the new episode arrives.
    final currentAttemptIndex = state.currentAttemptIndex;
    if (currentAttemptIndex != null) {
      _markSourceAttempt(currentAttemptIndex, SourceAttemptStatus.playing);
    }
    state = state.copyWith(uiPhase: const PlaybackUiPhase.idle());
  }

  @override
  PlayerState build() {
    ref.keepAlive();
    // Safety net: if the provider is somehow disposed without
    // disposeController() being called, clean up subscriptions.
    ref.onDispose(() {
      _torrentPollTimer?.cancel();
      _stallTimer?.cancel();
      _videoParamsSub?.cancel();
      _errorSub?.cancel();
      _playingSub?.cancel();
      _positionSub?.cancel();
      _durationSub?.cancel();
      _bufferingSub?.cancel();
      _completedSub?.cancel();
      _rateSub?.cancel();
      _logSub?.cancel();
    });
    return const PlayerState();
  }

  bool get isSeries =>
      _isInitialized && _item.contentType == MultimediaContentType.series;
  MultimediaItem? get multimediaItem => _isInitialized ? _item : null;
  String? get currentEpisodeUrl => _episode?.url ?? _videoUrl;

  Future<void> init({
    required Player player,
    required MultimediaItem item,
    required String videoUrl,
    Episode? episode,
    VideoController? videoViewController,
  }) async {
    state = const PlayerState(); // Resets all fields including errorMessage
    _logSub?.cancel();
    _logSub = null;
    _hasConfirmedPlaybackFrame = false;
    _manualSelectionPending = false;
    _revertMessage = null;
    _player = player;
    _videoViewController = videoViewController;
    _videoUrl = videoUrl;
    _episode = episode;
    _pendingResumeSeekPosition = null;
    _isApplyingPendingResumeSeek = false;
    _userAddedExternalSubtitles.clear();
    _pendingVideoViewSubtitleIdsBeforeReload = null;
    _selectNewestVideoViewSubtitleAfterReload = false;

    _item = item;

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
          if (kDebugMode) debugPrint('PlayerController.init: $e');
        }
      }
    }

    final imdbId = item.syncData?['imdbId'] ?? item.syncData?['imdb_id'];
    final tmdbId = item.tmdbId;

    state = state.copyWith(
      playerTitle: initialTitle,
      streamSubtitle: "Searching for sources...",
      imdbId: imdbId,
      tmdbId: tmdbId,
    );
    _enterStartupPhase(
      kind: PlaybackUiPhaseKind.bootstrapping,
      detail: "Preparing playback...",
    );

    _setupEventDrivenProgressSaving();
    _setupErrorListener();
    _setupVideoParamsListener();
    _setupDurationListener();
    _setupBufferingMonitor();
    _setupRateListener();
    _setupVideoViewListeners();

    state = state.copyWith(
      isLive:
          _item.contentType == MultimediaContentType.livestream ||
          _isLiveStream(_videoUrl),
    );

    _isInitialized = true;
    await _initStream();
    if (_isDisposed) return;
    await applySubtitleSettings();
  }

  void _setupVideoViewListeners() {
    if (_videoViewController == null) return;

    _videoViewController!.mediaInfo.addListener(() {
      final info = _videoViewController!.mediaInfo.value;
      if (info != null) {
        final detectedIsLive =
            _item.contentType == MultimediaContentType.livestream
            ? true
            : info.isLive;
        if (info.isSeekable != state.isSeekable ||
            detectedIsLive != state.isLive) {
          state = state.copyWith(
            isSeekable: info.isSeekable,
            isLive: detectedIsLive,
          );
        }

        if (!_hasConfirmedPlaybackFrame &&
            (info.duration > 0 || info.isLive) &&
            state.uiPhase.kind == PlaybackUiPhaseKind.openingSource) {
          _enterStartupPhase(
            kind: PlaybackUiPhaseKind.bufferingInitial,
            detail: detectedIsLive
                ? "Connecting to live stream..."
                : "Buffering selected source...",
            attemptIndex: state.currentAttemptIndex == null
                ? null
                : state.currentAttemptIndex! + 1,
            attemptTotal: state.sourceAttempts.isEmpty
                ? null
                : state.sourceAttempts.length,
          );
        }

        // Re-enable next-episode detection once ExoPlayer reports a confirmed
        // non-zero duration (mirrors the media_kit _setupDurationListener fix).
        if ((info.duration > 0 || info.isLive) &&
            _suppressNextEpisodeDetection) {
          _suppressNextEpisodeDetection = false;
        }

        if (_selectNewestVideoViewSubtitleAfterReload &&
            info.subtitleTracks.isNotEmpty) {
          final previousIds =
              _pendingVideoViewSubtitleIdsBeforeReload ?? const <String>{};
          final newTrackId =
              info.subtitleTracks.keys.firstWhereOrNull(
                (id) => !previousIds.contains(id),
              ) ??
              info.subtitleTracks.keys.lastOrNull;
          if (newTrackId != null) {
            _videoViewController!.setShowSubtitle(true);
            _videoViewController!.setOverrideSubtitle(newTrackId);
          }
          _pendingVideoViewSubtitleIdsBeforeReload = null;
          _selectNewestVideoViewSubtitleAfterReload = false;
        }
      }
    });

    _videoViewController!.loading.addListener(() {
      final isLoading = _videoViewController!.loading.value;
      if (isLoading) {
        _handleBufferStall();
        _stallTimer?.cancel();
        _stallTimer = Timer(const Duration(milliseconds: 200), () {
          if (_hasConfirmedPlaybackFrame) {
            _enterRuntimePhase(
              kind: PlaybackUiPhaseKind.bufferingRuntime,
              detail: state.isLive
                  ? "Reconnecting to live stream..."
                  : "Buffering playback...",
            );
          } else {
            _enterStartupPhase(
              kind: PlaybackUiPhaseKind.bufferingInitial,
              detail: state.isLive
                  ? "Connecting to live stream..."
                  : "Buffering selected source...",
              attemptIndex: state.currentAttemptIndex == null
                  ? null
                  : state.currentAttemptIndex! + 1,
              attemptTotal: state.sourceAttempts.isEmpty
                  ? null
                  : state.sourceAttempts.length,
            );
          }
        });
      } else {
        _stallTimer?.cancel();
        if (_hasConfirmedPlaybackFrame &&
            state.uiPhase.kind == PlaybackUiPhaseKind.bufferingRuntime) {
          _setIdlePhase();
        }
      }
    });

    _videoViewController!.error.addListener(() {
      final error = _videoViewController!.error.value;
      if (error != null) {
        _pendingVideoViewSubtitleIdsBeforeReload = null;
        _selectNewestVideoViewSubtitleAfterReload = false;
        if (kDebugMode) debugPrint("VideoView Player Error: $error");
        if (!_hasConfirmedPlaybackFrame ||
            (_videoViewController!.position.value) == 0) {
          // Error before playback confirmed — try next source.
          _markSourceAttempt(
            state.currentStreamIndex,
            SourceAttemptStatus.failed,
            isCurrent: false,
          );
          if (_manualSelectionPending) {
            _manualSelectionPending = false;
            revertToPreviousStream(
              "Selected source is not playable. Reverting back to previous source.",
            );
          } else {
            retryNextStream(sourceSessionId: state.sourceSessionId);
          }
        } else {
          // Error during active playback.
          if (state.isLive && state.currentStream != null) {
            if (_isRecoveringFromStall) return; // already reconnecting
            if (kDebugMode) {
              debugPrint(
                "VideoView live stream error. Triggering reconnect...",
              );
            }
            _isRecoveringFromStall = true;
            _enterRuntimePhase(
              kind: PlaybackUiPhaseKind.reconnectingLive,
              detail: "Reconnecting to live stream...",
            );
            changeStream(state.currentStream!, resetPosition: true);
            Future.delayed(const Duration(seconds: 10), () {
              _isRecoveringFromStall = false;
            });
            return;
          }
          _markSourceAttempt(
            state.currentStreamIndex,
            SourceAttemptStatus.failed,
            isCurrent: false,
          );
          _revertMessage =
              "Current source stopped unexpectedly. Trying next available source...";
          retryNextStream(sourceSessionId: state.sourceSessionId);
        }
      }
    });

    _videoViewController!.playbackState.addListener(() {
      final playing =
          _videoViewController!.playbackState.value ==
          VideoControllerPlaybackState.playing;
      if (!playing) {
        saveProgress();
      } else {
        // Do NOT call _confirmPlaybackStarted() here — ExoPlayer/AVPlayer fires
        // playbackState=playing when it starts buffering, before any frames arrive.
        // Confirmation happens via position listener (position > 0).
      }
    });

    _videoViewController!.finishedTimes.addListener(() {
      final completions = _videoViewController!.finishedTimes.value;
      if (completions > 0) {
        final isLive =
            _item.contentType == MultimediaContentType.livestream ||
            _isLiveStream(_videoUrl);
        if (isLive && state.currentStream != null) {
          _enterRuntimePhase(
            kind: PlaybackUiPhaseKind.reconnectingLive,
            detail: "Reconnecting to live stream...",
          );
          changeStream(state.currentStream!, resetPosition: true);
        }
      }
    });

    _videoViewController!.position.addListener(() {
      if (!state.useExoPlayer) return;

      final posMs = _videoViewController!.position.value;
      final durationMs = _videoViewController!.mediaInfo.value?.duration ?? 0;

      if (posMs > 0 && !_hasConfirmedPlaybackFrame) {
        _confirmPlaybackStarted();
      }

      if (durationMs == 0) return;

      final currentPct = posMs / durationMs;
      final lastPct = _lastSavedPosition.inMilliseconds / durationMs;

      if ((currentPct - lastPct).abs() >= _saveThresholdPercent) {
        saveProgress();
        _lastSavedPosition = Duration(milliseconds: posMs);
      }

      if (!_suppressNextEpisodeDetection &&
          _item.contentType == MultimediaContentType.series) {
        final remainingSecs = (durationMs - posMs) / 1000;
        if (remainingSecs <= 15 &&
            remainingSecs > 0 &&
            !state.showNextEpisodeOverlay) {
          int? currentIndex;
          if (_episode != null) {
            currentIndex = _item.episodes?.indexWhere(
              (e) => e.url == _episode!.url,
            );
          } else {
            currentIndex = _item.episodes?.indexWhere(
              (e) => e.url == _videoUrl,
            );
          }

          if (currentIndex != null &&
              currentIndex != -1 &&
              currentIndex < _item.episodes!.length - 1) {
            final next = _item.episodes![currentIndex + 1];
            state = state.copyWith(
              showNextEpisodeOverlay: true,
              nextEpisodeTitle: next.name,
            );
          }
        } else if (remainingSecs > 15 && state.showNextEpisodeOverlay) {
          state = state.copyWith(showNextEpisodeOverlay: false);
        }
      }
    });
  }

  void _setupRateListener() {
    _rateSub?.cancel();
    _rateSub = _player.stream.rate.listen((rate) {
      state = state.copyWith(playbackSpeed: rate);
    });
  }

  void _setupDurationListener() {
    _durationSub?.cancel();
    _durationSub = _player.stream.duration.listen((duration) {
      if (duration > Duration.zero) {
        if (_pendingResumeSeekPosition != null) {
          unawaited(_flushPendingResumeSeek());
        }
        // Safe point to re-enable next-episode detection: the new episode's
        // duration is now confirmed, so remaining-time calculations are valid.
        if (_suppressNextEpisodeDetection) {
          _suppressNextEpisodeDetection = false;
        }
      }
    });
  }

  void _setupVideoParamsListener() {
    // Intentionally empty: videoParams fires as soon as the container is parsed,
    // before any frames are rendered or position advances. Using it as a
    // confirmation trigger caused premature overlay dismissal → flickering retries.
    // Confirmation is handled solely by position > 0 (positionSub) and the
    // video_view position listener, which are reliable indicators of real playback.
    _videoParamsSub = _player.stream.videoParams.listen((_) {});
  }

  void _setupBufferingMonitor() {
    _bufferingSub?.cancel();
    _bufferingSub = _player.stream.buffering.listen((isBuffering) {
      if (isBuffering) {
        _handleBufferStall();
        _stallTimer?.cancel();
        _stallTimer = Timer(const Duration(milliseconds: 200), () {
          if (_hasConfirmedPlaybackFrame) {
            _enterRuntimePhase(
              kind: PlaybackUiPhaseKind.bufferingRuntime,
              detail: state.isLive
                  ? "Reconnecting to live stream..."
                  : "Buffering playback...",
            );
          } else {
            _enterStartupPhase(
              kind: PlaybackUiPhaseKind.bufferingInitial,
              detail: state.isLive
                  ? "Connecting to live stream..."
                  : "Buffering selected source...",
              attemptIndex: state.currentAttemptIndex == null
                  ? null
                  : state.currentAttemptIndex! + 1,
              attemptTotal: state.sourceAttempts.isEmpty
                  ? null
                  : state.sourceAttempts.length,
            );
          }
        });
      } else {
        _stallTimer?.cancel();
        if (_hasConfirmedPlaybackFrame &&
            state.uiPhase.kind == PlaybackUiPhaseKind.bufferingRuntime) {
          _setIdlePhase();
        }
      }
    });
  }

  void _handleBufferStall() {
    if (!_hasConfirmedPlaybackFrame) {
      return; // ignore stalls during source health check
    }
    if (_isLiveStream(_videoUrl)) return;

    final now = DateTime.now();
    _bufferDepletionTimes.add(now);

    // Keep only stalls in the last 60 seconds
    _bufferDepletionTimes.removeWhere(
      (t) => now.difference(t) > const Duration(seconds: 60),
    );

    if (_bufferDepletionTimes.length >= 2 && !state.isAdaptiveBufferingActive) {
      if (kDebugMode) {
        debugPrint(
          "Multiple buffer stalls detected. Activating adaptive buffering.",
        );
      }
      state = state.copyWith(isAdaptiveBufferingActive: true);

      // Re-apply properties with aggressive buffering
      if (_player.platform is NativePlayer) {
        final settings = ref.read(playerSettingsProvider).asData?.value;
        final readahead = (settings?.readaheadSeconds ?? 180) * 2;
        final native = _player.platform as NativePlayer;
        // Double the readahead and cache for VOD if stalled
        if (_player.state.duration > Duration.zero) {
          native.setProperty('demuxer-readahead-secs', '$readahead');
          native.setProperty('cache-secs', '$readahead');
        }
      }
    }
  }

  void _setupErrorListener() {
    _errorSub = _player.stream.error.listen((error) {
      if (kDebugMode) debugPrint("Player Error: $error");
      if (error.toString().toLowerCase().contains("abort")) return;

      if (!_hasConfirmedPlaybackFrame ||
          _player.state.position == Duration.zero) {
        // Error before playback confirmed — try next source.
        _markSourceAttempt(
          state.currentStreamIndex,
          SourceAttemptStatus.failed,
          isCurrent: false,
        );
        if (_manualSelectionPending) {
          _manualSelectionPending = false;
          revertToPreviousStream("Selected source failed. Reverting...");
        } else {
          retryNextStream(sourceSessionId: state.sourceSessionId);
        }
      } else {
        // Error during active playback.
        if (state.isLive && state.currentStream != null) {
          if (_isRecoveringFromStall) return; // watchdog already reconnecting
          if (kDebugMode) {
            debugPrint("Live stream error. Triggering reconnect...");
          }
          _isRecoveringFromStall = true;
          _enterRuntimePhase(
            kind: PlaybackUiPhaseKind.reconnectingLive,
            detail: "Reconnecting to live stream...",
          );
          changeStream(state.currentStream!, resetPosition: true);
          Future.delayed(const Duration(seconds: 10), () {
            _isRecoveringFromStall = false;
          });
          return;
        }
        _markSourceAttempt(
          state.currentStreamIndex,
          SourceAttemptStatus.failed,
          isCurrent: false,
        );
        _revertMessage =
            "Current source stopped unexpectedly. Trying next available source...";
        retryNextStream(sourceSessionId: state.sourceSessionId);
      }
    });
  }

  void skipLoadingOverlay() {
    state = state.copyWith(userSkippedOverlay: true);
    _setUiPhase(
      _composeUiPhase(kind: state.uiPhase.kind, fullscreenBlocking: false),
    );
  }

  void _setupEventDrivenProgressSaving() {
    _playingSub?.cancel();
    _playingSub = _player.stream.playing.listen((isPlaying) {
      if (!isPlaying) {
        saveProgress();
        _torrentPollTimer?.cancel();
        _torrentPollTimer = null;
      } else {
        // Do NOT call _confirmPlaybackStarted() here — media_kit fires
        // playing=true as soon as open() is called, before any frames arrive.
        // Confirmation happens in _positionSub (position > 0) and
        // _setupVideoParamsListener (video dimensions received).
        if (state.torrentStatus != null && _torrentPollTimer == null) {
          startTorrentPolling();
        }
      }
    });

    _completedSub?.cancel();
    _completedSub = _player.stream.completed.listen((isCompleted) {
      if (isCompleted) {
        final isLive =
            _item.contentType == MultimediaContentType.livestream ||
            _isLiveStream(_videoUrl);
        if (isLive && state.currentStream != null) {
          if (kDebugMode) {
            debugPrint("Live stream reached EOF. Forcing auto-reconnect...");
          }
          _enterRuntimePhase(
            kind: PlaybackUiPhaseKind.reconnectingLive,
            detail: "Reconnecting to live stream...",
          );
          changeStream(state.currentStream!, resetPosition: true);
        }
      }
    });

    _positionSub?.cancel();
    _positionSub = _player.stream.position.listen((pos) {
      if (pos.inMilliseconds > 0 && !_hasConfirmedPlaybackFrame) {
        _confirmPlaybackStarted();
      }

      final now = DateTime.now();

      // --- Stall Watchdog Logic ---
      if (_player.state.playing && !state.isBuffering && !state.isLoading) {
        if (_lastPosition != null && _lastPosition == pos) {
          final stallDuration = _lastPositionUpdateTime != null
              ? now.difference(_lastPositionUpdateTime!)
              : Duration.zero;

          if (stallDuration.inSeconds >= 5 && !_isRecoveringFromStall) {
            if (kDebugMode) {
              debugPrint(
                "Watchdog: Silent stall detected (5s). Kicking engine...",
              );
            }
            _isRecoveringFromStall = true;

            // Recovery: reconnect live streams from scratch; kick VOD.
            if (state.isLive && state.currentStream != null) {
              changeStream(state.currentStream!, resetPosition: true);
            } else {
              _player.play();
            }

            // prevent multi-trigger
            Future.delayed(const Duration(seconds: 10), () {
              _isRecoveringFromStall = false;
            });
          }
        } else {
          _lastPosition = pos;
          _lastPositionUpdateTime = now;
        }
      } else {
        _lastPosition = pos;
        _lastPositionUpdateTime = now;
      }
      // -----------------------------

      final duration = _player.state.duration;
      if (duration == Duration.zero) return;

      final currentPct = pos.inMilliseconds / duration.inMilliseconds;
      final lastPct =
          _lastSavedPosition.inMilliseconds / duration.inMilliseconds;

      if ((currentPct - lastPct).abs() >= _saveThresholdPercent) {
        saveProgress();
        _lastSavedPosition = pos;
      }

      // Next Episode Detection (Series only, trigger 15s before end)
      if (!_suppressNextEpisodeDetection &&
          _item.contentType == MultimediaContentType.series) {
        final remaining = duration - pos;
        if (remaining.inSeconds <= 15 &&
            remaining.inSeconds > 0 &&
            !state.showNextEpisodeOverlay) {
          // Use _episode if available, otherwise fallback to URL matching
          int? currentIndex;
          if (_episode != null) {
            currentIndex = _item.episodes?.indexWhere(
              (e) => e.url == _episode!.url,
            );
          } else {
            currentIndex = _item.episodes?.indexWhere(
              (e) => e.url == _videoUrl,
            );
          }

          if (currentIndex != null &&
              currentIndex != -1 &&
              currentIndex < _item.episodes!.length - 1) {
            final next = _item.episodes![currentIndex + 1];
            state = state.copyWith(
              showNextEpisodeOverlay: true,
              nextEpisodeTitle: next.name,
            );
          }
        } else if (remaining.inSeconds > 15 && state.showNextEpisodeOverlay) {
          state = state.copyWith(showNextEpisodeOverlay: false);
        }
      }
    });
  }

  Future<void> _initStream({
    PlaybackUiPhaseKind requestedPhaseKind =
        PlaybackUiPhaseKind.fetchingSources,
    bool forceNewSourceSession = true,
  }) async {
    final sourceSessionId = forceNewSourceSession
        ? _beginSourceSession(resetAttempts: true)
        : state.sourceSessionId;

    String detail = "Fetching sources...";
    switch (requestedPhaseKind) {
      case PlaybackUiPhaseKind.loadingNextEpisode:
        // Enhancement: Use startup (blocking) phase so the screen goes dark
        // instead of showing controls over the previous episode's frame.
        _enterStartupPhase(
          kind: PlaybackUiPhaseKind.loadingNextEpisode,
          detail: "Loading next episode...",
        );
        break;
      case PlaybackUiPhaseKind.switchingSource:
        _enterRuntimePhase(
          kind: PlaybackUiPhaseKind.switchingSource,
          detail: "Switching source...",
        );
        break;
      case PlaybackUiPhaseKind.reconnectingLive:
        _enterRuntimePhase(
          kind: PlaybackUiPhaseKind.reconnectingLive,
          detail: "Reconnecting to live stream...",
        );
        break;
      default:
        if (_item.provider == 'Local' || AppUtils.isLocalFile(_videoUrl)) {
          detail = "Opening local file...";
        } else if (_item.provider == 'Torrent' ||
            _videoUrl.startsWith("magnet:") ||
            _videoUrl.endsWith(".torrent")) {
          detail = "Preparing torrent stream...";
        }
        _enterStartupPhase(kind: requestedPhaseKind, detail: detail);
    }

    state = state.copyWith(currentAttemptIndex: null);

    if (await _handleSpecialProviders()) return;

    final activeProvider = _resolveProvider();
    if (activeProvider == null) {
      state = state.copyWith(errorMessage: "No provider selected.");
      return;
    }

    try {
      if (_videoUrl.isNotEmpty) {
        state = state.copyWith(streamSubtitle: "Fetching sources...");
        if (await _handleFallbackTorrent()) return;

        final rawStreams = await activeProvider.loadStreams(_videoUrl);
        if (!_isCurrentSourceSession(sourceSessionId)) return;
        if (rawStreams.isNotEmpty) {
          // Sort streams by quality preference based on current network type.
          // Wi-Fi → wifiQuality preference, mobile/other → mobileQuality.
          // Sources with unrecognised quality labels go to the end (best-effort).
          final settings = ref.read(playerSettingsProvider).asData?.value;
          final streams = settings == null
              ? rawStreams
              : await _sortedByQuality(rawStreams, settings);
          if (!_isCurrentSourceSession(sourceSessionId)) return;

          final initialIndex = _findSavedStreamIndex(streams);
          state = state.copyWith(
            streams: streams,
            currentStreamIndex: initialIndex,
          );
          final checkCount = streams.length > 3 ? 3 : streams.length;

          // Issue 1: Mark ALL batch candidates as `trying` before parallel check,
          // so the UI shows the correct status for each source being checked.
          _setSourceAttemptsFromStreams(streams);
          if (checkCount > 1) {
            final batchIndices = {
              for (int i = 0; i < checkCount; i++)
                (initialIndex + i) % streams.length,
            };
            final updated = state.sourceAttempts
                .map(
                  (e) => batchIndices.contains(e.index)
                      ? e.copyWith(
                          status: SourceAttemptStatus.trying,
                          isCurrent: e.index == initialIndex,
                        )
                      : e,
                )
                .toList();
            state = state.copyWith(
              sourceAttempts: updated,
              currentAttemptIndex: initialIndex,
            );
          } else {
            _markSourceAttempt(initialIndex, SourceAttemptStatus.trying);
          }

          // Issue 2: No attemptIndex/attemptTotal during batch check —
          // "Source X of N" is meaningless when checking 3 at once.
          _enterStartupPhase(
            kind: PlaybackUiPhaseKind.checkingSources,
            detail: checkCount > 1
                ? "Checking $checkCount sources..."
                : "Preparing selected source...",
          );

          // PERFORMANCE: Parallel check the first few streams (health check)
          // This avoids waiting for a timeout on a dead stream if a working one is available
          final workingIndex = await _findFirstWorkingStream(
            streams,
            startIndex: initialIndex,
            limit: checkCount,
            sourceSessionId: sourceSessionId,
          );
          if (!_isCurrentSourceSession(sourceSessionId)) return;

          await loadStreamAtIndex(
            workingIndex,
            sourceSessionId: sourceSessionId,
          );
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Error loading streams: $e");
    }

    if (!_isCurrentSourceSession(sourceSessionId)) return;
    state = state.copyWith(errorMessage: "No streams found.");
  }

  Future<bool> _handleSpecialProviders() async {
    if (_item.provider == 'Remote' ||
        _item.provider == 'Local' ||
        _item.provider == 'Torrent' ||
        AppUtils.isLocalFile(_videoUrl)) {
      final isTorrent =
          _item.provider == 'Torrent' ||
          _videoUrl.startsWith("magnet:") ||
          _videoUrl.endsWith(".torrent");

      final stream = StreamResult(
        url: _videoUrl,
        source: isTorrent ? "Torrent" : "Video",
        headers: {},
      );

      state = state.copyWith(streams: [stream], currentStreamIndex: 0);
      _setSourceAttemptsFromStreams([stream], activeIndex: 0);
      await loadStreamAtIndex(0, sourceSessionId: state.sourceSessionId);
      return true;
    }
    return false;
  }

  Future<bool> _handleFallbackTorrent() async {
    if (_videoUrl.startsWith("magnet:") || _videoUrl.endsWith(".torrent")) {
      final stream = StreamResult(
        url: _videoUrl,
        source: "Torrent",
        headers: {},
      );
      state = state.copyWith(streams: [stream], currentStreamIndex: 0);
      _setSourceAttemptsFromStreams([stream], activeIndex: 0);
      await loadStreamAtIndex(0, sourceSessionId: state.sourceSessionId);
      return true;
    }
    return false;
  }

  SkyStreamProvider? _resolveProvider() {
    final activeState = ref.read(activeProviderProvider);
    final manager = ref.read(extensionManagerProvider.notifier);

    if (_item.provider != null) {
      try {
        final val = _item.provider!;
        return manager.getAllProviders().firstWhere(
          (p) => p.packageName == val || p.name == val,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('PlayerController._resolveProvider: $e');
      }
    }
    return activeState;
  }

  int _findSavedStreamIndex(List<StreamResult> streams) {
    try {
      final historyRepo = ref.read(historyRepositoryProvider);
      final isSeries = _item.contentType == MultimediaContentType.series;

      String? lastUrl;
      if (isSeries) {
        lastUrl = historyRepo.getLastStreamUrl(_item.url);
      }

      if (lastUrl == null) {
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
        lastUrl = previousState.lastStreamUrl;
      }

      if (lastUrl != null) {
        final foundIndex = streams.indexWhere((s) => s.url == lastUrl);
        if (foundIndex != -1) return foundIndex;
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Error checking saved stream quality: $e");
    }
    return 0;
  }

  Episode? _resolveCurrentEpisode() {
    if (_episode != null) return _episode;
    if (_item.contentType != MultimediaContentType.series) return null;
    return _item.episodes?.firstWhereOrNull((e) => e.url == _videoUrl);
  }

  List<SubtitleFile> _effectiveExternalSubtitles(
    List<SubtitleFile>? streamSubtitles,
  ) {
    final merged = <SubtitleFile>[];
    final seenUrls = <String>{};

    for (final sub in [...?streamSubtitles, ..._userAddedExternalSubtitles]) {
      if (seenUrls.add(sub.url)) {
        merged.add(sub);
      }
    }

    return merged;
  }

  List<SubtitleTrackConfig> _buildSubtitleConfigs(
    List<SubtitleFile> subtitles,
  ) {
    return subtitles
        .map(
          (subtitle) => SubtitleTrackConfig(
            uri: subtitle.url,
            mimeType: subtitle.url.toLowerCase().endsWith('.vtt')
                ? 'text/vtt'
                : 'application/x-subrip',
            language: subtitle.lang ?? 'und',
          ),
        )
        .toList();
  }

  String _languageName(String code) {
    return code.trim();
  }

  String _formatTrackLabel({
    String? language,
    String? title,
    String? fallbackId,
  }) {
    final List<String> parts = [];
    if (language != null && language.trim().isNotEmpty) {
      parts.add(language.trim());
    }
    if (title != null && title.trim().isNotEmpty) {
      parts.add(title.trim());
    }

    if (parts.isNotEmpty) {
      return parts.join(' - ');
    }

    return fallbackId != null && fallbackId.trim().isNotEmpty
        ? (int.tryParse(fallbackId) != null
              ? 'Audio Track $fallbackId'
              : fallbackId)
        : 'Unknown Track';
  }

  String? _formatTechnicalSubtitle(dynamic track) {
    try {
      final List<String> techParts = [];

      // Extract raw technical tags from the track object (media_kit specific)
      // We use dynamic access as these fields exist in the runtime object but
      // may not be present in early/stub versions of the class.
      final String? codec = track.codec?.toString();
      final String? channels = track.channels?.toString();
      final dynamic samplerate = track.samplerate;

      if (codec != null && codec.isNotEmpty && codec != 'null') {
        techParts.add(codec.toUpperCase());
      }

      if (channels != null &&
          channels.isNotEmpty &&
          channels != 'null' &&
          channels != 'unknown') {
        techParts.add(channels);
      }

      if (samplerate != null && samplerate is num && samplerate > 0) {
        techParts.add(
          '${(samplerate / 1000).toStringAsFixed(1).replaceAll('.0', '')}kHz',
        );
      }

      if (techParts.isNotEmpty) {
        return techParts.join(' · ');
      }
    } catch (_) {
      // Fallback if specific fields are inaccessible
    }
    return null;
  }

  Future<void> _openResolvedStream(
    String playUrl,
    StreamResult stream,
    Map<String, String> headers, {
    required bool useVideoView,
  }) async {
    if (useVideoView) {
      // Pause media_kit so it stops consuming bandwidth while video_view plays.
      // (media_kit.open() will replace it if the user switches back.)
      if (!state.useExoPlayer) {
        await _player.pause();
      }

      String finalUrl = playUrl;
      if (finalUrl.contains('play.php') || finalUrl.contains('index.php')) {
        finalUrl = LocalProxyService.instance.getProxyUrl(
          finalUrl,
          headers: headers,
          forceM3u8Extension: true,
        );
        if (kDebugMode) {
          debugPrint("[PLAYER] Proxied non-standard HLS: $finalUrl");
        }
      }

      final subs = state.externalSubtitles;
      if (subs.isNotEmpty && _videoViewSupportsMergedExternalSubtitles) {
        _videoViewController!.openWithSubtitles(
          finalUrl,
          headers: headers,
          subtitles: _buildSubtitleConfigs(subs),
          drmKey: stream.drmKey,
          drmKid: stream.drmKid,
        );
      } else {
        _videoViewController!.open(
          finalUrl,
          headers: headers,
          drmKey: stream.drmKey,
          drmKid: stream.drmKid,
        );
      }
      state = state.copyWith(useExoPlayer: true, isSeekable: false);
      return;
    }

    // Close video_view before handing off to media_kit so ExoPlayer/AVPlayer
    // stops buffering and releases its surface while media_kit plays.
    if (state.useExoPlayer) {
      _videoViewController?.close();
    }

    await _player.open(Media(playUrl, httpHeaders: headers));
    state = state.copyWith(useExoPlayer: false, isSeekable: true);
  }

  Future<void> seekTo(Duration position, {bool fast = false}) async {
    if (!state.canSeek) return;

    final clamped = position < Duration.zero ? Duration.zero : position;

    if (state.useExoPlayer && _videoViewController != null) {
      _videoViewController!.seekTo(clamped.inMilliseconds, fast: fast);
      return;
    }

    await _player.seek(clamped);
  }

  Future<void> seekRelative(Duration amount, {bool fast = false}) async {
    if (!state.canSeek) return;

    final currentPosition = state.useExoPlayer
        ? Duration(milliseconds: _videoViewController?.position.value ?? 0)
        : _player.state.position;

    await seekTo(currentPosition + amount, fast: fast);
  }

  Future<void> play() async {
    if (state.useExoPlayer && _videoViewController != null) {
      _videoViewController!.play();
      return;
    }

    await _player.play();
  }

  Future<void> pause() async {
    if (state.useExoPlayer && _videoViewController != null) {
      _videoViewController!.pause();
      return;
    }

    await _player.pause();
  }

  Future<void> togglePlayPause() async {
    final isPlaying = state.useExoPlayer && _videoViewController != null
        ? _videoViewController!.playbackState.value ==
              VideoControllerPlaybackState.playing
        : _player.state.playing;

    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  PlayerTrackSelectionSnapshot getTrackSelectionSnapshot() {
    if (state.useExoPlayer && _videoViewController != null) {
      final controller = _videoViewController!;
      final info = controller.mediaInfo.value;
      if (info == null) {
        return const PlayerTrackSelectionSnapshot();
      }

      final overrideAudio = controller.overrideAudio.value;
      final overrideSubtitle = controller.overrideSubtitle.value;
      final showSubtitle = controller.showSubtitle.value;

      final audioTracks = info.audioTracks.entries
          .map(
            (entry) => PlayerTrackOption(
              id: entry.key,
              label: _formatTrackLabel(
                language: entry.value.language,
                title: entry.value.title,
                fallbackId: entry.key,
              ),
              subtitle: entry.value.format,
              selected:
                  overrideAudio == entry.key ||
                  (overrideAudio == null && info.audioTracks.length == 1),
            ),
          )
          .toList();

      final subtitleTracks = info.subtitleTracks.entries
          .map(
            (entry) => PlayerTrackOption(
              id: entry.key,
              label: _formatTrackLabel(
                language: entry.value.language,
                title: entry.value.title,
                fallbackId: entry.key,
              ),
              subtitle: entry.value.format,
              selected: showSubtitle && overrideSubtitle == entry.key,
            ),
          )
          .toList();

      return PlayerTrackSelectionSnapshot(
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        subtitlesOffSelected: !showSubtitle,
      );
    }

    final audioTracks = _player.state.tracks.audio
        .map(
          (track) => PlayerTrackOption(
            id: track.id,
            label: _formatTrackLabel(
              language: track.language,
              title: track.title,
              fallbackId: track.id,
            ),
            subtitle: _formatTechnicalSubtitle(track),
            selected: track == _player.state.track.audio,
          ),
        )
        .toList();

    final subtitleTracks = <PlayerTrackOption>[
      ...state.externalSubtitles.map(
        (subtitle) => PlayerTrackOption(
          id: 'external:${subtitle.url}',
          label: subtitle.label,
          subtitle: subtitle.lang != null
              ? _languageName(subtitle.lang!)
              : null,
          selected:
              _player.state.track.subtitle.id == subtitle.url ||
              _player.state.track.subtitle.id == 'external:${subtitle.url}',
        ),
      ),
      ..._player.state.tracks.subtitle.map(
        (track) => PlayerTrackOption(
          id: track.id,
          label: _formatTrackLabel(
            language: track.language,
            title: track.title,
            fallbackId: track.id,
          ),
          selected: track == _player.state.track.subtitle,
        ),
      ),
    ];

    return PlayerTrackSelectionSnapshot(
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      subtitlesOffSelected: _player.state.track.subtitle == SubtitleTrack.no(),
    );
  }

  Future<void> selectAudioTrack(String id) async {
    if (state.useExoPlayer && _videoViewController != null) {
      _videoViewController!.setOverrideAudio(id);
      return;
    }

    final track = _player.state.tracks.audio.firstWhereOrNull(
      (t) => t.id == id,
    );
    if (track != null) {
      await _player.setAudioTrack(track);
    }
  }

  Future<void> selectSubtitleTrack(String? id) async {
    if (state.useExoPlayer && _videoViewController != null) {
      if (id == null) {
        _videoViewController!.setShowSubtitle(false);
        if (_videoViewController!.overrideSubtitle.value != null) {
          _videoViewController!.setOverrideSubtitle(null);
        }
        return;
      }

      _videoViewController!.setShowSubtitle(true);
      _videoViewController!.setOverrideSubtitle(id);
      return;
    }

    if (id == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }

    if (id.startsWith('external:')) {
      final url = id.substring('external:'.length);
      final subtitle = state.externalSubtitles.firstWhereOrNull(
        (sub) => sub.url == url,
      );
      if (subtitle != null) {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            subtitle.url,
            title: subtitle.label,
            language: subtitle.lang,
          ),
        );
      }
      return;
    }

    final embeddedId = id.startsWith('embedded:')
        ? id.substring('embedded:'.length)
        : id;
    final track = _player.state.tracks.subtitle.firstWhereOrNull(
      (t) => t.id == embeddedId,
    );
    if (track != null) {
      await _player.setSubtitleTrack(track);
    }
  }

  Future<bool> _isStreamCandidateHealthy(StreamResult stream) async {
    if (stream.url.startsWith("magnet:") ||
        stream.url.endsWith(".torrent") ||
        stream.url.startsWith("/")) {
      return true;
    }

    final uri = Uri.parse(stream.url);
    final headers = <String, String>{...?stream.headers};

    try {
      final resp = await http
          .head(uri, headers: headers)
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode < 400) return true;
    } catch (_) {
      // Fall back to a ranged GET below.
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.headers.addAll(headers);
      request.headers.putIfAbsent('Range', () => 'bytes=0-0');
      final resp = await client
          .send(request)
          .timeout(const Duration(seconds: 3));
      final subscription = resp.stream.listen((_) {});
      await subscription.cancel();
      return resp.statusCode < 400 || resp.statusCode == 416;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> loadStreamAtIndex(
    int index, {
    int? sourceSessionId,
    bool manualSelection = false,
  }) async {
    if (index < 0 || index >= state.streams.length) return;
    if (sourceSessionId != null && !_isCurrentSourceSession(sourceSessionId)) {
      return;
    }

    final stream = state.streams[index];
    final rawProviderName =
        _item.provider ??
        ref.read(activeProviderProvider)?.name ??
        "Unknown";
    final providerName = _getProviderDisplayName(rawProviderName);
    final subtitles = _effectiveExternalSubtitles(stream.subtitles);
    final attemptTotal = state.sourceAttempts.isEmpty
        ? state.streams.length
        : state.sourceAttempts.length;
    _markSourceAttempt(
      index,
      manualSelection
          ? SourceAttemptStatus.selected
          : SourceAttemptStatus.trying,
    );
    _manualSelectionPending = manualSelection;

    // Issue 3: Detect torrent streams early so the overlay shows the correct detail
    // before _resolveStreamUrl is called (which internally resolves the torrent URL).
    final isTorrentStream =
        stream.url.startsWith("magnet:") ||
        stream.url.endsWith(".torrent") ||
        (stream.url.startsWith("/") && stream.source.contains("Torrent"));

    state = state.copyWith(
      currentStreamIndex: index,
      currentStream: stream,
      streamSubtitle: "$providerName - ${stream.source}",
      externalSubtitles: subtitles,
      isLive:
          _item.contentType == MultimediaContentType.livestream ||
          _isLiveStream(stream.url),
    );

    // Issue 1: Manual source selection after playback is confirmed should not
    // block the screen — use a non-blocking runtime phase so the current frame
    // stays visible while the new source opens.
    if (manualSelection && _hasConfirmedPlaybackFrame) {
      _enterRuntimePhase(
        kind: PlaybackUiPhaseKind.switchingSource,
        detail: "Switching to ${stream.source}...",
      );
    } else {
      _enterStartupPhase(
        kind: PlaybackUiPhaseKind.openingSource,
        detail: isTorrentStream
            ? "Initializing torrent engine..."
            : "Opening ${stream.source}...",
        attemptIndex: index + 1,
        attemptTotal: attemptTotal,
      );
    }

    try {
      final playUrl = await _resolveStreamUrl(stream);
      if (playUrl == null) throw Exception("Failed to resolve stream URL");
      if (sourceSessionId != null &&
          !_isCurrentSourceSession(sourceSessionId)) {
        return;
      }

      if (playUrl.contains("index=")) {
        startTorrentPolling(playUrl);
      } else {
        stopTorrentPolling();
      }

      final resolvedIsLive = _detectResolvedLiveState(playUrl);
      final useVideoView = _canUseVideoViewForStream(
        playUrl,
        stream,
        isLive: resolvedIsLive,
      );
      if (sourceSessionId != null &&
          !_isCurrentSourceSession(sourceSessionId)) {
        return;
      }
      state = state.copyWith(
        streamSubtitle: "$providerName - ${stream.source}",
        isLive: resolvedIsLive,
        isSeekable: !useVideoView,
      );
      if (state.useExoPlayer != useVideoView && _hasConfirmedPlaybackFrame) {
        _enterRuntimePhase(
          kind: PlaybackUiPhaseKind.switchingEngine,
          detail: "Optimizing playback...",
        );
      }

      final headers = stream.headers ?? {};
      await _applyPlaybackProperties(
        headers,
        stream,
        useVideoView: useVideoView,
      );
      if (sourceSessionId != null &&
          !_isCurrentSourceSession(sourceSessionId)) {
        return;
      }
      await _openResolvedStream(
        playUrl,
        stream,
        headers,
        useVideoView: useVideoView,
      );
      if (sourceSessionId != null &&
          !_isCurrentSourceSession(sourceSessionId)) {
        return;
      }
      _enterStartupPhase(
        kind: PlaybackUiPhaseKind.bufferingInitial,
        detail: resolvedIsLive
            ? "Connecting to live stream..."
            : "Buffering selected source...",
        attemptIndex: index + 1,
        attemptTotal: attemptTotal,
      );

      final historyRepo = ref.read(historyRepositoryProvider);
      final isSeries = _item.contentType == MultimediaContentType.series;

      int savedPos = 0;
      if (isSeries) {
        final ep = _resolveCurrentEpisode();
        final historyEpisodeUrl = ep?.url ?? _videoUrl;
        savedPos = historyRepo.getEpisodePosition(
          historyEpisodeUrl,
          mainUrl: _item.url,
          season: ep?.season,
          episode: ep?.episode,
        );
      } else {
        savedPos = historyRepo.getPosition(_item.url);
      }

      if (savedPos > 0) {
        // Show prompt instead of seeking silently — user may want to start over.
        state = state.copyWith(resumePromptPosition: savedPos);
      }
    } catch (e) {
      if (sourceSessionId != null &&
          !_isCurrentSourceSession(sourceSessionId)) {
        return;
      }
      if (kDebugMode) debugPrint("Stream $index failed: $e");
      _markSourceAttempt(index, SourceAttemptStatus.failed, isCurrent: false);
      if (manualSelection) {
        // Issue 2: Don't show "all sources failed" for a manual pick — revert
        // silently to the previously playing source instead.
        revertToPreviousStream(
          "Selected source is not playable. Reverting back to previous source.",
        );
        return;
      }
      retryNextStream(sourceSessionId: sourceSessionId);
    }
  }

  /// Called when the user taps "Resume" in the resume prompt overlay.
  Future<void> confirmResume() async {
    final pos = state.resumePromptPosition;
    state = state.copyWith(resumePromptPosition: null);
    if (pos != null && pos > 0) {
      _pendingResumeSeekPosition = pos;
      await _flushPendingResumeSeek();
    }
  }

  /// Called when the user taps "Start Over" or the prompt auto-dismisses.
  void dismissResumePrompt() {
    _pendingResumeSeekPosition = null;
    state = state.copyWith(resumePromptPosition: null);
  }

  /// Jumps back to the live edge. For DVR streams, seeks to the end of the
  /// known duration; for pure live streams, forces a full reconnect.
  Future<void> goLive() async {
    if (!state.isLive || state.currentStream == null) return;
    final dur = state.useExoPlayer
        ? Duration(
            milliseconds: _videoViewController?.mediaInfo.value?.duration ?? 0,
          )
        : _player.state.duration;
    if (dur > Duration.zero) {
      await seekTo(dur);
    } else {
      _enterRuntimePhase(
        kind: PlaybackUiPhaseKind.reconnectingLive,
        detail: "Reconnecting to live stream...",
      );
      changeStream(state.currentStream!, resetPosition: true);
    }
  }

  Future<void> changeStream(
    StreamResult stream, {
    bool isRevert = false,
    bool resetPosition = false,
    bool manualSelection = false,
  }) async {
    final matchingIndex = state.streams.indexWhere(
      (candidate) =>
          candidate.url == stream.url && candidate.source == stream.source,
    );
    if (!isRevert) {
      state = state.copyWith(
        previousStream: state.currentStream,
        currentStreamIndex: matchingIndex == -1
            ? state.currentStreamIndex
            : matchingIndex,
      );
    }

    // Track that this is a user-initiated switch so the error listeners can
    // revert to the previous source instead of falling through to retryNextStream.
    if (manualSelection && !isRevert) {
      _manualSelectionPending = true;
    }

    final rawPName =
        _item.provider ??
        ref.read(activeProviderProvider)?.name ??
        'Unknown';
    final pName = _getProviderDisplayName(rawPName);

    // Capture current position before we switch engines/streams.
    // Read from whichever engine is currently active.
    final oldPos = state.useExoPlayer
        ? Duration(milliseconds: _videoViewController?.position.value ?? 0)
        : _player.state.position;

    _enterRuntimePhase(
      kind: PlaybackUiPhaseKind.switchingSource,
      detail: "Switching to ${stream.source}...",
    );

    try {
      final playUrl = await _resolveStreamUrl(stream);
      if (playUrl == null) throw Exception("Failed to resolve stream URL");
      final subtitles = _effectiveExternalSubtitles(stream.subtitles);

      final resolvedIsLive = _detectResolvedLiveState(playUrl);
      final useVideoView = _canUseVideoViewForStream(
        playUrl,
        stream,
        isLive: resolvedIsLive,
      );
      if (state.useExoPlayer != useVideoView && _hasConfirmedPlaybackFrame) {
        _enterRuntimePhase(
          kind: PlaybackUiPhaseKind.switchingEngine,
          detail: "Optimizing playback...",
        );
      }
      state = state.copyWith(
        currentStream: stream,
        externalSubtitles: subtitles,
        isLive: resolvedIsLive,
        isSeekable: !useVideoView,
        streamSubtitle: "$pName - ${stream.source}",
      );

      if (playUrl.contains("index=")) {
        startTorrentPolling(playUrl);
      } else {
        stopTorrentPolling();
      }

      final headers = stream.headers ?? {};
      await _applyPlaybackProperties(
        headers,
        stream,
        useVideoView: useVideoView,
      );
      await _openResolvedStream(
        playUrl,
        stream,
        headers,
        useVideoView: useVideoView,
      );

      if (oldPos > Duration.zero && !resetPosition) {
        await _safeSeekTo(oldPos.inMilliseconds);
      } else if (resetPosition) {
        await seekTo(Duration.zero, fast: true);
      }
    } catch (e) {
      _manualSelectionPending = false;
      if (kDebugMode) debugPrint("Change stream failed: $e");
      if (isRevert) {
        state = state.copyWith(errorMessage: "Revert failed: $e");
      } else {
        revertToPreviousStream(
          "Could not switch to selected source. Reverting back to previous source.",
        );
      }
    }
  }

  Future<void> retryNextStream({int? sourceSessionId}) async {
    if (sourceSessionId != null && !_isCurrentSourceSession(sourceSessionId)) {
      return;
    }

    // Find the next index that isn't already failed
    int nextIndex = state.currentStreamIndex + 1;
    while (nextIndex < state.streams.length) {
      final attempt = state.sourceAttempts.firstWhereOrNull(
        (e) => e.index == nextIndex,
      );
      if (attempt == null || attempt.status != SourceAttemptStatus.failed) {
        break;
      }
      nextIndex++;
    }

    if (nextIndex < state.streams.length) {
      final nextAttempt = state.sourceAttempts.firstWhereOrNull(
        (e) => e.index == nextIndex,
      );
      // If nextIndex already passed the health check in a prior batch (status=trying),
      // reuse it directly — no need to re-check.
      final alreadyHealthChecked =
          nextAttempt?.status == SourceAttemptStatus.trying;

      // Whether any candidate beyond nextIndex has already been health-checked.
      final hasNextChecked = state.sourceAttempts.any(
        (e) => e.index > nextIndex && e.status != SourceAttemptStatus.pending,
      );

      int targetIndex = nextIndex;

      if (alreadyHealthChecked) {
        // Fast path: nextIndex was already confirmed healthy in the previous batch.
        // Show a counter (single source), no re-check needed.
        // Fix Q1: explicit empty subtitle so the old source name isn't shown.
        _enterStartupPhase(
          kind: PlaybackUiPhaseKind.checkingSources,
          subtitle: '',
          detail: "Source failed. Trying next source...",
          attemptIndex: nextIndex + 1,
          attemptTotal: state.sourceAttempts.isEmpty
              ? state.streams.length
              : state.sourceAttempts.length,
        );
      } else if (!hasNextChecked && state.streams.length > nextIndex + 1) {
        // Batch path: entering a new, unchecked window — run parallel health check.
        final checkCount = (state.streams.length - nextIndex) > 3
            ? 3
            : (state.streams.length - nextIndex);

        // Mark all batch candidates as `trying` BEFORE the parallel check so the
        // source list shows the correct status, and enter a counter-free phase so
        // "Source X of N" doesn't linger from the previous failed source.
        final batchIndices = {
          for (int i = 0; i < checkCount; i++)
            (nextIndex + i) % state.streams.length,
        };
        final updatedAttempts = state.sourceAttempts
            .map(
              (e) => batchIndices.contains(e.index)
                  ? e.copyWith(
                      status: SourceAttemptStatus.trying,
                      isCurrent: e.index == nextIndex,
                    )
                  : e,
            )
            .toList();
        state = state.copyWith(
          sourceAttempts: updatedAttempts,
          currentAttemptIndex: nextIndex,
          // Fix Q1: clear old source name so the subtitle doesn't show
          // the failed source during the parallel check.
          streamSubtitle: "Checking sources...",
        );
        _enterStartupPhase(
          kind: PlaybackUiPhaseKind.checkingSources,
          // No attemptIndex/attemptTotal: counter is meaningless for a batch.
          detail: "Checking $checkCount sources...",
        );

        targetIndex = await _findFirstWorkingStream(
          state.streams,
          startIndex: nextIndex,
          limit: checkCount,
          sourceSessionId: sourceSessionId,
        );
      } else {
        // Single next source (last in list, or all others already checked).
        _enterStartupPhase(
          kind: PlaybackUiPhaseKind.checkingSources,
          subtitle: '',
          detail: "Source failed. Trying next source...",
          attemptIndex: nextIndex + 1,
          attemptTotal: state.sourceAttempts.isEmpty
              ? state.streams.length
              : state.sourceAttempts.length,
        );
      }

      _markSourceAttempt(targetIndex, SourceAttemptStatus.trying);
      unawaited(
        loadStreamAtIndex(targetIndex, sourceSessionId: sourceSessionId),
      );
    } else {
      // All sources exhausted — always show the blocking error overlay regardless
      // of whether playback had started. The overlay has a "Go Back" button.
      _enterAllSourcesFailedPhase();
    }
  }

  void revertToPreviousStream(String message) {
    if (state.previousStream == null) {
      // No previous stream to revert to — skip to the next available source.
      retryNextStream(sourceSessionId: state.sourceSessionId);
      return;
    }
    _revertMessage = message;
    changeStream(state.previousStream!, isRevert: true);
  }

  /// Consumed by the UI to show a one-time snackbar/toast. Null after read.
  String? _revertMessage;
  String? consumeRevertMessage() {
    final msg = _revertMessage;
    _revertMessage = null;
    return msg;
  }

  Future<void> onTorrentFileSelected(int index) async {
    _enterRuntimePhase(
      kind: PlaybackUiPhaseKind.switchingSource,
      detail: "Switching torrent file...",
    );
    try {
      final url = await ref
          .read(torrentServiceProvider)
          .getStreamUrlForFileIndex(index);
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
          if (kDebugMode) {
            debugPrint('PlayerController.onTorrentFileSelected: $e');
          }
        }

        final newStream = StreamResult(
          url: url,
          source: "Torrent ($fileLabel)",
          headers: {},
        );
        changeStream(newStream, resetPosition: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Failed to switch file: $e");
    }
  }

  Future<void> playNextEpisode() async {
    if (_item.contentType != MultimediaContentType.series) return;

    int? currentIndex;
    if (_episode != null) {
      currentIndex = _item.episodes?.indexWhere((e) => e.url == _episode!.url);
    } else {
      currentIndex = _item.episodes?.indexWhere((e) => e.url == _videoUrl);
    }

    if (currentIndex != null &&
        currentIndex != -1 &&
        currentIndex < _item.episodes!.length - 1) {
      final nextEpisode = _item.episodes![currentIndex + 1];

      // Smart Next Episode: Check for downloaded version
      final downloadService = ref.read(downloadServiceProvider);
      final localFile = await downloadService.getDownloadedFile(
        _item,
        episode: nextEpisode,
      );

      final String finalUrl = localFile?.path ?? nextEpisode.url;
      final bool isLocal = localFile != null;

      // Save current episode's progress BEFORE updating _episode/_videoUrl.
      // pause() (below) triggers saveProgress() via _playingSub — if _episode
      // already points to nextEpisode at that point, the current position gets
      // written under the wrong episode's history key (classic off-by-one bug).
      saveProgress();
      await pause(); // _episode still = current ep here, so any triggered save is correct

      // NOW switch context to the next episode.
      _suppressNextEpisodeDetection = true;
      _hasConfirmedPlaybackFrame = false;
      _videoUrl = finalUrl;
      _episode = nextEpisode;
      _userAddedExternalSubtitles.clear();
      state = state.copyWith(
        playerTitle: "${_item.title} - ${nextEpisode.name}",
        showNextEpisodeOverlay: false,
        streamSubtitle: isLocal ? "Local - Downloaded" : "Fetching sources...",
      );

      await _initStream(
        requestedPhaseKind: PlaybackUiPhaseKind.loadingNextEpisode,
      );
    }
  }

  void dismissNextEpisodeOverlay() {
    state = state.copyWith(showNextEpisodeOverlay: false);
  }

  void toggleEpisodeList() {
    state = state.copyWith(showEpisodeList: !state.showEpisodeList);
  }

  Future<void> loadEpisode(Episode episode) async {
    if (state.isLoading) return; // guard: uiPhase-derived getter
    state = state.copyWith(showEpisodeList: false);

    // Save current episode's progress BEFORE changing _episode/_videoUrl,
    // so the history key written by pause()-triggered saves is correct.
    saveProgress();

    // Smart load: Check for downloaded version
    final downloadService = ref.read(downloadServiceProvider);
    final localFile = await downloadService.getDownloadedFile(
      _item,
      episode: episode,
    );

    final String finalUrl = localFile?.path ?? episode.url;
    final bool isLocal = localFile != null;

    // Pause while _episode/_videoUrl still point to the old episode.
    await pause();

    // NOW switch context to the selected episode.
    _episode = episode;
    _videoUrl = finalUrl;
    _hasConfirmedPlaybackFrame = false;
    _suppressNextEpisodeDetection = true;
    _userAddedExternalSubtitles.clear();

    state = state.copyWith(
      playerTitle: "${_item.title} - ${episode.name}",
      streamSubtitle: isLocal ? "Local - Downloaded" : "Fetching sources...",
    );

    await _initStream(
      requestedPhaseKind: PlaybackUiPhaseKind.loadingNextEpisode,
    );
  }

  void saveProgress() {
    try {
      // Read position/duration from whichever engine is currently active.
      final int pos;
      final int dur;
      if (state.useExoPlayer && _videoViewController != null) {
        pos = _videoViewController!.position.value;
        dur = _videoViewController!.mediaInfo.value?.duration ?? 0;
      } else {
        pos = _player.state.position.inMilliseconds;
        dur = _player.state.duration.inMilliseconds;
      }
      final isLivestream =
          _item.contentType == MultimediaContentType.livestream;

      // Livestreams: save to history without progress (position=0, duration=0)
      if (isLivestream) {
        final pId =
            _item.provider ??
            ref.read(activeProviderProvider)?.packageName ??
            'Unknown';
        final itemToSave = _item.copyWith(provider: pId);
        ref
            .read(watchHistoryProvider.notifier)
            .saveProgress(
              itemToSave,
              0,
              0,
              lastStreamUrl: null, // Don't save temporary links for livestreams
              lastEpisodeUrl: null,
            );
        return;
      }

      if (dur < 30000) return;

      final double progress = (pos / dur) * 100;
      final bool isSeries = _item.contentType == MultimediaContentType.series;
      final historyNotifier = ref.read(watchHistoryProvider.notifier);

      final pId =
          _item.provider ??
          ref.read(activeProviderProvider)?.packageName ??
          'Unknown';
      final itemToSave = _item.copyWith(provider: pId);

      // Identify current episode if series
      final currentEpisode = _resolveCurrentEpisode();

      // Handle Completion / Next Episode Logic
      if (progress >= 95) {
        if (!isSeries) {
          historyNotifier.removeFromHistory(_item.url);
          return;
        } else if (currentEpisode != null) {
          // Find next episode
          final currentIndex = _item.episodes!.indexOf(currentEpisode);
          if (currentIndex != -1 && currentIndex < _item.episodes!.length - 1) {
            final nextEpisode = _item.episodes![currentIndex + 1];
            // Save NEXT episode as current progress (reset to 0)
            historyNotifier.saveProgress(
              itemToSave,
              0,
              0,
              lastStreamUrl: null,
              lastEpisodeUrl: nextEpisode.url,
              season: nextEpisode.season,
              episode: nextEpisode.episode,
              episodeTitle: nextEpisode.name,
            );
            return;
          } else {
            // Last episode of the series completed
            historyNotifier.removeFromHistory(_item.url);
            return;
          }
        }
      }

      // Normal Progress Saving
      if (progress > 5 || isSeries) {
        historyNotifier.saveProgress(
          itemToSave,
          pos,
          dur,
          lastStreamUrl: state.currentStream?.url,
          lastEpisodeUrl: currentEpisode?.url ?? _videoUrl,
          season: currentEpisode?.season,
          episode: currentEpisode?.episode,
          episodeTitle: currentEpisode?.name,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint("History save failed: $e");
    }
  }

  void startTorrentPolling([String? activeStreamUrl]) {
    _torrentPollTimer?.cancel();

    Future<void> poll() async {
      if (_isPolling) return;
      _isPolling = true;
      try {
        final status = await ref
            .read(torrentServiceProvider)
            .getCurrentStatus();
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
              if (kDebugMode) {
                debugPrint('PlayerController.startTorrentPolling: $e');
              }
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
      const Duration(seconds: 3),
      (_) => poll(),
    );
  }

  void stopTorrentPolling() {
    _torrentPollTimer?.cancel();
    _torrentPollTimer = null;
    if (state.torrentStatus != null) {
      state = state.copyWith(torrentStatus: null);
    }
  }

  void disposeController() {
    _isDisposed = true;
    _torrentPollTimer?.cancel();
    _torrentPollTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;

    _videoParamsSub?.cancel();
    _errorSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _completedSub?.cancel();
    _rateSub?.cancel();
    _logSub?.cancel();

    saveProgress();
    ref.read(torrentServiceProvider).stop();
    Future.microtask(() {
      state = const PlayerState();
    });
  }

  Future<int> _findFirstWorkingStream(
    List<StreamResult> streams, {
    required int startIndex,
    required int limit,
    int? sourceSessionId,
  }) async {
    if (streams.isEmpty) return 0;

    // Safety check for start index
    final int start = startIndex.clamp(0, streams.length - 1);

    // Extract candidates (circular if needed, though usually not)
    final candidates = <int>[];
    for (int i = 0; i < limit; i++) {
      final idx = (start + i) % streams.length;
      if (!candidates.contains(idx)) candidates.add(idx);
    }

    if (candidates.length <= 1) return start;

    try {
      if (sourceSessionId != null &&
          !_isCurrentSourceSession(sourceSessionId)) {
        return start;
      }
      if (kDebugMode) {
        debugPrint(
          "Starting parallel health check for ${candidates.length} streams",
        );
      }
      // Early-exit parallel check: all candidates start simultaneously, but we
      // resolve as soon as the highest-priority healthy result is available.
      // Example with [0,1,2]: if 0 passes → done immediately (don't wait for 1,2).
      // If 0 fails and 1 passes → done (don't wait for 2).
      // If 0 and 2 have results but 1 is still in flight → wait (1 outranks 2).
      final completer = Completer<int>();
      final results = <int, bool>{}; // idx → isHealthy

      for (final idx in candidates) {
        _isStreamCandidateHealthy(streams[idx])
            .then((isHealthy) {
              if (completer.isCompleted) return;
              if (!isHealthy) {
                _markSourceAttempt(
                  idx,
                  SourceAttemptStatus.failed,
                  isCurrent: false,
                );
              }
              results[idx] = isHealthy;

              // Walk candidates in preference order; stop at the first one
              // whose result we have and which is healthy.
              for (final c in candidates) {
                if (!results.containsKey(c)) {
                  break; // still waiting for a higher-priority one
                }
                if (results[c]!) {
                  if (kDebugMode) {
                    debugPrint("Stream $c is healthy (early-exit)");
                  }
                  completer.complete(c);
                  return;
                }
              }
              // All results are in and all failed → fall back to start
              if (results.length == candidates.length &&
                  !completer.isCompleted) {
                completer.complete(start);
              }
            })
            .catchError((_) {
              if (completer.isCompleted) return;
              results[idx] = false;
              _markSourceAttempt(
                idx,
                SourceAttemptStatus.failed,
                isCurrent: false,
              );
              if (results.length == candidates.length) {
                completer.complete(start);
              }
            });
      }

      final winner = await completer.future;
      if (sourceSessionId != null &&
          !_isCurrentSourceSession(sourceSessionId)) {
        return start;
      }
      return winner;
    } catch (e) {
      if (kDebugMode) debugPrint("Parallel check failed: $e");
    }

    return start; // Fallback to initial
  }

  Future<List<StreamResult>> _sortedByQuality(
    List<StreamResult> streams,
    PlayerSettings settings,
  ) async {
    final onWifi = await isOnWifi();
    final preference = onWifi ? settings.wifiQuality : settings.mobileQuality;
    return sortStreamsByQuality(streams, preference);
  }

  String _getProviderDisplayName(String providerName) {
    try {
      final manager = ref.read(extensionManagerProvider.notifier);
      final p = manager.getAllProviders().firstWhere(
        (p) => p.packageName == providerName || p.name == providerName,
      );
      if (p.isDebug) return "${p.name} [DEBUG]";
      return p.name;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerController._getProviderDisplayName: $e');
      }
    }
    return providerName;
  }

  Future<String?> _resolveStreamUrl(StreamResult stream) async {
    if (stream.url.startsWith("magnet:") ||
        stream.url.endsWith(".torrent") ||
        (stream.url.startsWith("/") && stream.source.contains("Torrent"))) {
      state = state.copyWith(streamSubtitle: "Initializing Torrent Engine...");
      final torrentUrl = await ref
          .read(torrentServiceProvider)
          .getStreamUrl(stream.url);
      if (torrentUrl != null) return torrentUrl;
      return null;
    }

    return AppUtils.normalizeUrl(stream.url);
  }

  /// Applies per-playback MPV properties (headers, cookies, DRM).
  Future<void> _applyPlaybackProperties(
    Map<String, String> headers,
    StreamResult stream, {
    required bool useVideoView,
  }) async {
    // Debug: log what DRM fields the stream has so failures are traceable.
    if (kDebugMode) {
      debugPrint(
        '[DRM] stream drmKid=${stream.drmKid} '
        'drmKey=${stream.drmKey} '
        'licenseUrl=${stream.licenseUrl}',
      );
    }

    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;

      final lowerHeaders = headers.map((k, v) => MapEntry(k.toLowerCase(), v));

      // Propagate ALL provided headers to MPV (Critical for cookies/auth)
      if (lowerHeaders.isNotEmpty) {
        final List<String> headerFields = [];
        lowerHeaders.forEach((key, value) {
          // FFmpeg/libavformat "headers" option standard is CRLF terminated strings.
          // Comma-separated list is also accepted by MPV but CRLF is more robust.
          headerFields.add('$key: $value');
        });

        if (headerFields.isNotEmpty) {
          // Join with \r\n and ensure it ends with \r\n
          final fields = '${headerFields.join('\r\n')}\r\n';
          if (kDebugMode) {
            debugPrint('Player: Setting http-header-fields: $fields');
          }
          await native.setProperty('http-header-fields', fields);
        }
      }

      // Also set dedicated properties for better compatibility
      if (lowerHeaders.containsKey('user-agent')) {
        await native.setProperty('user-agent', lowerHeaders['user-agent']!);
      }
      if (lowerHeaders.containsKey('referer')) {
        await native.setProperty('referrer', lowerHeaders['referer']!);
      }

      // 0. Hardware decoding preference
      // Use auto-safe on Windows: 'auto' enables D3D11VA which can crash during
      // DASH manifest negotiation before codec parameters are fully known.
      final settings = ref.read(playerSettingsProvider).asData?.value;
      if (settings?.hardwareDecoding ?? true) {
        await native.setProperty(
          'hwdec',
          Platform.isWindows ? 'auto-safe' : 'auto',
        );
      } else {
        await native.setProperty('hwdec', 'no');
      }

      // 1. Performance tuning & Anti-Looping
      await native.setProperty('cache', 'yes');

      // Accumulates demuxer-lavf-o options; applied as one combined call below
      // to prevent later additions (e.g. DRM key) from silently overwriting
      // earlier ones (e.g. live reconnect seg_max_retry).
      final demuxerLavfOpts = <String>[];

      final isLivePattern =
          _isLiveStream(stream.url) ||
          _item.contentType == MultimediaContentType.livestream;
      if (kDebugMode) {
        debugPrint(
          'Stream Type (isLivePattern): $isLivePattern, URL: ${stream.url}',
        );
      }
      if (isLivePattern) {
        // Live TV: small buffer to absorb network jitter, not the large VOD buffer
        await native.setProperty('demuxer-readahead-secs', '8');
        await native.setProperty('cache-secs', '8');
        await native.setProperty('cache', 'yes');
        await native.setProperty('cache-pause-initial', 'yes');
        await native.setProperty('cache-pause-wait', '2');

        // Network
        await native.setProperty('network-timeout', '30');
        await native.setProperty('tls-verify', 'no');

        // Reconnect
        await native.setProperty(
          'stream-lavf-o',
          'reconnect_on_network_error=1,reconnect_delay_max=5,reconnect_on_eof=1,reconnect_streamed=1',
        );

        // HLS/DASH segment retry — collected for combined application below.
        demuxerLavfOpts.add('seg_max_retry=5');

        // Playback
        await native.setProperty('framedrop', 'decoder');
        await native.setProperty('hr-seek-framedrop', 'yes');
        await native.setProperty('hwdec', 'auto-safe');

        // H.264 resilience: wait for clean keyframe after reconnect
        await native.setProperty('vd-lavc-skiploopfilter', 'nonkey');
        await native.setProperty('vd-lavc-skipframe', 'nonref');

        if (kDebugMode && _logSub == null) {
          _logSub = _player.stream.log.listen((log) {
            debugPrint('[MPV] ${log.level}: ${log.text}');
          });
        }
      } else {
        final settings = ref.read(playerSettingsProvider).asData?.value;
        final readahead = settings?.readaheadSeconds ?? 180;
        await native.setProperty('demuxer-readahead-secs', '$readahead');
        await native.setProperty('cache-secs', '$readahead');
        await native.setProperty('cache', 'yes');
      }

      // Adaptive demuxer cache based on device profile.
      // DASH streams on desktop are capped lower to prevent OOM from aggressive
      // segment pre-fetch combined with high-bitrate representations.
      final profile = ref.read(deviceProfileProvider).asData?.value;
      final isDashStream = _isDashStreamUrl(stream.url);
      String cacheSize = "512MiB"; // Default
      if (profile != null) {
        if (profile.isTv) {
          cacheSize = "128MiB"; // Less RAM on TVs
        } else if (profile.isDesktopOS || profile.isTablet) {
          cacheSize = isDashStream ? "256MiB" : "1GiB";
        }
      }

      await native.setProperty('demuxer-max-bytes', cacheSize);
      // Allow seeking back without re-fetching — proportional to device RAM
      final backCacheSize = profile?.isTv == true
          ? '64MiB'
          : (profile?.isDesktopOS == true || profile?.isTablet == true)
          ? '256MiB'
          : '128MiB';
      await native.setProperty('demuxer-max-back-bytes', backCacheSize);

      // 2. Resolve ClearKey Hex Keys
      String? keyHex = stream.drmKey;

      if (keyHex == null && stream.licenseUrl != null) {
        final extractedKeys = await _extractKeysFromLicenseUrl(
          stream.licenseUrl!,
          headers: stream.headers,
        );
        if (extractedKeys != null) {
          keyHex = extractedKeys['key'];
        }
      }

      if (keyHex != null) {
        // FFmpeg's DASH demuxer natively expects cenc_decryption_key.
        // It's usually the 32-character hex KEY.
        if (kDebugMode) {
          debugPrint(
            '[DRM] Injecting cenc_decryption_key via demuxer-lavf-o: $keyHex',
          );
        }

        if (!useVideoView) {
          // Collected into demuxerLavfOpts and applied below to prevent
          // overwriting live reconnect options (seg_max_retry) set earlier.
          demuxerLavfOpts.add('cenc_decryption_key=$keyHex');
        } else {
          // If using VideoView on Android, we'd pass DRM keys to the native side here.
        }
      }

      // 3. Apply all demuxer-lavf-o options in a single combined call.
      //    Multiple setProperty('demuxer-lavf-o', ...) calls overwrite each
      //    other; joining here ensures live and DRM settings coexist.
      if (demuxerLavfOpts.isNotEmpty) {
        await native.setProperty('demuxer-lavf-o', demuxerLavfOpts.join(','));
      }

      try {
        final tempDir = await getTemporaryDirectory();
        // Use p.join to produce a platform-correct path; on Windows the mixed
        // forward/back-slash path produced by string concatenation can confuse
        // libmpv's internal path parser.
        final cookieFile = File(p.join(tempDir.path, 'mpv_cookies.txt'));
        if (!await cookieFile.exists()) {
          await cookieFile.create();
        }
        await native.setProperty('cookies-file', cookieFile.path);
        // Note: 'cookies-file-access' is not a valid MPV property and is omitted.
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to set cookies-file: $e');
      }
    }
  }

  /// Fetches a ClearKey license from [licenseUrl] and returns the FIRST
  /// kid and key found as a map: {'kid': '...', 'key': '...'} in hex format.
  /// If the response is not parseable, returns null.
  Future<Map<String, String>?> _extractKeysFromLicenseUrl(
    String licenseUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('[DRM] Fetching ClearKey license from $licenseUrl');
      }
      final response = await http.get(Uri.parse(licenseUrl), headers: headers);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('[DRM] License server returned ${response.statusCode}');
        }
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final keys = body['keys'] as List<dynamic>?;
      if (keys == null || keys.isEmpty) {
        if (kDebugMode) debugPrint('[DRM] No keys array in license response');
        return null;
      }

      // MPV's libdash only supports a single kid:key pair reliably via Laurl redirect.
      for (final entry in keys) {
        final kid = entry['kid'] as String?;
        final k = entry['k'] as String?;
        if (kid == null || k == null) continue;

        // Base64url → hex conversion.
        final kidHex = _base64UrlToHex(kid);
        final keyHex = _base64UrlToHex(k);
        if (kidHex != null && keyHex != null) {
          return {'kid': kidHex, 'key': keyHex};
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[DRM] Error fetching/parsing license: $e');
      return null;
    }
  }

  /// Converts a Base64url-encoded string to a lowercase hex string.
  String? _base64UrlToHex(String base64url) {
    try {
      // Add padding if needed.
      String padded = base64url;
      final rem = padded.length % 4;
      if (rem == 2) padded += '==';
      if (rem == 3) padded += '=';
      final bytes = base64Url.decode(padded);
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DRM] base64url decode failed for "$base64url": $e');
      }
      return null;
    }
  }

  bool _isLiveStream(String url) {
    if (url.isEmpty) return false;

    // Items explicitly marked as livestream in provider metadata
    if (_item.contentType == MultimediaContentType.livestream) return true;

    final lower = url.toLowerCase();

    // Torrents and local files are definitely VOD
    if (lower.startsWith('magnet:') ||
        lower.endsWith('.torrent') ||
        lower.startsWith('/')) {
      return false;
    }

    // Live protocols
    if (lower.startsWith('rtmp://') ||
        lower.startsWith('rtsp://') ||
        lower.startsWith('mms://') ||
        lower.startsWith('udp://') ||
        lower.startsWith('rtp://')) {
      return true;
    }

    // IPTV specific path/query patterns
    if (lower.contains('/live/') ||
        lower.contains('/iptv/') ||
        lower.contains('stream.m3u8') ||
        lower.contains('chunklist')) {
      return true;
    }

    // Xtream Codes API patterns
    if (lower.contains('type=m3u8') || lower.contains('output=m3u8')) {
      return true;
    }

    // Default to VOD for bandwidth protection
    return false;
  }

  Future<void> _safeSeekTo(int position) async {
    if (position <= 0) return;

    // ExoPlayer path: seek directly; no media_kit stream to wait on.
    if (state.useExoPlayer && _videoViewController != null) {
      try {
        _videoViewController!.seekTo(position);
      } catch (e) {
        if (kDebugMode) debugPrint("ExoPlayer seek failed: $e");
      }
      return;
    }

    // media_kit path: wait for duration to be known before seeking.
    try {
      var duration = _player.state.duration;
      if (duration == Duration.zero) {
        duration = await _player.stream.duration
            .firstWhere((d) => d != Duration.zero)
            .timeout(const Duration(seconds: 8));
      }

      final maxMs = duration.inMilliseconds;
      if (maxMs <= 0) return;

      final targetMs = position.clamp(0, maxMs);
      await _player.seek(Duration(milliseconds: targetMs));
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint("Timeout waiting for duration: $e");
      }

      // Best-effort fallback: some streams can seek before duration is reported.
      try {
        await _player.seek(Duration(milliseconds: position));
      } catch (seekError) {
        if (kDebugMode) {
          debugPrint("Fallback seek failed: $seekError");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Seek failed: $e");
      }
    }
  }

  Future<void> _flushPendingResumeSeek() async {
    final pos = _pendingResumeSeekPosition;
    if (pos == null || pos <= 0 || _isApplyingPendingResumeSeek) return;

    _isApplyingPendingResumeSeek = true;
    try {
      await _safeSeekTo(pos);
      _pendingResumeSeekPosition = null;
    } finally {
      _isApplyingPendingResumeSeek = false;
    }
  }

  Future<void> setPlaybackSpeed(double rate) async {
    final appliedRate = rate.clamp(0.5, state.maxPlaybackSpeed);

    if (state.useExoPlayer && _videoViewController != null) {
      _videoViewController!.setSpeed(appliedRate);
      state = state.copyWith(playbackSpeed: appliedRate);
      return;
    }

    await _player.setRate(appliedRate);
    state = state.copyWith(playbackSpeed: appliedRate);
  }

  Future<void> setSubtitleDelay(double seconds) async {
    if (!state.supportsSubtitleDelay) return;

    final native = _player.platform;
    if (native is NativePlayer) {
      await native.setProperty('sub-delay', seconds.toString());
      state = state.copyWith(subtitleDelay: seconds);
    }
  }

  Future<void> applySubtitleSettings() async {
    if (_isDisposed || !state.supportsSubtitleStyling) return;

    final native = _player.platform;
    if (native is NativePlayer) {
      final settings =
          ref.read(playerSettingsProvider).asData?.value ??
          const PlayerSettings();

      // MPV sub properties
      await native.setProperty(
        'sub-font-size',
        settings.subtitleSize.toString(),
      );
      await native.setProperty(
        'sub-pos',
        settings.subtitlePosition.round().toString(),
      );

      // Colors are in MPV hex format (e.g. #RRGGBB or #AARRGGBB)
      String colorToMpvHex(int color, [double opacity = 1.0]) {
        final alpha = (opacity * 255).toInt().toRadixString(16).padLeft(2, '0');
        final rgb = color.toRadixString(16).padLeft(8, '0').substring(2);
        return '#$alpha$rgb';
      }

      await native.setProperty(
        'sub-color',
        colorToMpvHex(settings.subtitleColor),
      );
      if (settings.subtitleBackgroundColor != 0x00000000) {
        await native.setProperty(
          'sub-back-color',
          colorToMpvHex(
            settings.subtitleBackgroundColor,
            settings.subtitleBackgroundOpacity,
          ),
        );
      } else {
        await native.setProperty('sub-back-color', '#00000000');
      }
    }
  }

  Future<double> _getSystemVolumeLevel() async {
    try {
      return ((await FlutterVolumeController.getVolume()) ?? 0.5).clamp(
        0.0,
        1.0,
      );
    } catch (_) {
      return 0.5;
    }
  }

  double _getEngineVolumeLevel() {
    if (state.useExoPlayer && _videoViewController != null) {
      return _videoViewController!.volume.value.clamp(0.0, 1.0);
    }

    return (_player.state.volume / 100).clamp(0.0, 2.0);
  }

  Future<void> _setSystemVolumeLevel(double value) async {
    try {
      await FlutterVolumeController.setVolume(value.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> _setEngineVolumeLevel(double value) async {
    if (state.useExoPlayer && _videoViewController != null) {
      _videoViewController!.setVolume(value.clamp(0.0, 1.0));
      return;
    }

    await _player.setVolume((value * 100).clamp(0.0, 200.0));
  }

  Future<double> getVolumeLevel() async {
    final systemVolume = await _getSystemVolumeLevel();
    final engineVolume = _getEngineVolumeLevel();
    final value = engineVolume > 1.0 ? engineVolume : systemVolume;
    if (value > 0) {
      _lastNonZeroVolumeLevel = value;
    }
    return value;
  }

  Future<double> setVolumeLevel(double value) async {
    final target = value.clamp(0.0, state.supportsVolumeBoost ? 2.0 : 1.0);

    if (target > 0) {
      _lastNonZeroVolumeLevel = target;
    }

    if (target > 1.0 && state.supportsVolumeBoost) {
      await _setSystemVolumeLevel(1.0);
      await _setEngineVolumeLevel(target);
      return target;
    }

    await _setEngineVolumeLevel(1.0);
    await _setSystemVolumeLevel(target);
    return target;
  }

  Future<double> changeVolume(double step) async {
    final current = await getVolumeLevel();
    final boostStep = state.supportsVolumeBoost && current >= 1.0
        ? step * 2
        : step;
    return setVolumeLevel(current + boostStep);
  }

  Future<double> toggleMute() async {
    final current = await getVolumeLevel();
    if (current > 0) {
      return setVolumeLevel(0.0);
    }

    return setVolumeLevel(_lastNonZeroVolumeLevel);
  }

  Future<void> loadExternalSubtitleFile({String? filePath}) async {
    if (state.useExoPlayer && !state.supportsExternalSubtitleLoading) {
      return;
    }

    String? path = filePath;
    if (path == null) {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
      );
      if (result != null && result.files.single.path != null) {
        path = result.files.single.path!;
      }
    }

    if (path != null) {
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      final baseName = p.basenameWithoutExtension(path).trim();
      final label = baseName.isNotEmpty ? baseName : "External ($ext)";
      final newSub = SubtitleFile(url: path, label: label, lang: "und");

      state = state.copyWith(
        externalSubtitles: _effectiveExternalSubtitles(
          state.currentStream?.subtitles,
        ),
      );

      if (!_userAddedExternalSubtitles.any((sub) => sub.url == newSub.url)) {
        _userAddedExternalSubtitles.add(newSub);
        state = state.copyWith(
          externalSubtitles: _effectiveExternalSubtitles(
            state.currentStream?.subtitles,
          ),
        );
      }

      if (state.useExoPlayer && state.currentStream != null) {
        _pendingVideoViewSubtitleIdsBeforeReload = _videoViewController
            ?.mediaInfo
            .value
            ?.subtitleTracks
            .keys
            .toSet();
        _selectNewestVideoViewSubtitleAfterReload =
            !(Platform.isMacOS || Platform.isIOS);

        await changeStream(state.currentStream!, resetPosition: false);

        if (!state.useExoPlayer) {
          _pendingVideoViewSubtitleIdsBeforeReload = null;
          _selectNewestVideoViewSubtitleAfterReload = false;
          await selectSubtitleTrack('external:${newSub.url}');
        }
        return;
      }

      await selectSubtitleTrack('external:${newSub.url}');
    }
  }
}

final playerControllerProvider =
    NotifierProvider.autoDispose<PlayerController, PlayerState>(
      PlayerController.new,
    );

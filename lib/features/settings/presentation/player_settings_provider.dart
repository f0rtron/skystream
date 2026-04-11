import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/settings_repository.dart';
import '../../player/domain/entity/subtitle_model.dart';
import '../../player/data/subtitle_providers.dart';
import '../../../core/network/dio_client_provider.dart';

enum PlayerGesture { brightness, volume, none }

/// Preferred playback quality tier. Plugins don't guarantee a specific
/// quality but sources are sorted so the preferred tier is tried first.
enum QualityPreference {
  any,   // no preference — keep original order
  q360,  // 360p
  q480,  // 480p / SD
  q720,  // 720p / HD
  q1080, // 1080p / FHD
  q4k,   // 4K / UHD / 2160p
}

class PlayerSettings {
  final PlayerGesture leftGesture;
  final PlayerGesture rightGesture;
  final bool doubleTapEnabled;
  final bool swipeSeekEnabled;
  final int seekDuration;
  final String defaultResizeMode;
  final double subtitleSize;
  final int subtitleColor;
  final int subtitleBackgroundColor;
  final double subtitleBackgroundOpacity;
  final bool hardwareDecoding;
  final String?
  preferredPlayer; // null = internal, 'vlc' / 'mpv' etc. = external
  final int readaheadSeconds;
  final double subtitlePosition;
  /// Quality to prefer when on Wi-Fi. Default: 4K (best available).
  final QualityPreference wifiQuality;
  /// Quality to prefer when on mobile data. Default: 1080p.
  final QualityPreference mobileQuality;

  // Subtitle Accounts
  final String osUsername;
  final String osPassword;
  final String osApiKey;
  final String subdlEmail;
  final String subdlPassword;
  final String subdlApiKey;
  final String subsourceApiKey;

  const PlayerSettings({
    this.leftGesture = PlayerGesture.brightness,
    this.rightGesture = PlayerGesture.volume,
    this.doubleTapEnabled = true,
    this.swipeSeekEnabled = true,
    this.seekDuration = 10,
    this.defaultResizeMode = 'Fit',
    this.subtitleSize = 22.0,
    this.subtitleColor = 0xFFFFFFFF, // White
    this.subtitleBackgroundColor = 0x00000000, // Transparent
    this.subtitleBackgroundOpacity = 0.5, // Default opacity (50%)
    this.hardwareDecoding = true,
    this.preferredPlayer,
    this.readaheadSeconds = 180,
    this.subtitlePosition = 100.0,
    this.wifiQuality = QualityPreference.q4k,
    this.mobileQuality = QualityPreference.q1080,
    this.osUsername = '',
    this.osPassword = '',
    this.osApiKey = '',
    this.subdlEmail = '',
    this.subdlPassword = '',
    this.subdlApiKey = '',
    this.subsourceApiKey = '',
  });

  PlayerSettings copyWith({
    PlayerGesture? leftGesture,
    PlayerGesture? rightGesture,
    bool? doubleTapEnabled,
    bool? swipeSeekEnabled,
    int? seekDuration,
    String? defaultResizeMode,
    double? subtitleSize,
    int? subtitleColor,
    int? subtitleBackgroundColor,
    double? subtitleBackgroundOpacity,
    bool? hardwareDecoding,
    String? preferredPlayer,
    bool clearPreferredPlayer = false,
    int? readaheadSeconds,
    double? subtitlePosition,
    QualityPreference? wifiQuality,
    QualityPreference? mobileQuality,
    String? osUsername,
    String? osPassword,
    String? osApiKey,
    String? subdlEmail,
    String? subdlPassword,
    String? subdlApiKey,
    String? subsourceApiKey,
  }) {
    return PlayerSettings(
      leftGesture: leftGesture ?? this.leftGesture,
      rightGesture: rightGesture ?? this.rightGesture,
      doubleTapEnabled: doubleTapEnabled ?? this.doubleTapEnabled,
      swipeSeekEnabled: swipeSeekEnabled ?? this.swipeSeekEnabled,
      seekDuration: seekDuration ?? this.seekDuration,
      defaultResizeMode: defaultResizeMode ?? this.defaultResizeMode,
      subtitleSize: subtitleSize ?? this.subtitleSize,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      subtitleBackgroundColor:
          subtitleBackgroundColor ?? this.subtitleBackgroundColor,
      subtitleBackgroundOpacity:
          subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
      hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
      preferredPlayer: clearPreferredPlayer
          ? null
          : (preferredPlayer ?? this.preferredPlayer),
      readaheadSeconds: readaheadSeconds ?? this.readaheadSeconds,
      subtitlePosition: subtitlePosition ?? this.subtitlePosition,
      wifiQuality: wifiQuality ?? this.wifiQuality,
      mobileQuality: mobileQuality ?? this.mobileQuality,
      osUsername: osUsername ?? this.osUsername,
      osPassword: osPassword ?? this.osPassword,
      osApiKey: osApiKey ?? this.osApiKey,
      subdlEmail: subdlEmail ?? this.subdlEmail,
      subdlPassword: subdlPassword ?? this.subdlPassword,
      subdlApiKey: subdlApiKey ?? this.subdlApiKey,
      subsourceApiKey: subsourceApiKey ?? this.subsourceApiKey,
    );
  }
}

class PlayerSettingsNotifier extends AsyncNotifier<PlayerSettings> {
  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  @override
  Future<PlayerSettings> build() async {
    final storage = _repository;
    final l =
        storage.getPlayerSetting<String>(
          'player_gesture_left',
          defaultValue: 'brightness',
        ) ??
        'brightness';
    final r =
        storage.getPlayerSetting<String>(
          'player_gesture_right',
          defaultValue: 'volume',
        ) ??
        'volume';
    final dt =
        storage.getPlayerSetting<bool>(
          'player_double_tap',
          defaultValue: true,
        ) ??
        true;
    final dur =
        storage.getPlayerSetting<int>(
          'player_seek_duration',
          defaultValue: 10,
        ) ??
        10;
    final resize =
        storage.getPlayerSetting<String>(
          'player_default_resize',
          defaultValue: 'Fit',
        ) ??
        'Fit';
    final subSize =
        (storage.getPlayerSetting('player_sub_size') as num?)?.toDouble() ??
        22.0;
    final subColor =
        storage.getPlayerSetting<int>(
          'player_sub_color',
          defaultValue: 0xFFFFFFFF,
        ) ??
        0xFFFFFFFF;
    final subBg =
        (storage.getPlayerSetting('player_sub_bg') as num?)?.toInt() ??
        0x00000000;
    final subBgOpacity = 
        (storage.getPlayerSetting('player_sub_bg_opacity') as num?)?.toDouble() ??
        0.5;
    final prefPlayer = storage.getPlayerSetting<String>('player_preferred');
    final swipeSeek =
        storage.getPlayerSetting<bool>(
          'player_swipe_seek',
          defaultValue: true,
        ) ??
        true;
    final hwDec =
        storage.getPlayerSetting<bool>('player_hw_dec', defaultValue: true) ??
        true;
    final rSecons =
        storage.getPlayerSetting<int>('player_readahead', defaultValue: 180) ??
        180;
    final subPos =
         (storage.getPlayerSetting('player_sub_pos') as num?)?.toDouble() ??
         100.0;
    final wifiQ = _parseQuality(
      storage.getPlayerSetting<String>('player_wifi_quality'),
      QualityPreference.q4k,
    );
    final mobileQ = _parseQuality(
      storage.getPlayerSetting<String>('player_mobile_quality'),
      QualityPreference.q1080,
    );
    final osUser = storage.getPlayerSetting<String>('player_os_user') ?? '';
    final osPass = storage.getPlayerSetting<String>('player_os_pass') ?? '';
    final osKey = storage.getPlayerSetting<String>('player_os_key') ?? '';
    final dlEmail = storage.getPlayerSetting<String>('player_subdl_email') ?? '';
    final dlPass = storage.getPlayerSetting<String>('player_subdl_pass') ?? '';
    final dlKey = storage.getPlayerSetting<String>('player_subdl_key') ?? '';
    final ssKey = storage.getPlayerSetting<String>('player_ss_key') ?? '';

    return PlayerSettings(
      leftGesture: _parse(l),
      rightGesture: _parse(r),
      doubleTapEnabled: dt,
      swipeSeekEnabled: swipeSeek,
      seekDuration: dur,
      defaultResizeMode: resize,
      subtitleSize: subSize,
      subtitleColor: subColor,
      subtitleBackgroundColor: subBg,
      subtitleBackgroundOpacity: subBgOpacity,
      hardwareDecoding: hwDec,
      preferredPlayer: prefPlayer,
      readaheadSeconds: rSecons,
      subtitlePosition: subPos,
      wifiQuality: wifiQ,
      mobileQuality: mobileQ,
      osUsername: osUser,
      osPassword: osPass,
      osApiKey: osKey,
      subdlEmail: dlEmail,
      subdlPassword: dlPass,
      subdlApiKey: dlKey,
      subsourceApiKey: ssKey,
    );
  }

  Future<void> setLeftGesture(PlayerGesture g) async {
    await _repository.setPlayerSetting('player_gesture_left', g.name);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(leftGesture: g));
  }

  Future<void> setRightGesture(PlayerGesture g) async {
    await _repository.setPlayerSetting('player_gesture_right', g.name);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(rightGesture: g));
  }

  Future<void> setDoubleTapEnabled(bool val) async {
    await _repository.setPlayerSetting('player_double_tap', val);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(doubleTapEnabled: val));
  }

  Future<void> setSwipeSeekEnabled(bool val) async {
    await _repository.setPlayerSetting('player_swipe_seek', val);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(swipeSeekEnabled: val));
  }

  Future<void> setSeekDuration(int seconds) async {
    await _repository.setPlayerSetting('player_seek_duration', seconds);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(seekDuration: seconds));
  }

  Future<void> setDefaultResizeMode(String mode) async {
    await _repository.setPlayerSetting('player_default_resize', mode);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(defaultResizeMode: mode));
  }

  Future<void> setHardwareDecoding(bool val) async {
    await _repository.setPlayerSetting('player_hw_dec', val);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(hardwareDecoding: val));
  }

  Future<void> setSubtitleSettings(double size, int color, int bg, [double? opacity]) async {
    await _repository.setPlayerSetting('player_sub_size', size);
    await _repository.setPlayerSetting('player_sub_color', color);
    await _repository.setPlayerSetting('player_sub_bg', bg);
    if (opacity != null) {
      await _repository.setPlayerSetting('player_sub_bg_opacity', opacity);
    }
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(
      current.copyWith(
        subtitleSize: size,
        subtitleColor: color,
        subtitleBackgroundColor: bg,
        subtitleBackgroundOpacity: opacity ?? current.subtitleBackgroundOpacity,
      ),
    );
  }

  /// Set the preferred external player (null = internal player)
  Future<void> setPreferredPlayer(String? playerId) async {
    if (playerId == null) {
      await _repository.setPlayerSetting('player_preferred', null);
      final current = state.asData?.value ?? const PlayerSettings();
      state = AsyncData(current.copyWith(clearPreferredPlayer: true));
    } else {
      await _repository.setPlayerSetting('player_preferred', playerId);
      final current = state.asData?.value ?? const PlayerSettings();
      state = AsyncData(current.copyWith(preferredPlayer: playerId));
    }
  }

  Future<void> setReadaheadSeconds(int seconds) async {
    await _repository.setPlayerSetting('player_readahead', seconds);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(readaheadSeconds: seconds));
  }

  Future<void> setSubtitlePosition(double pos) async {
    await _repository.setPlayerSetting('player_sub_pos', pos);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(subtitlePosition: pos));
  }

  Future<void> setSubtitleBackgroundOpacity(double val) async {
    await _repository.setPlayerSetting('player_sub_bg_opacity', val);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(subtitleBackgroundOpacity: val));
  }

  Future<void> resetSubtitleSettings() async {
    final current = state.asData?.value ?? const PlayerSettings();
    final newState = current.copyWith(
      subtitleSize: 22.0,
      subtitleColor: 0xFFFFFFFF,
      subtitleBackgroundColor: 0x00000000,
      subtitleBackgroundOpacity: 0.5,
      subtitlePosition: 100.0,
    );

    await _repository.setPlayerSetting('player_sub_size', 22.0);
    await _repository.setPlayerSetting('player_sub_color', 0xFFFFFFFF);
    await _repository.setPlayerSetting('player_sub_bg', 0x00000000);
    await _repository.setPlayerSetting('player_sub_bg_opacity', 0.5);
    await _repository.setPlayerSetting('player_sub_pos', 100.0);

    state = AsyncData(newState);
  }

  Future<void> setWifiQuality(QualityPreference q) async {
    await _repository.setPlayerSetting('player_wifi_quality', q.name);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(wifiQuality: q));
  }

  Future<void> setMobileQuality(QualityPreference q) async {
    await _repository.setPlayerSetting('player_mobile_quality', q.name);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(mobileQuality: q));
  }

  Future<void> setOpenSubtitlesCredentials(String user, String pass, [String? key]) async {
    await _repository.setPlayerSetting('player_os_user', user);
    await _repository.setPlayerSetting('player_os_pass', pass);
    if (key != null) {
      await _repository.setPlayerSetting('player_os_key', key);
    }
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(osUsername: user, osPassword: pass, osApiKey: key));
  }

  Future<void> setSubDlAuth({required String apiKey, String? email, String? pass}) async {
    await _repository.setPlayerSetting('player_subdl_key', apiKey);
    if (email != null) await _repository.setPlayerSetting('player_subdl_email', email);
    if (pass != null) await _repository.setPlayerSetting('player_subdl_pass', pass);
    
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(
      subdlApiKey: apiKey,
      subdlEmail: email ?? current.subdlEmail, 
      subdlPassword: pass ?? current.subdlPassword,
    ));
  }

  Future<void> setSubDlApiKey(String key) async {
    await _repository.setPlayerSetting('player_subdl_key', key);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(subdlApiKey: key));
  }

  Future<void> setSubSourceApiKey(String key) async {
    await _repository.setPlayerSetting('player_ss_key', key);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(current.copyWith(subsourceApiKey: key));
  }

  /// Verifies OpenSubtitles credentials without saving.
  Future<bool> verifyOpenSubtitles(String user, String pass, [String? key]) async {
    final dio = ref.read(dioClientProvider);
    final provider = OpenSubtitlesProvider(dio, username: user, password: pass, apiKey: key);
    return await provider.verifyCredentials();
  }

  /// Verifies SubDL credentials via login and returns the fetched key or error.
  Future<({String? key, String? error})> verifySubDl(String email, String pass) async {
    final dio = ref.read(dioClientProvider);
    final provider = SubDLProvider(dio, email: email, password: pass);
    return await provider.login(email, pass);
  }

  /// Verifies SubDL API Key without saving.
  Future<bool> verifySubDlKey(String key) async {
    final dio = ref.read(dioClientProvider);
    final provider = SubDLProvider(dio, apiKey: key);
    return await provider.verifyKey();
  }

  /// Verifies SubSource API Key without saving.
  Future<bool> verifySubSource(String key) async {
    final dio = ref.read(dioClientProvider);
    final provider = SubSourceProvider(dio, apiKey: key);
    return await provider.verifyKey();
  }

  PlayerGesture _parse(String s) {
    return PlayerGesture.values.firstWhere(
      (e) => e.name == s,
      orElse: () => PlayerGesture.none,
    );
  }

  QualityPreference _parseQuality(String? s, QualityPreference fallback) {
    if (s == null) return fallback;
    return QualityPreference.values.firstWhere(
      (e) => e.name == s,
      orElse: () => fallback,
    );
  }
}

final playerSettingsProvider =
    AsyncNotifierProvider<PlayerSettingsNotifier, PlayerSettings>(
      PlayerSettingsNotifier.new,
    );

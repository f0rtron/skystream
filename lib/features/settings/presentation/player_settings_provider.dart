import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/settings_repository.dart';

enum PlayerGesture { brightness, volume, none }

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
  final String?
      preferredPlayer; // null = internal, 'vlc' / 'mpv' etc. = external

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
    this.preferredPlayer,
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
    String? preferredPlayer,
    bool clearPreferredPlayer = false,
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
      preferredPlayer: clearPreferredPlayer
          ? null
          : (preferredPlayer ?? this.preferredPlayer),
    );
  }
}

class PlayerSettingsNotifier extends AsyncNotifier<PlayerSettings> {
  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  @override
  Future<PlayerSettings> build() async {
    final storage = _repository;
    final l = storage.getPlayerSetting<String>('player_gesture_left', defaultValue: 'brightness') ?? 'brightness';
    final r = storage.getPlayerSetting<String>('player_gesture_right', defaultValue: 'volume') ?? 'volume';
    final dt = storage.getPlayerSetting<bool>('player_double_tap', defaultValue: true) ?? true;
    final dur = storage.getPlayerSetting<int>('player_seek_duration', defaultValue: 10) ?? 10;
    final resize = storage.getPlayerSetting<String>('player_default_resize', defaultValue: 'Fit') ?? 'Fit';
    final subSize = storage.getPlayerSetting<double>('player_sub_size', defaultValue: 22.0) ?? 22.0;
    final subColor = storage.getPlayerSetting<int>('player_sub_color', defaultValue: 0xFFFFFFFF) ?? 0xFFFFFFFF;
    final subBg = storage.getPlayerSetting<int>('player_sub_bg', defaultValue: 0x00000000) ?? 0x00000000;
    final prefPlayer = storage.getPlayerSetting<String>('player_preferred');
    final swipeSeek = storage.getPlayerSetting<bool>('player_swipe_seek', defaultValue: true) ?? true;

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
      preferredPlayer: prefPlayer,
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

  Future<void> setSubtitleSettings(double size, int color, int bg) async {
    await _repository.setPlayerSetting('player_sub_size', size);
    await _repository.setPlayerSetting('player_sub_color', color);
    await _repository.setPlayerSetting('player_sub_bg', bg);
    final current = state.asData?.value ?? const PlayerSettings();
    state = AsyncData(
      current.copyWith(
        subtitleSize: size,
        subtitleColor: color,
        subtitleBackgroundColor: bg,
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

  PlayerGesture _parse(String s) {
    return PlayerGesture.values.firstWhere(
      (e) => e.name == s,
      orElse: () => PlayerGesture.none,
    );
  }
}

final playerSettingsProvider =
    AsyncNotifierProvider<PlayerSettingsNotifier, PlayerSettings>(
      PlayerSettingsNotifier.new,
    );

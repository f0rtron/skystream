import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/settings_repository.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  late SettingsRepository _repository;

  @override
  ThemeMode build() {
    _repository = ref.watch(settingsRepositoryProvider);
    final saved = _repository.getThemeMode();
    return _getThemeMode(saved);
  }

  void setThemeMode(ThemeMode mode) async {
    state = mode;
    await _repository.saveThemeMode(mode.name);
  }

  ThemeMode _getThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}

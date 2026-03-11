import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_service.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(storageServiceProvider));
});

class SettingsRepository {
  final StorageService _storageService;

  SettingsRepository(this._storageService);

  Future<void> saveThemeMode(String mode) async {
    await _storageService.saveThemeMode(mode);
  }

  String getThemeMode() {
    return _storageService.getThemeMode();
  }

  Future<void> setDevLoadAssets(bool enabled) async {
    await _storageService.setDevLoadAssets(enabled);
  }

  bool getDevLoadAssets() {
    return _storageService.getDevLoadAssets();
  }

  Future<void> setActiveProviderId(String? id) => _storageService.setActiveProviderId(id);

  String? getActiveProviderId() {
    return _storageService.getActiveProviderId();
  }

  Future<void> setLanguage(String lang) async {
    await _storageService.setLanguage(lang);
  }

  String getLanguage() {
    return _storageService.getLanguage();
  }

  Future<void> setPlayerSetting(String key, dynamic value) async {
    await _storageService.setPlayerSetting(key, value);
  }

  T? getPlayerSetting<T>(String key, {T? defaultValue}) {
    return _storageService.getPlayerSetting<T>(key, defaultValue: defaultValue);
  }

  Future<void> clearPreferences() async {
    await _storageService.clearPreferences();
  }

  Future<void> deleteAllData() async {
    await _storageService.deleteAllData();
  }
}

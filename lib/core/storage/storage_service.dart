import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:io';
import '../domain/entity/multimedia_item.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService must be initialized');
});

class StorageService {
  late Box _libraryBox;
  late Box _settingsBox;
  late Box _extensionsBox;

  static const String kLibraryBox = 'library_box';
  static const String kSettingsBox = 'settings_box';
  static const String kExtensionsBox = 'extension_data_box';

  Future<void> init() async {
    final supportDir = await getApplicationSupportDirectory();
    Hive.init(supportDir.path);

    _libraryBox = await _safeOpenBox(kLibraryBox);
    _settingsBox = await _safeOpenBox(kSettingsBox);
    _extensionsBox = await _safeOpenBox(kExtensionsBox);
    await initHistory();
  }

  Future<Box> _safeOpenBox(String boxName) async {
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      debugPrint(
        "Error opening Hive box '$boxName': $e. Deleting and recreating...",
      );
      // If the box is corrupted or has unknown type IDs, delete it.
      try {
        await Hive.deleteBoxFromDisk(boxName);
      } catch (_) {
        // Ignore delete errors, maybe file doesn't exist or lock issue
      }
      return await Hive.openBox(boxName);
    }
  }

  /// Helper to ensure keys do not exceed Hive's 255 char limit.
  /// Generates a stable hash for long URLs.
  String _getKey(String url) {
    if (url.length <= 250) return url;
    return md5.convert(utf8.encode(url)).toString();
  }

  // --- Library (Favorites) ---

  // We store items as JSON strings or Maps. Key is url.
  Future<void> addToLibrary(MultimediaItem item) async {
    // We assume item.url is unique enough for now
    await _libraryBox.put(_getKey(item.url), {
      'title': item.title,
      'url': item.url,
      'posterUrl': item.posterUrl,
      'bannerUrl': item.bannerUrl,
      'description': item.description,
      'type': item.contentType.name,
      'provider': item.provider,
    });
  }

  Future<void> removeFromLibrary(String url) async {
    await _libraryBox.delete(_getKey(url));
  }

  bool isInLibrary(String url) {
    return _libraryBox.containsKey(_getKey(url));
  }

  List<MultimediaItem> getLibraryItems() {
    final items = <MultimediaItem>[];
    for (var i = 0; i < _libraryBox.length; i++) {
      final key = _libraryBox.keyAt(i);
      final map = Map<String, dynamic>.from(_libraryBox.get(key));
      items.add(
        MultimediaItem(
          title: map['title'] ?? '',
          url: map['url'] ?? '',
          posterUrl: map['posterUrl'] ?? '',
          bannerUrl: map['bannerUrl'],
          description: map['description'],
          contentType: MultimediaItem.parseContentType(map['type'] ?? map['contentType']),
          provider: map['provider'],
        ),
      );
    }
    return items;
  }

  // --- Settings ---

  Future<void> saveThemeMode(String mode) async {
    await _settingsBox.put('theme_mode', mode);
  }

  String getThemeMode() {
    return _settingsBox.get('theme_mode', defaultValue: 'system');
  }

  Future<void> setDevLoadAssets(bool enabled) async {
    await _settingsBox.put('dev_load_assets', enabled);
  }

  bool getDevLoadAssets() {
    return _settingsBox.get('dev_load_assets', defaultValue: false);
  }

  // --- Active Provider ---

  Future<void> setActiveProviderId(String? id) async {
    await _settingsBox.put('active_provider_id', id ?? '__NONE__');
  }

  String? getActiveProviderId() {
    final id = _settingsBox.get('active_provider_id') as String?;
    if (id == null || id == '__NONE__') return null;
    return id;
  }

  // --- Extension Persistence ---

  Future<void> setExtensionData(String key, String? value) async {
    if (value == null) {
      await _extensionsBox.delete(key);
    } else {
      await _extensionsBox.put(key, value);
    }
  }

  String? getExtensionData(String key) {
    return _extensionsBox.get(key) as String?;
  }

  // --- Language ---
  Future<void> setLanguage(String lang) async {
    await _settingsBox.put('language', lang);
  }

  String getLanguage() {
    return _settingsBox.get('language', defaultValue: 'en-US');
  }

  // --- Player Settings ---
  Future<void> setPlayerSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  T? getPlayerSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  // --- Watch History ---

  static const String kHistoryBox = 'history_box';
  late Box _historyBox;

  Future<void> initHistory() async {
    _historyBox = await _safeOpenBox(kHistoryBox);
  }

  Future<void> saveProgress(
    MultimediaItem item,
    int positionMillis,
    int durationMillis, {
    String? lastStreamUrl,
    String? lastEpisodeUrl,
  }) async {
    await _historyBox.put(_getKey(item.url), {
      'title': item.title,
      'url': item.url,
      'posterUrl': item.posterUrl,
      'bannerUrl': item.bannerUrl,
      'description': item.description,
      'contentType': item.contentType.name,
      'provider': item.provider,
      'position': positionMillis,
      'duration': durationMillis,
      'lastStreamUrl': lastStreamUrl,
      'lastEpisodeUrl': lastEpisodeUrl,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> removeFromHistory(String url) async {
    await _historyBox.delete(_getKey(url));
  }

  Future<void> clearAllHistory() async {
    await _historyBox.clear();
  }

  List<Map<String, dynamic>> getWatchHistory() {
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _historyBox.length; i++) {
      final key = _historyBox.keyAt(i);
      final map = Map<String, dynamic>.from(_historyBox.get(key));
      items.add(map);
    }
    // Sort by timestamp descending (newest first)
    items.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );
    return items;
  }

  int getPosition(String url) {
    final key = _getKey(url);
    if (_historyBox.containsKey(key)) {
      final map = _historyBox.get(key);
      return map['position'] ?? 0;
    }
    return 0;
  }

  String? getLastStreamUrl(String url) {
    final key = _getKey(url);
    if (_historyBox.containsKey(key)) {
      final map = _historyBox.get(key);
      return map['lastStreamUrl'] as String?;
    }
    return null;
  }

  String? getLastEpisodeUrl(String url) {
    final key = _getKey(url);
    if (_historyBox.containsKey(key)) {
      final map = _historyBox.get(key);
      return map['lastEpisodeUrl'] as String?;
    }
    return null;
  }

  Future<void> clearPreferences() async {
    try {
      // Clear SharedPreferences (Settings, Repo URLs, etc)
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Delete Hive Boxes (Library, History, Settings, Extensions)
      try {
        if (_libraryBox.isOpen) await _libraryBox.close();
        await Hive.deleteBoxFromDisk(kLibraryBox);
      } catch (e) {
        debugPrint('Error deleting library box: $e');
      }
      try {
        if (_settingsBox.isOpen) await _settingsBox.close();
        await Hive.deleteBoxFromDisk(kSettingsBox);
      } catch (e) {
        debugPrint('Error deleting settings box: $e');
      }
      try {
        if (_historyBox.isOpen) await _historyBox.close();
        await Hive.deleteBoxFromDisk(kHistoryBox);
      } catch (e) {
        debugPrint('Error deleting history box: $e');
      }
      try {
        if (_extensionsBox.isOpen) await _extensionsBox.close();
        await Hive.deleteBoxFromDisk(kExtensionsBox);
      } catch (e) {
        debugPrint('Error deleting extensions box: $e');
      }
    } catch (e) {
      debugPrint('Error clearing preferences: $e');
    }
  }

  Future<void> deleteAllData() async {
    try {
      // Delete Extensions Folder (Application Support)
      final supportDir = await getApplicationSupportDirectory();
      final extDir = Directory('${supportDir.path}/extensions');
      if (await extDir.exists()) {
        await extDir.delete(recursive: true);
      }

      // Clear Preferences (Hive + Prefs)
      await clearPreferences();

      // Clear Cache Manager (Images)
      try {
        await DefaultCacheManager().emptyCache();
      } catch (e) {
        debugPrint("Error clearing cache manager: $e");
      }

      // Clear Temporary Directory
      try {
        final tempDir = await getTemporaryDirectory();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint("Error clearing temp dir: $e");
      }
    } catch (e) {
      debugPrint('Error deleting data: $e');
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entity/multimedia_item.dart';
import 'storage_service.dart';

class HistoryItem {
  final MultimediaItem item;
  final int position;
  final int duration;
  final String? lastStreamUrl;
  final String? lastEpisodeUrl;
  final int timestamp;

  HistoryItem({
    required this.item,
    required this.position,
    required this.duration,
    this.lastStreamUrl,
    this.lastEpisodeUrl,
    required this.timestamp,
  });

  double get progress => duration > 0 ? position / duration : 0;

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      item: MultimediaItem(
        title: map['title'] ?? '',
        url: map['url'] ?? '',
        posterUrl: map['posterUrl'] ?? '',
        bannerUrl: map['bannerUrl'],
        description: map['description'],
        contentType: MultimediaItem.parseContentType(map['type'] ?? map['contentType'] ?? 'movie'),
        provider: map['provider'],
      ),
      position: map['position'] ?? 0,
      duration: map['duration'] ?? 0,
      lastStreamUrl: map['lastStreamUrl'],
      lastEpisodeUrl: map['lastEpisodeUrl'],
      timestamp: map['timestamp'] ?? 0,
    );
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(storageServiceProvider));
});

class HistoryRepository {
  final StorageService _storageService;

  HistoryRepository(this._storageService);

  Future<void> saveProgress(
    MultimediaItem item,
    int position,
    int duration, {
    String? lastStreamUrl,
    String? lastEpisodeUrl,
  }) async {
    await _storageService.saveProgress(
      item,
      position,
      duration,
      lastStreamUrl: lastStreamUrl,
      lastEpisodeUrl: lastEpisodeUrl,
    );
  }

  Future<void> removeFromHistory(String url) async {
    await _storageService.removeFromHistory(url);
  }

  Future<void> clearAllHistory() async {
    await _storageService.clearAllHistory();
  }

  List<HistoryItem> getWatchHistory() {
    final rawItems = _storageService.getWatchHistory();
    return rawItems.map((map) => HistoryItem.fromMap(map)).toList();
  }

  int getPosition(String url) {
    return _storageService.getPosition(url);
  }

  String? getLastStreamUrl(String url) {
    return _storageService.getLastStreamUrl(url);
  }

  String? getLastEpisodeUrl(String url) {
    return _storageService.getLastEpisodeUrl(url);
  }
}

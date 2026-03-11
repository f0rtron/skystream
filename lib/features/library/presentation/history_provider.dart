import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/storage/history_repository.dart';
import '../../../../core/domain/entity/multimedia_item.dart';

export '../../../../core/storage/history_repository.dart' show HistoryItem;

final watchHistoryProvider = NotifierProvider<WatchHistoryNotifier, List<HistoryItem>>(() {
  return WatchHistoryNotifier();
});

class WatchHistoryNotifier extends Notifier<List<HistoryItem>> {
  late HistoryRepository _repository;

  @override
  List<HistoryItem> build() {
    _repository = ref.watch(historyRepositoryProvider);
    return _repository.getWatchHistory();
  }

  void refresh() {
    state = _repository.getWatchHistory();
  }

  Future<void> clearAllHistory() async {
    await _repository.clearAllHistory();
    refresh();
  }

  Future<void> removeFromHistory(String url) async {
    await _repository.removeFromHistory(url);
    refresh();
  }

  Future<void> saveProgress(
    MultimediaItem item,
    int position,
    int duration, {
    String? lastStreamUrl,
    String? lastEpisodeUrl,
  }) async {
    await _repository.saveProgress(
      item,
      position,
      duration,
      lastStreamUrl: lastStreamUrl,
      lastEpisodeUrl: lastEpisodeUrl,
    );
    refresh();
  }
}

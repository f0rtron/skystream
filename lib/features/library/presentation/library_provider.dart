import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/library_repository.dart';

class LibraryNotifier extends Notifier<List<MultimediaItem>> {
  late LibraryRepository _repository;

  @override
  List<MultimediaItem> build() {
    _repository = ref.watch(libraryRepositoryProvider);
    return _repository.getLibraryItems();
  }

  void refresh() {
    state = _repository.getLibraryItems();
  }

  Future<void> addItem(MultimediaItem item) async {
    await _repository.addToLibrary(item);
    state = _repository.getLibraryItems(); // Refresh state
  }

  Future<void> removeItem(String url) async {
    await _repository.removeFromLibrary(url);
    state = _repository.getLibraryItems(); // Refresh state
  }

  bool isBookmarked(String url) {
    return _repository.isInLibrary(url);
  }

  Future<void> clearAll() async {
    // _repository doesn't have clear all library yet, we should loop or add it to repo if needed
    // or just assume it is done via settingsdeleteAllData.
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<MultimediaItem>>(LibraryNotifier.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/entity/multimedia_item.dart';
import 'storage_service.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(storageServiceProvider));
});

class LibraryRepository {
  final StorageService _storageService;

  LibraryRepository(this._storageService);

  Future<void> addToLibrary(MultimediaItem item) async {
    await _storageService.addToLibrary(item);
  }

  Future<void> removeFromLibrary(String url) async {
    await _storageService.removeFromLibrary(url);
  }

  bool isInLibrary(String url) {
    return _storageService.isInLibrary(url);
  }

  List<MultimediaItem> getLibraryItems() {
    return _storageService.getLibraryItems();
  }
}

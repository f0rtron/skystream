import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'services/plugin_storage_service.dart';
import 'services/repository_service.dart';

import '../network/dio_client_provider.dart';
import '../services/torrent_service.dart';

part 'providers.g.dart';

// Repository Service Provider
@Riverpod(keepAlive: true)
RepositoryService repositoryService(Ref ref) {
  return RepositoryService(ref.watch(dioClientProvider));
}

// Plugin Storage Service Provider
@Riverpod(keepAlive: true)
PluginStorageService pluginStorageService(Ref ref) {
  return PluginStorageService();
}

// Torrent Service Provider
@Riverpod(keepAlive: true)
TorrentService torrentService(Ref ref) {
  return TorrentService();
}

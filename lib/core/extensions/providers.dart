import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/plugin_storage_service.dart';
import 'services/repository_service.dart';

import '../network/dio_client_provider.dart';
import '../services/torrent_service.dart';

// Repository Service Provider
final repositoryServiceProvider = Provider<RepositoryService>((ref) {
  return RepositoryService(ref.watch(dioClientProvider));
});

// Plugin Storage Service Provider
final pluginStorageServiceProvider = Provider<PluginStorageService>((ref) {
  return PluginStorageService();
});

// Torrent Service Provider
final torrentServiceProvider = Provider<TorrentService>((ref) {
  return TorrentService();
});

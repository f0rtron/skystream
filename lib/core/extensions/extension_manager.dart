import 'package:flutter/material.dart'; // Contains ChangeNotifier
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'base_provider.dart';

import 'dart:io';
import 'engine/js_engine.dart';
import 'models/extension_plugin.dart';
import 'providers/js_based_provider.dart';
import 'services/plugin_storage_service.dart';
import 'providers.dart';
import '../storage/settings_repository.dart';

final extensionManagerProvider =
    NotifierProvider<ExtensionManager, List<SkyStreamProvider>>(
      ExtensionManager.new,
    );

class ExtensionManager extends Notifier<List<SkyStreamProvider>> {
  JsEngineService? _engine;
  PluginStorageService? _storageService;

  @override
  List<SkyStreamProvider> build() {
    _engine = ref.watch(jsEngineProvider);
    _storageService = ref.watch(pluginStorageServiceProvider);
    return [];
  }

  /// Called by the extensions feature when installed plugins change.
  /// Keeps core independent of the feature; sync is triggered from app/feature layer.
  Future<void> syncFromPlugins(List<ExtensionPlugin> installed) async {
    await _syncPlugins(installed);
  }

  Future<void> _syncPlugins(List<ExtensionPlugin> installed) async {
    debugPrint("ExtensionManager: Syncing ${installed.length} plugin");
    if (_engine == null || _storageService == null) return;

    final activePackageName = ref.read(settingsRepositoryProvider).getActiveProviderId();

    // Sort plugins: Active first
    final sortedPlugins = List<ExtensionPlugin>.from(installed);
    if (activePackageName != null) {
      sortedPlugins.sort((a, b) {
        if (a.packageName == activePackageName) return -1;
        if (b.packageName == activePackageName) return 1;
        return 0;
      });
    }

    // Batch load background providers to avoid UI stutter
    final parallelLoads = <Future<SkyStreamProvider?>>[];

    for (final plugin in sortedPlugins) {
      final existingList = state.where((p) => p.packageName == plugin.packageName);
      final existing = existingList.isNotEmpty ? existingList.first : null;

      bool needsLoad = existing == null;
      if (existing != null) {
        final newVersion = plugin.version.toString();
        final oldVersion = existing.version;
        if (newVersion != oldVersion) {
          // Version changed, reload
          state = state.where((p) => p.packageName != plugin.packageName).toList();
          needsLoad = true;
        }
      }

      if (needsLoad) {
        if (plugin.packageName == activePackageName) {
          // Priority load for active provider
          await _loadPlugin(plugin, addToState: true);
        } else {
          // Background providers loaded in parallel
          parallelLoads.add(_loadPlugin(plugin, addToState: false));
        }
      }
    }

    if (parallelLoads.isNotEmpty) {
      final results = await Future.wait(parallelLoads);
      final loaded = results.whereType<SkyStreamProvider>().toList();
      if (loaded.isNotEmpty) {
        state = [...state, ...loaded];
      }
    }

    // Unload Removed Plugins
    final installedPackageNames = installed.map((e) => e.packageName).toSet();

    final providersToRemove = <SkyStreamProvider>[];

    for (final provider in state) {
      if (!installedPackageNames.contains(provider.packageName)) {
        providersToRemove.add(provider);
      }
    }

    if (providersToRemove.isNotEmpty) {
      debugPrint(
        "ExtensionManager: Unloading ${providersToRemove.length} providers",
      );
      final newState = List<SkyStreamProvider>.from(state);
      for (final p in providersToRemove) {
        debugPrint("ExtensionManager: Removing ${p.packageName} (${p.name})");
        newState.remove(p);
        // Also cleanup JS resources if needed
        if (p is JsBasedProvider) {
          // _engine?.unload(p.namespace);
        }
      }
      state = newState;
    }
  }

  Future<void> updateCustomBaseUrl(String packageName, String? url) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setCustomBaseUrl(packageName, url);

    // Reload the provider to apply changes
    final currentProvider = getProvider(packageName);
    if (currentProvider != null) {
      debugPrint("ExtensionManager: Custom base URL updated for $packageName. Reload recommended.");
    }
  }

  Future<SkyStreamProvider?> _loadPlugin(
    ExtensionPlugin plugin, {
    bool addToState = true,
  }) async {
    if (_engine == null || _storageService == null) return null;
    try {
      final path = await _storageService!.getPluginJsPath(plugin);
      debugPrint("ExtensionManager: Loading JS from: $path");

      if (!path.startsWith('assets/')) {
        if (!await File(path).exists()) {
          debugPrint("ExtensionManager: JS File does NOT exist at $path");
          return null;
        }
      }

      // Derive namespace from ID to ensure uniqueness
      final namespace = plugin.packageName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      final settings = ref.read(settingsRepositoryProvider);
      final customBaseUrl = settings.getCustomBaseUrl(plugin.packageName);

      final provider = JsBasedProvider(
        _engine!,
        path,
        packageName: plugin.packageName,
        namespace: namespace,
        manifest: plugin.manifest,
        customBaseUrl: customBaseUrl,
      );

      debugPrint("ExtensionManager: Waiting for init of $namespace");
      await provider.waitForInit;
      debugPrint("ExtensionManager: Init complete for ${plugin.packageName}");

      if (addToState) {
        _addProvider(provider);
      }
      return provider;
    } catch (e) {
      debugPrint("Failed to load plugin ${plugin.name}: $e");
      return null;
    }
  }

  void _addProvider(SkyStreamProvider provider) {
    // Deduplicate by Package Name
    if (!state.any((p) => p.packageName == provider.packageName)) {
      debugPrint(
        "ExtensionManager: Adding provider to state: ${provider.name} (${provider.packageName})",
      );
      state = [...state, provider];
    } else {
      debugPrint("ExtensionManager: Provider ${provider.packageName} already in state.");
    }
  }

  List<SkyStreamProvider> getAllProviders() => state;

  SkyStreamProvider? getProvider(String packageName) {
    try {
      return state.firstWhere((p) => p.packageName == packageName);
    } catch (_) {
      return null;
    }
  }
}

// Provider to track if we are still resolving the initial active provider
final providerResolutionLoadingProvider =
    NotifierProvider<ProviderResolutionLoadingNotifier, bool>(
      ProviderResolutionLoadingNotifier.new,
    );

class ProviderResolutionLoadingNotifier extends Notifier<bool> {
  @override
  bool build() {
    return true;
  }

  void set(bool value) => state = value;
}

// Global definition of activeProviderStateProvider
final activeProviderStateProvider =
    NotifierProvider<ActiveProviderNotifier, SkyStreamProvider?>(
      ActiveProviderNotifier.new,
    );

// Currently selected provider
class ActiveProviderNotifier extends Notifier<SkyStreamProvider?> {
  String? _targetProviderId;
  bool _initialLoadDone = false;

  @override
  SkyStreamProvider? build() {
    ref.listen(extensionManagerProvider, (previous, next) {
      // On first listen invocation, perform the initial load from storage
      if (!_initialLoadDone) {
        _initialLoadDone = true;
        _loadFromStorage(next);
        return;
      }

      if (_targetProviderId != null && state == null) {
        final p = ref
            .read(extensionManagerProvider.notifier)
            .getProvider(_targetProviderId!);
        if (p != null) {
          state = p;
          _targetProviderId = null;
          ref.read(providerResolutionLoadingProvider.notifier).set(false);
        }
      } else if (state != null) {
        final currentPackageName = state!.packageName;
        final found = next.where((p) => p.packageName == currentPackageName);

        if (found.isEmpty) {
          debugPrint(
            "ActiveProviderNotifier: Active provider removed, waiting for reload...",
          );
          state = null;
          _targetProviderId = currentPackageName;
          ref.read(providerResolutionLoadingProvider.notifier).set(true);
        } else {
          final match = found.first;
          if (match != state) {
            state = match;
          }
        }
      }
    });

    return null;
  }

  void _loadFromStorage(List<SkyStreamProvider> currentProviders) {
    final storage = ref.read(settingsRepositoryProvider);
    final id = storage.getActiveProviderId();

    if (id == null) {
      state = null;
      _targetProviderId = null;
      ref.read(providerResolutionLoadingProvider.notifier).set(false);
    } else {
      _targetProviderId = id;
      final p = ref.read(extensionManagerProvider.notifier).getProvider(id);
      if (p != null) {
        state = p;
        _targetProviderId = null;
        ref.read(providerResolutionLoadingProvider.notifier).set(false);
      }
    }
  }

  Future<void> set(SkyStreamProvider? provider) async {
    state = provider;
    _targetProviderId = null;
    ref.read(providerResolutionLoadingProvider.notifier).set(false);

    final storage = ref.read(settingsRepositoryProvider);
    await storage.setActiveProviderId(provider?.packageName);
  }
}

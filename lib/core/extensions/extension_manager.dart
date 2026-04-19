import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'base_provider.dart';

import 'dart:io';
import 'engine/js_engine.dart';
import 'models/extension_plugin.dart';
import 'providers/js_based_provider.dart';
import 'services/plugin_storage_service.dart';
import 'providers.dart';
import '../storage/settings_repository.dart';
import '../storage/extension_repository.dart';
import '../logger/app_logger.dart';

part 'extension_manager.g.dart';

@Riverpod(keepAlive: true)
class ExtensionManager extends _$ExtensionManager {
  JsEngineService? _engine;
  PluginStorageService? _storageService;
  Future<void>? _syncLock;

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
    if (_engine == null || _storageService == null) return;

    // Use a lock to ensure only one sync happens at a time.
    final prevLock = _syncLock ?? Future.value();
    final completer = Completer<void>();
    _syncLock = completer.future;

    try {
      await prevLock;

    final activePackageName = ref
        .read(settingsRepositoryProvider)
        .getActiveProviderId();

    // Sort plugins: Active first
    final sortedPlugins = List<ExtensionPlugin>.from(installed);
    if (activePackageName != null) {
      sortedPlugins.sort((a, b) {
        if (a.packageName == activePackageName) return -1;
        if (b.packageName == activePackageName) return 1;
        return 0;
      });
    }

    // 1. Priority Load: Active Provider (if needs loading)
    if (activePackageName != null) {
      try {
        final activePlugin = sortedPlugins.firstWhere(
          (p) => p.packageName == activePackageName,
        );
        final existing = _hasLoadedProviders(activePackageName);
        if (!existing) {
          final loaded = await _loadPlugin(activePlugin);
          for (final p in loaded) {
            _addProvider(p);
          }
        }
      } catch (_) {
        // Active plugin not found in installed list, ignore
      }
    }

    // 2. Process background providers in manageable batches (Pool of 3)
    const batchSize = 3;

    for (int i = 0; i < sortedPlugins.length; i += batchSize) {
      final batch = sortedPlugins.skip(i).take(batchSize);
      final batchLoads = <Future<List<SkyStreamProvider>>>[];

      for (final plugin in batch) {
        final alreadyLoaded = _hasLoadedProviders(plugin.packageName);

        bool needsLoad = !alreadyLoaded;
        if (alreadyLoaded) {
          final existing = _firstLoadedProvider(plugin.packageName);
          if (existing != null && plugin.version.toString() != existing.version) {
            _removeProvidersForPackage(plugin.packageName);
            needsLoad = true;
          }
        }

        if (needsLoad && plugin.packageName != activePackageName) {
          batchLoads.add(_loadPlugin(plugin));
        }
      }

      if (batchLoads.isNotEmpty) {
        final results = await Future.wait(batchLoads);
        final loadedInBatch = results.expand((l) => l).toList();
        if (loadedInBatch.isNotEmpty) {
          state = [...state, ...loadedInBatch];
        }
      }
    }

    // Unload Removed Plugins
    final installedPackageNames = installed.map((e) => e.packageName).toSet();

    final providersToRemove = <SkyStreamProvider>[];

    for (final provider in state) {
      if (!_belongsToInstalled(provider.packageName, installedPackageNames)) {
        providersToRemove.add(provider);
      }
    }

    if (providersToRemove.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          "ExtensionManager: Unloading ${providersToRemove.length} providers",
        );
      }
      final newState = List<SkyStreamProvider>.from(state);
      for (final p in providersToRemove) {
        if (kDebugMode) {
          debugPrint("ExtensionManager: Removing ${p.packageName} (${p.name})");
        }
        newState.remove(p);
        if (p is JsBasedProvider) {
          // _engine?.unload(p.namespace);
        }
      }
      state = newState;
    }

    // Signal that plugin sync is complete
    ref.read(pluginSyncCompleteProvider.notifier).set(true);
    } finally {
      if (!completer.isCompleted) completer.complete();
      if (_syncLock == completer.future) _syncLock = null;
    }
  }

  /// Reloads a plugin, picking up preference changes (domain switch, provider toggles).
  Future<void> reloadPlugin(ExtensionPlugin plugin) async {
    if (_engine == null || _storageService == null) return;
    _removeProvidersForPackage(plugin.packageName);
    final loaded = await _loadPlugin(plugin);
    for (final p in loaded) {
      _addProvider(p);
    }
  }

  /// Trigger garbage collection in the underlying JS engine
  void runGC() {
    _engine?.runGC();
  }

  Future<void> updateCustomBaseUrl(String packageName, String? url) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setCustomBaseUrl(packageName, url);
  }

  /// Returns true if the user has enabled this sub-provider (default: true).
  bool _isSubProviderEnabled(String packageName, String providerId) {
    final storage = ref.read(extensionRepositoryProvider);
    return storage.getExtensionData('$packageName:_provider_enabled_$providerId') != 'false';
  }

  /// Loads a plugin and returns all resulting provider instances.
  /// For plugins with a `providers` array, fans out one instance per enabled sub-provider.
  /// For regular plugins, returns a single-element list.
  Future<List<SkyStreamProvider>> _loadPlugin(ExtensionPlugin plugin) async {
    if (_engine == null || _storageService == null) return [];
    try {
      final path = await _storageService!.getPluginJsPath(plugin);
      if (kDebugMode) debugPrint("ExtensionManager: Loading JS from: $path");
      talker.debug("ExtensionManager: Loading JS from: $path");

      if (!path.startsWith('assets/')) {
        if (!await File(path).exists()) {
          if (kDebugMode) debugPrint("ExtensionManager: JS File does NOT exist at $path");
          return [];
        }
      }

      final baseNamespace = plugin.packageName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      // Fan-out: one JS file → multiple provider instances
      if (plugin.providers != null && plugin.providers!.isNotEmpty) {
        final results = <SkyStreamProvider>[];
        for (final sub in plugin.providers!) {
          if (!_isSubProviderEnabled(plugin.packageName, sub.id)) continue;
          final subId = sub.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final provider = JsBasedProvider(
            _engine!,
            path,
            packageName: '${plugin.packageName}::${sub.id}',
            jsPackageName: plugin.packageName,
            namespace: '${baseNamespace}__$subId',
            forcedName: sub.name,
            manifest: plugin.manifest,
            customBaseUrl: sub.baseUrl,
          );
          await provider.waitForInit;
          results.add(provider);
        }
        if (kDebugMode) debugPrint("ExtensionManager: Loaded ${results.length} sub-providers for ${plugin.packageName}");
        return results;
      }

      // Single provider
      final settings = ref.read(settingsRepositoryProvider);
      final customBaseUrl = settings.getCustomBaseUrl(plugin.packageName);
      final provider = JsBasedProvider(
        _engine!,
        path,
        packageName: plugin.packageName,
        namespace: baseNamespace,
        manifest: plugin.manifest,
        customBaseUrl: customBaseUrl,
      );
      await provider.waitForInit;
      if (kDebugMode) {
        debugPrint("ExtensionManager: Init complete for ${plugin.packageName}");
        talker.debug("ExtensionManager: Init complete for ${plugin.packageName}");
      }
      return [provider];
    } catch (e) {
      if (kDebugMode) debugPrint("Failed to load plugin ${plugin.name}: $e");
      talker.error("Failed to load plugin ${plugin.name}: $e");
      return [];
    }
  }

  // ── Helper methods ────────────────────────────────────────────────────────

  /// True if any loaded provider belongs to [packageName] (direct or sub-provider).
  bool _hasLoadedProviders(String packageName) {
    return state.any((p) =>
        p.packageName == packageName ||
        p.packageName.startsWith('$packageName::'));
  }

  /// First loaded provider belonging to [packageName], or null.
  SkyStreamProvider? _firstLoadedProvider(String packageName) {
    try {
      return state.firstWhere((p) =>
          p.packageName == packageName ||
          p.packageName.startsWith('$packageName::'));
    } catch (_) {
      return null;
    }
  }

  /// Removes all loaded providers belonging to [packageName] from state.
  void _removeProvidersForPackage(String packageName) {
    state = state
        .where((p) =>
            p.packageName != packageName &&
            !p.packageName.startsWith('$packageName::'))
        .toList();
  }

  /// True if [providerPackageName] belongs to one of the installed packages.
  /// Handles synthetic sub-provider names (`parentPkg::subId`).
  bool _belongsToInstalled(String providerPackageName, Set<String> installedPackageNames) {
    if (installedPackageNames.contains(providerPackageName)) return true;
    final sep = providerPackageName.lastIndexOf('::');
    if (sep > 0) {
      return installedPackageNames.contains(providerPackageName.substring(0, sep));
    }
    return false;
  }

  void _addProvider(SkyStreamProvider provider) {
    // Deduplicate by Package Name
    if (!state.any((p) => p.packageName == provider.packageName)) {
      if (kDebugMode) {
        debugPrint(
          "ExtensionManager: Adding provider to state: ${provider.name} (${provider.packageName})",
        );
      }
      state = [...state, provider];
    } else {
      if (kDebugMode) {
        debugPrint(
          "ExtensionManager: Provider ${provider.packageName} already in state.",
        );
      }
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
@Riverpod(keepAlive: true)
class ProviderResolutionLoading extends _$ProviderResolutionLoading {
  @override
  bool build() {
    return true;
  }

  void set(bool value) => state = value;
}

// Tracks whether the initial plugin sync has completed at least once
@Riverpod(keepAlive: true)
class PluginSyncComplete extends _$PluginSyncComplete {
  @override
  bool build() {
    return false;
  }

  void set(bool value) => state = value;
}

// Global definition of activeProviderState
@Riverpod(keepAlive: true)
class ActiveProvider extends _$ActiveProvider {
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
        } else if (next.isNotEmpty || ref.read(pluginSyncCompleteProvider)) {
          // Plugins have loaded (or sync completed with zero plugins)
          // but the target provider is missing (removed/uninstalled).
          // Clear the stale setting.
          _targetProviderId = null;
          ref.read(settingsRepositoryProvider).setActiveProviderId(null);
          ref.read(providerResolutionLoadingProvider.notifier).set(false);
        }
      } else if (state != null) {
        final currentPackageName = state!.packageName;
        final found = next.where((p) => p.packageName == currentPackageName);

        if (found.isEmpty) {
          state = null;
          _targetProviderId = currentPackageName;
          ref.read(providerResolutionLoadingProvider.notifier).set(false);
        } else {
          final match = found.first;
          if (match != state) {
            state = match;
          }
        }
      }
    });

    // ref.listen only fires on changes, not the initial value. If extensionManager
    // already has a value when we subscribe (e.g. empty list on fresh install),
    // the listener never fires. Defer initial load to after build - we cannot
    // modify other providers (providerResolutionLoadingProvider) during build.
    Future.microtask(() {
      _initialLoadDone = true;
      _loadFromStorage(ref.read(extensionManagerProvider));
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
      } else {
        // Provider not yet loaded. Keep _targetProviderId set so the listener can pick it up
        // when extensionManagerProvider updates later.
        state = null;
        // Do NOT set _targetProviderId = null here!
        // We also DO NOT set loading = false yet, as we are waiting for this specific ID.
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

import 'package:flutter/material.dart'; // Contains ChangeNotifier
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_provider.dart';

// Import providers (Eventually this will be dynamic)
import 'dart:io';
import 'engine/js_engine.dart';
import 'models/extension_plugin.dart';
import 'providers/js_based_provider.dart';
import 'services/plugin_storage_service.dart';
import 'providers.dart'; // storage and repo providers
import '../../features/extensions/providers/extensions_controller.dart';

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

    // Listen to changes in installed plugin
    ref.listen(extensionsControllerProvider, (previous, next) {
      if (previous?.installedPlugins != next.installedPlugins) {
        _syncPlugins(next.installedPlugins);
      }
    });

    // Initial load
    final extensionsState = ref.read(extensionsControllerProvider);
    Future.microtask(() => _syncPlugins(extensionsState.installedPlugins));

    // Do NOT reset state to empty here if we are rebuilding due to engine/storage change
    // But since _engine/_storageService ARE watched, build() WILL run again if they change.
    // However, usually they don't change.
    // If they do change, we probably DO want to reload everything.
    return [];
  }

  Future<void> _syncPlugins(List<ExtensionPlugin> installed) async {
    debugPrint("ExtensionManager: Syncing ${installed.length} plugin");
    if (_engine == null || _storageService == null) return;

    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString('active_provider_id');

    // Sort plugins: Active first
    final sortedPlugins = List<ExtensionPlugin>.from(installed);
    if (activeId != null) {
      sortedPlugins.sort((a, b) {
        if (a.id == activeId) return -1;
        if (b.id == activeId) return 1;
        return 0;
      });
    }

    // Batch load background providers to avoid UI stutter
    final newProviders = <SkyStreamProvider>[];

    for (final plugin in sortedPlugins) {
      final existingList = state.where((p) => p.id == plugin.id);
      final existing = existingList.isNotEmpty ? existingList.first : null;

      bool needsLoad = existing == null;
      if (existing != null) {
        final newVersion = plugin.version.toString();
        final oldVersion = existing.version;
        if (newVersion != oldVersion) {
          // Version changed, reload
          state = state.where((p) => p.id != plugin.id).toList();
          needsLoad = true;
        }
      }

      if (needsLoad) {
        if (plugin.id == activeId) {
          await _loadPlugin(plugin, addToState: true);
        } else {
          // Stagger loading slightly to not freeze UI
          await Future.delayed(const Duration(milliseconds: 10));
          final p = await _loadPlugin(plugin, addToState: false);
          if (p != null) newProviders.add(p);
        }
      }
    }

    if (newProviders.isNotEmpty) {
      state = [...state, ...newProviders];
    }

    // Unload Removed Plugins
    final installedIds = installed.map((e) => e.id).toSet();

    final providersToRemove = <SkyStreamProvider>[];

    for (final provider in state) {
      if (!installedIds.contains(provider.id)) {
        providersToRemove.add(provider);
      }
    }

    if (providersToRemove.isNotEmpty) {
      debugPrint(
        "ExtensionManager: Unloading ${providersToRemove.length} providers",
      );
      final newState = List<SkyStreamProvider>.from(state);
      for (final p in providersToRemove) {
        debugPrint("ExtensionManager: Removing ${p.id} (${p.name})");
        newState.remove(p);
        // Also cleanup JS resources if needed
        if (p is JsBasedProvider) {
          // _engine?.unload(p.namespace);
        }
      }
      state = newState;
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

      // Derive namespace from ID to ensure uniqueness (internalName might be missing/default)
      final namespace = plugin.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      final provider = JsBasedProvider(
        _engine!,
        path,
        id: plugin.id, // Pass ID
        namespace: namespace,
      );

      debugPrint("ExtensionManager: Waiting for init of $namespace");
      await provider.waitForInit;
      debugPrint("ExtensionManager: Init complete for ${plugin.id}");

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
    // Deduplicate by ID
    if (!state.any((p) => p.id == provider.id)) {
      debugPrint(
        "ExtensionManager: Adding provider to state: ${provider.name} (${provider.id})",
      );
      state = [...state, provider];
    } else {
      debugPrint("ExtensionManager: Provider ${provider.id} already in state.");
    }
  }

  List<SkyStreamProvider> getAllProviders() => state;

  SkyStreamProvider? getProvider(String id) {
    try {
      return state.firstWhere((p) => p.id == id);
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
  String? _targetProviderName;

  @override
  SkyStreamProvider? build() {
    // Only trigger load once
    Future.microtask(() => _load());

    // Listen for new plugin being loaded
    ref.listen(extensionManagerProvider, (previous, next) {
      if (_targetProviderName != null && state == null) {
        // Try to resolve again
        final p = ref
            .read(extensionManagerProvider.notifier)
            .getProvider(_targetProviderName!);
        if (p != null) {
          state = p;
          _targetProviderName = null; // Found it!
          ref.read(providerResolutionLoadingProvider.notifier).set(false);
        }
      } else if (state != null) {
        // Check if current active provider has been removed or replaced
        final currentId = state!.id;
        final found = next.where((p) => p.id == currentId);

        if (found.isEmpty) {
          // Removed (likely reloading) -> Enter waiting state
          debugPrint(
            "ActiveProviderNotifier: Active provider removed, waiting for reload...",
          );
          state = null;
          _targetProviderName = currentId;
          ref.read(providerResolutionLoadingProvider.notifier).set(true);
        } else {
          // Present -> Check for instance update
          final match = found.first;
          if (match != state) {
            debugPrint(
              "ActiveProviderNotifier: Refreshed active provider instance. Match: ${match.hashCode}, State: ${state.hashCode}",
            );
            state = match;
          } else {
            debugPrint(
              "ActiveProviderNotifier: Match found (${match.hashCode}) == State (${state.hashCode}), NO UPDATE.",
            );
          }
        }
      }
    });

    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('active_provider_id');

    // Fallback migration: Check old key if new key missing (User might still have 'active_provider')
    // But name is unreliable. We'll start fresh or try name lookup once?
    // Let's just strictly use ID. If not found, user re-selects (safer than picking wrong one).

    if (id == '__NONE__' || id == null) {
      state = null;
      _targetProviderName = null;
      ref.read(providerResolutionLoadingProvider.notifier).set(false);
    } else {
      _targetProviderName = id;
      final p = ref.read(extensionManagerProvider.notifier).getProvider(id);
      if (p != null) {
        state = p;
        _targetProviderName = null;
        ref.read(providerResolutionLoadingProvider.notifier).set(false);
      } else {
        // Provider with ID not found (yet?)
        // It might load later via _syncPlugins listener
      }
    }
  }

  Future<void> set(SkyStreamProvider? provider) async {
    state = provider;
    _targetProviderName = null;
    ref.read(providerResolutionLoadingProvider.notifier).set(false);

    final prefs = await SharedPreferences.getInstance();
    if (provider != null) {
      await prefs.setString('active_provider_id', provider.id);
    } else {
      await prefs.setString('active_provider_id', '__NONE__');
    }
  }
}

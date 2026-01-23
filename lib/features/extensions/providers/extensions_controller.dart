import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/extensions/models/extension_plugin.dart';
import '../../../../core/extensions/models/extension_repository.dart';
import '../../../../core/extensions/providers.dart';
import '../../../../core/extensions/services/repository_service.dart';
import '../../../../core/extensions/services/plugin_storage_service.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/extensions/utils/js_manifest_parser.dart';

// State for the Extensions Screen
class ExtensionsState {
  final bool isLoading;
  final List<ExtensionPlugin> installedPlugins;
  final List<ExtensionRepository> repositories;
  final Map<String, List<ExtensionPlugin>> availablePlugins; // Key: Repo URL
  final Map<String, ExtensionPlugin>
  availableUpdates; // Key: PackageID, Value: New Online Plugin
  final String? error;

  ExtensionsState({
    this.isLoading = false,
    this.installedPlugins = const [],
    this.repositories = const [],
    this.availablePlugins = const {},
    this.availableUpdates = const {},
    this.error,
  });

  ExtensionsState copyWith({
    bool? isLoading,
    List<ExtensionPlugin>? installedPlugins,
    List<ExtensionRepository>? repositories,
    Map<String, List<ExtensionPlugin>>? availablePlugins,
    Map<String, ExtensionPlugin>? availableUpdates,
    String? error,
  }) {
    return ExtensionsState(
      isLoading: isLoading ?? this.isLoading,
      installedPlugins: installedPlugins ?? this.installedPlugins,
      repositories: repositories ?? this.repositories,
      availablePlugins: availablePlugins ?? this.availablePlugins,
      availableUpdates: availableUpdates ?? this.availableUpdates,
      error: error,
    );
  }
}

class ExtensionsController extends Notifier<ExtensionsState> {
  late RepositoryService _repositoryService;
  late PluginStorageService _storageService;

  @override
  ExtensionsState build() {
    _repositoryService = ref.watch(repositoryServiceProvider);
    _storageService = ref.watch(pluginStorageServiceProvider);

    // Initial load
    Future.microtask(() => _init());

    return ExtensionsState();
  }

  Future<void> _init() async {
    await loadInstalledPlugins();
    await _loadPersistedRepositories();
  }

  Future<void> _loadPersistedRepositories() async {
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList('extension_repo_urls') ?? [];

    for (final url in urls) {
      // Use visitedUrls empty set for each initial load to ensure isolation
      await addRepository(url);
    }
  }

  Future<void> loadInstalledPlugins() async {
    state = state.copyWith(isLoading: true);
    try {
      final plugins = await _storageService.listInstalledPlugins();

      // Load Asset Plugins if enabled
      if (ref.read(storageServiceProvider).getDevLoadAssets()) {
        final assetPlugins = await _loadAssetPlugins();
        debugPrint(
          "ExtensionsController: Loaded ${assetPlugins.length} asset plugins",
        );
        plugins.addAll(assetPlugins);
      } else {
        debugPrint("ExtensionsController: Asset loading disabled");
      }

      state = state.copyWith(installedPlugins: plugins, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<List<ExtensionPlugin>> _loadAssetPlugins() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();

      final pluginFiles = assets
          .where(
            (key) => key.startsWith('assets/plugins/') && key.endsWith('.js'),
          )
          .toList();

      final plugins = <ExtensionPlugin>[];

      for (final file in pluginFiles) {
        final content = await rootBundle.loadString(file);
        final plugin = _parseJsPlugin(content, file);
        if (plugin != null) {
          plugins.add(plugin);
        }
      }
      return plugins;
    } catch (e) {
      debugPrint("Error loading asset plugins: $e");
      return [];
    }
  }

  ExtensionPlugin? _parseJsPlugin(String content, String filePath) {
    try {
      final jsonMap = JsManifestParser.parse(content);

      if (jsonMap != null) {
        final json = Map<String, dynamic>.from(jsonMap);

        // Ensure ID
        if (json['id'] == null) {
          // Fallback for dev if missing
          json['id'] = "local.asset.${filePath.split('/').last}";
        }

        // Apply .debug suffix for asset plugins to allow coexistence with release versions
        // and for easy identification in UI
        if (filePath.startsWith('assets/')) {
          final originalId = json['id'];
          if (!originalId.toString().endsWith('.debug')) {
            json['id'] = "$originalId.debug";
          }
        }

        // Inject sourceUrl (filePath) so it is picked up by fromJson
        json['url'] = filePath;

        return ExtensionPlugin.fromJson(json, 'LocalAssets');
      }

      return null;
    } catch (e) {
      debugPrint("Error parsing asset plugin $filePath: $e");
      return null;
    }
  }

  Future<int> checkForUpdates() async {
    final updates = <String, ExtensionPlugin>{};
    final onlineMap = <String, ExtensionPlugin>{};

    for (final list in state.availablePlugins.values) {
      for (final plugin in list) {
        onlineMap[plugin.packageId] = plugin;
      }
    }

    for (final installed in state.installedPlugins) {
      final online = onlineMap[installed.packageId];
      if (online != null) {
        if (online.version > installed.version) {
          updates[installed.packageId] = online;
        }
      }
    }

    int installedCount = 0;
    if (updates.isNotEmpty) {
      state = state.copyWith(availableUpdates: updates);

      // Auto-update immediately
      for (final plugin in updates.values) {
        await installPlugin(plugin);
        installedCount++;
      }
    }
    return installedCount;
  }

  Future<void> addRepository(String url, {Set<String>? visitedUrls}) async {
    // Cycle Detection
    visitedUrls ??= {};
    if (visitedUrls.contains(url)) {
      debugPrint("Recursion detected: skipping repeated repo $url");
      return;
    }
    visitedUrls.add(url);

    state = state.copyWith(isLoading: true);
    try {
      final repo = await _repositoryService.fetchRepository(url);
      if (repo != null) {
        // Handle Recursive Repositories (Megarepo)
        if (repo.includedRepos.isNotEmpty) {
          debugPrint(
            "Repo ${repo.name} contains ${repo.includedRepos.length} included repos",
          );
          for (final subRepoUrl in repo.includedRepos) {
            await addRepository(subRepoUrl, visitedUrls: visitedUrls);
          }

          // If the repo is PURELY a container (no plugin of its own),
          // do NOT add it to the list or persist it.
          if (repo.pluginLists.isEmpty) {
            state = state.copyWith(isLoading: false);
            return;
          }
        }

        final currentRepos = List<ExtensionRepository>.from(state.repositories);
        if (!currentRepos.any((element) => element.url == repo.url)) {
          currentRepos.add(repo);

          // Persist URL (Only top-level or unique ones)
          final prefs = await SharedPreferences.getInstance();
          final urls = prefs.getStringList('extension_repo_urls') ?? [];
          if (!urls.contains(url)) {
            urls.add(url);
            await prefs.setStringList('extension_repo_urls', urls);
          }
        }

        final plugins = await _repositoryService.getRepoPlugins(repo);
        final currentAvailable = Map<String, List<ExtensionPlugin>>.from(
          state.availablePlugins,
        );
        currentAvailable[repo.url] = plugins;

        state = state.copyWith(
          repositories: currentRepos,
          availablePlugins: currentAvailable,
          isLoading: false,
        );
      } else {
        // ... (Keep existing error logic, or simplify?)
        // Simplify: don't error out the whole state for one bad sub-repo
        debugPrint("Failed to parse repository at $url");
        if (visitedUrls.length == 1) {
          // Only show error if it's the root call
          state = state.copyWith(
            isLoading: false,
            error: "Failed to parse repository",
          );
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> removeRepository(String url) async {
    try {
      final currentRepos = List<ExtensionRepository>.from(state.repositories);
      final repoToRemove = currentRepos.firstWhere(
        (r) => r.url == url,
        orElse: () => throw Exception("Repo not found"),
      );

      // Capture plugin provided by this repo BEFORE removing it from state
      final repoPluginsToCheck = state.availablePlugins[url] ?? [];

      currentRepos.removeWhere((r) => r.url == url);

      final currentAvailable = Map<String, List<ExtensionPlugin>>.from(
        state.availablePlugins,
      );
      currentAvailable.remove(url);

      // Update State with Repo Removed
      state = state.copyWith(
        repositories: currentRepos,
        availablePlugins: currentAvailable,
      );

      // Remove persistence
      final prefs = await SharedPreferences.getInstance();
      var urls = prefs.getStringList('extension_repo_urls') ?? [];
      urls.remove(url);
      await prefs.setStringList('extension_repo_urls', urls);

      // Identify plugin to delete
      final pluginsToDelete = <ExtensionPlugin>[];

      for (final repoPlugin in repoPluginsToCheck) {
        final match = state.installedPlugins
            .cast<ExtensionPlugin?>()
            .firstWhere(
              (p) =>
                  p?.packageId == repoPlugin.packageId ||
                  p?.internalName == repoPlugin.internalName,
              orElse: () => null,
            );
        if (match != null) {
          pluginsToDelete.add(match);
        }
      }

      // Also try strict ID match just in case
      final strictMatches = state.installedPlugins.where(
        (p) => p.repositoryId == repoToRemove.id,
      );
      for (final p in strictMatches) {
        if (!pluginsToDelete.contains(p)) {
          // check equality by reference or ID
          if (!pluginsToDelete.any(
            (existing) => existing.packageId == p.packageId,
          )) {
            pluginsToDelete.add(p);
          }
        }
      }

      for (final plugin in pluginsToDelete) {
        await _storageService.deletePlugin(plugin);
      }

      // Final State Update to remove deleted plugin from 'installed' list
      // We essentially just filter the CURRENT state's installed list
      final newInstalled = state.installedPlugins
          .where((p) => !pluginsToDelete.any((d) => d.packageId == p.packageId))
          .toList();
      state = state.copyWith(installedPlugins: newInstalled);
    } catch (e) {
      state = state.copyWith(error: "Failed to remove repository: $e");
    }
  }

  Future<void> installPlugin(ExtensionPlugin plugin) async {
    state = state.copyWith(isLoading: true);
    try {
      File? savedFile;

      // Standard HTTP Download
      savedFile = await _repositoryService.downloadPlugin(plugin.sourceUrl);

      if (savedFile != null) {
        await _storageService.installPlugin(
          savedFile.path,
          plugin.repositoryId,
        );
        await loadInstalledPlugins();

        if (await savedFile.exists()) {
          await savedFile.delete();
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          error: "Failed to download plugin",
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updatePlugin(ExtensionPlugin plugin) async {
    await installPlugin(plugin);
  }

  Future<void> uninstallPlugin(ExtensionPlugin plugin) async {
    await _storageService.deletePlugin(plugin);
    await loadInstalledPlugins();
  }
}

final extensionsControllerProvider =
    NotifierProvider<ExtensionsController, ExtensionsState>(
      ExtensionsController.new,
    );

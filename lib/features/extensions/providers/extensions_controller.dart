import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/extensions/models/extension_plugin.dart';
import '../../../../core/extensions/models/extension_repository.dart';
import '../../../../core/extensions/providers.dart';
import '../../../core/storage/settings_repository.dart';

part 'extensions_controller.g.dart';

// State for the Extensions Screen (Sealed Class Hierarchy)
sealed class ExtensionsState {
  final List<ExtensionPlugin> installedPlugins;
  final List<ExtensionRepository> repositories;
  final Map<String, List<ExtensionPlugin>> availablePlugins; // Key: Repo URL
  final Map<String, ExtensionPlugin> availableUpdates; // Key: PackageID

  const ExtensionsState({
    this.installedPlugins = const [],
    this.repositories = const [],
    this.availablePlugins = const {},
    this.availableUpdates = const {},
  });
}

final class ExtensionsLoading extends ExtensionsState {
  const ExtensionsLoading({
    super.installedPlugins,
    super.repositories,
    super.availablePlugins,
    super.availableUpdates,
  });
}

final class ExtensionsSuccess extends ExtensionsState {
  const ExtensionsSuccess({
    required super.installedPlugins,
    required super.repositories,
    required super.availablePlugins,
    required super.availableUpdates,
  });
}

final class ExtensionsError extends ExtensionsState {
  final String message;

  const ExtensionsError(
    this.message, {
    super.installedPlugins,
    super.repositories,
    super.availablePlugins,
    super.availableUpdates,
  });
}

@Riverpod(keepAlive: true)
class ExtensionsController extends _$ExtensionsController {
  bool _initialized = false;

  @override
  ExtensionsState build() {
    return const ExtensionsLoading();
  }

  /// Call once (e.g. from Extensions screen or app startup) to load plugins and repos.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await _init();
  }

  Future<void> _init() async {
    state = ExtensionsLoading(
      installedPlugins: state.installedPlugins,
      repositories: state.repositories,
      availablePlugins: state.availablePlugins,
      availableUpdates: state.availableUpdates,
    );
    try {
      final storageService = ref.read(pluginStorageServiceProvider);
      final repositoryService = ref.read(repositoryServiceProvider);
      
      // 1. Load Installed Plugins
      final plugins = await storageService.listInstalledPlugins();
      if (ref.read(settingsRepositoryProvider).getDevLoadAssets()) {
        final assetPlugins = await _loadAssetPlugins();
        plugins.addAll(assetPlugins);
      }

      // 2. Load Repositories
      final prefs = await SharedPreferences.getInstance();
      final urls = prefs.getStringList('extension_repo_urls') ?? [];

      final repos = <ExtensionRepository>[];
      final available = <String, List<ExtensionPlugin>>{};

      for (final url in urls) {
        try {
          final repo = await repositoryService.fetchRepository(url);
          if (repo != null) {
            repos.add(repo);
            available[repo.url] = await repositoryService.getRepoPlugins(repo);
          }
        } catch (e) {
          if (kDebugMode) debugPrint("Failed to load persisted repo $url: $e");
        }
      }

      // 3. Set Final State Once
      state = ExtensionsSuccess(
        installedPlugins: plugins,
        repositories: repos,
        availablePlugins: available,
        availableUpdates: state.availableUpdates,
      );
    } catch (e) {
      state = ExtensionsError(
        e.toString(),
        installedPlugins: state.installedPlugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: state.availableUpdates,
      );
    }
  }

  Future<void> loadInstalledPlugins() async {
    state = ExtensionsLoading(
      installedPlugins: state.installedPlugins,
      repositories: state.repositories,
      availablePlugins: state.availablePlugins,
      availableUpdates: state.availableUpdates,
    );
    try {
      final storageService = ref.read(pluginStorageServiceProvider);
      final plugins = await storageService.listInstalledPlugins();

      // Load Asset Plugins if enabled
      if (ref.read(settingsRepositoryProvider).getDevLoadAssets()) {
        final assetPlugins = await _loadAssetPlugins();
        if (kDebugMode) {
          debugPrint(
            "ExtensionsController: Loaded ${assetPlugins.length} asset plugins",
          );
        }
        plugins.addAll(assetPlugins);
      } else {
        if (kDebugMode) {
          debugPrint("ExtensionsController: Asset loading disabled");
        }
      }

      state = ExtensionsSuccess(
        installedPlugins: plugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: state.availableUpdates,
      );
    } catch (e) {
      state = ExtensionsError(
        e.toString(),
        installedPlugins: state.installedPlugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: state.availableUpdates,
      );
    }
  }

  Future<List<ExtensionPlugin>> _loadAssetPlugins() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets();

      // Find all .json manifest files. Each manifest.json represents a plugin.
      final manifestFiles = assets
          .where(
            (key) => key.startsWith('assets/plugins/') && key.endsWith('.json'),
          )
          .toList();

      final plugins = <ExtensionPlugin>[];

      for (final configFile in manifestFiles) {
        final content = await rootBundle.loadString(configFile);
        // The .js file is expected to have the same name as the .json file
        final jsFile = configFile.replaceFirst('.json', '.js');

        final plugin = _parseJsonManifest(content, jsFile);
        if (plugin != null) {
          plugins.add(plugin);
        }
      }
      return plugins;
    } catch (e) {
      if (kDebugMode) debugPrint("Error loading asset plugins: $e");
      return [];
    }
  }

  ExtensionPlugin? _parseJsonManifest(String content, String jsFilePath) {
    try {
      final json = Map<String, dynamic>.from(jsonDecode(content));

      // Dart 3 Pattern Matching for manifest extraction
      final (packageName, id) = (json['packageName'] as String?, json['id'] as String?);
      
      if (packageName == null && id == null) {
        json['packageName'] = "local.asset.${jsFilePath.split('/').last}";
      }

      // Apply .debug suffix for asset plugins
      if (jsFilePath.startsWith('assets/')) {
        final currentPkg = (json['packageName'] ?? json['id']).toString();
        if (!currentPkg.endsWith('.debug')) {
          json['packageName'] = "$currentPkg.debug";
        }
      }

      // Important: The sourceUrl for the provider is the .js file
      json['url'] = jsFilePath;

      return ExtensionPlugin.fromJson(json, 'LocalAssets');
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Error parsing json manifest for $jsFilePath: $e");
      }
      return null;
    }
  }

  /// Auto-updates all stale plugins and returns the display names of every
  /// plugin that was successfully updated (empty list = nothing to update).
  Future<List<String>> checkForUpdates() async {
    final updates = <String, ExtensionPlugin>{};
    final onlineMap = <String, ExtensionPlugin>{};

    for (final list in state.availablePlugins.values) {
      for (final plugin in list) {
        onlineMap[plugin.packageName] = plugin;
      }
    }

    for (final installed in state.installedPlugins) {
      final online = onlineMap[installed.packageName];
      if (online != null && online.version > installed.version) {
        updates[installed.packageName] = online;
      }
    }

    final updatedNames = <String>[];
    if (updates.isNotEmpty) {
      state = ExtensionsSuccess(
        installedPlugins: state.installedPlugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: updates,
      );

      for (final plugin in updates.values) {
        await installPlugin(plugin);
        updatedNames.add(plugin.name);
      }

      state = ExtensionsSuccess(
        installedPlugins: state.installedPlugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: const {},
      );
    }
    return updatedNames;
  }

  Future<void> addRepository(String url, {Set<String>? visitedUrls}) async {
    // Cycle Detection
    visitedUrls ??= {};
    if (visitedUrls.contains(url)) {
      if (kDebugMode) {
        debugPrint("Recursion detected: skipping repeated repo $url");
      }
      return;
    }
    visitedUrls.add(url);

    state = ExtensionsLoading(
      installedPlugins: state.installedPlugins,
      repositories: state.repositories,
      availablePlugins: state.availablePlugins,
      availableUpdates: state.availableUpdates,
    );
    try {
      final repositoryService = ref.read(repositoryServiceProvider);
      final repo = await repositoryService.fetchRepository(url);
      if (repo != null) {
        // Handle Recursive Repositories (Megarepo)
        if (repo.includedRepos.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              "Repo ${repo.name} contains ${repo.includedRepos.length} included repos",
            );
          }
          for (final subRepoUrl in repo.includedRepos) {
            await addRepository(subRepoUrl, visitedUrls: visitedUrls);
          }

          // If the repo is PURELY a container (no plugin of its own),
          // do NOT add it to the list or persist it.
          if (repo.pluginLists.isEmpty) {
            state = ExtensionsSuccess(
              installedPlugins: state.installedPlugins,
              repositories: state.repositories,
              availablePlugins: state.availablePlugins,
              availableUpdates: state.availableUpdates,
            );
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

        final plugins = await repositoryService.getRepoPlugins(repo);
        final currentAvailable = Map<String, List<ExtensionPlugin>>.from(
          state.availablePlugins,
        );
        currentAvailable[repo.url] = plugins;

        state = ExtensionsSuccess(
          repositories: currentRepos,
          availablePlugins: currentAvailable,
          installedPlugins: state.installedPlugins,
          availableUpdates: state.availableUpdates,
        );
      } else {
        if (kDebugMode) debugPrint("Failed to parse repository at $url");
        if (visitedUrls.length == 1) {
          state = ExtensionsError(
            "Failed to parse repository",
            installedPlugins: state.installedPlugins,
            repositories: state.repositories,
            availablePlugins: state.availablePlugins,
            availableUpdates: state.availableUpdates,
          );
        } else {
          state = ExtensionsSuccess(
            installedPlugins: state.installedPlugins,
            repositories: state.repositories,
            availablePlugins: state.availablePlugins,
            availableUpdates: state.availableUpdates,
          );
        }
      }
    } catch (e) {
      state = ExtensionsError(
        e.toString(),
        installedPlugins: state.installedPlugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: state.availableUpdates,
      );
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
      state = ExtensionsSuccess(
        installedPlugins: state.installedPlugins,
        repositories: currentRepos,
        availablePlugins: currentAvailable,
        availableUpdates: state.availableUpdates,
      );

      // Remove persistence
      final prefs = await SharedPreferences.getInstance();
      final urls = prefs.getStringList('extension_repo_urls') ?? [];
      urls.remove(url);
      await prefs.setStringList('extension_repo_urls', urls);

      // Identify plugin to delete
      final pluginsToDelete = <ExtensionPlugin>[];

      for (final repoPlugin in repoPluginsToCheck) {
        final match = state.installedPlugins
            .cast<ExtensionPlugin?>()
            .firstWhere(
              (p) => p?.packageName == repoPlugin.packageName,
              orElse: () => null,
            );
        if (match != null) {
          pluginsToDelete.add(match);
        }
      }

      // Also try strict ID match just in case
      final strictMatches = state.installedPlugins.where(
        (p) => p.repositoryId == repoToRemove.packageName,
      );
      for (final p in strictMatches) {
        if (!pluginsToDelete.contains(p)) {
          // check equality by reference or Package Name
          if (!pluginsToDelete.any(
            (existing) => existing.packageName == p.packageName,
          )) {
            pluginsToDelete.add(p);
          }
        }
      }

      final storageService = ref.read(pluginStorageServiceProvider);
      for (final plugin in pluginsToDelete) {
        await storageService.deletePlugin(plugin);
      }

      // Final State Update
      final newInstalled = state.installedPlugins
          .where(
            (p) => !pluginsToDelete.any((d) => d.packageName == p.packageName),
          )
          .toList();
      state = ExtensionsSuccess(
        installedPlugins: newInstalled,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: state.availableUpdates,
      );
    } catch (e) {
      state = ExtensionsError(
        "Failed to remove repository: $e",
        installedPlugins: state.installedPlugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: state.availableUpdates,
      );
    }
  }

  Future<void> installPlugin(ExtensionPlugin plugin) async {
    await installPlugins([plugin]);
  }

  Future<void> installPlugins(List<ExtensionPlugin> plugins) async {
    state = ExtensionsLoading(
      installedPlugins: state.installedPlugins,
      repositories: state.repositories,
      availablePlugins: state.availablePlugins,
      availableUpdates: state.availableUpdates,
    );
    try {
      final repositoryService = ref.read(repositoryServiceProvider);
      final storageService = ref.read(pluginStorageServiceProvider);
      
      for (final plugin in plugins) {
        File? savedFile;

        // Standard HTTP Download
        savedFile = await repositoryService.downloadPlugin(plugin.sourceUrl);

        if (savedFile != null) {
          await storageService.installPlugin(
            savedFile.path,
            plugin.repositoryId,
          );

          // Clear this plugin from availableUpdates
          final newUpdates = Map<String, ExtensionPlugin>.from(
            state.availableUpdates,
          )..remove(plugin.packageName);
          state = ExtensionsLoading(
            installedPlugins: state.installedPlugins,
            repositories: state.repositories,
            availablePlugins: state.availablePlugins,
            availableUpdates: newUpdates,
          );

          if (await savedFile.exists()) {
            await savedFile.delete();
          }
        }
      }
      await loadInstalledPlugins();
    } catch (e) {
      state = ExtensionsError(
        e.toString(),
        installedPlugins: state.installedPlugins,
        repositories: state.repositories,
        availablePlugins: state.availablePlugins,
        availableUpdates: state.availableUpdates,
      );
    }
  }

  Future<void> updatePlugin(ExtensionPlugin plugin) async {
    await installPlugin(plugin);
  }

  Future<void> uninstallPlugin(ExtensionPlugin plugin) async {
    final storageService = ref.read(pluginStorageServiceProvider);
    await storageService.deletePlugin(plugin);
    await loadInstalledPlugins();
  }
}

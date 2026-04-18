import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/extension_plugin.dart';
import 'dart:convert';

class PluginStorageService {
  /// Root directory for extensions: app_doc_dir/extensions/plugin/
  Future<Directory> get _pluginsDir async {
    final appDocDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDocDir.path, 'extensions', 'plugin'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Installs a plugin from a .sky (Zip) file.
  ///
  /// 1. Reads the zip.
  /// 2. Extracts `plugin.json`.
  /// 3. Parses the JSON for metadata (ID, Version, etc).
  /// 4. Installs to: plugin/[ID]/
  /// 5. Generates `meta.json` for caching.
  Future<ExtensionPlugin?> installPlugin(
    String filePath,
    String? explicitRepoId,
  ) async {
    if (kDebugMode) {
      debugPrint("PluginStorageService: Installing .sky from $filePath");
    }
    final file = File(filePath);
    if (!await file.exists()) throw Exception("Plugin file not found");

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find and parse plugin.json (Plugin v2 Standard)
    final jsonFile = archive.findFile('plugin.json');
    if (jsonFile == null) {
      throw Exception(
        "Invalid .sky: Missing plugin.json (V2 Standard required)",
      );
    }

    final jsonContent = utf8.decode(jsonFile.content as List<int>);
    final Map<String, dynamic> manifestMap;
    try {
      manifestMap = jsonDecode(jsonContent);
    } catch (e) {
      throw Exception("Failed to parse plugin.json: $e");
    }

    // Ensure Unique Package Name exists (New Standard)
    if (manifestMap['packageName'] == null && manifestMap['id'] == null) {
      throw Exception("Plugin Manifest (plugin.json) missing 'packageName'");
    }

    // Create ExtensionPlugin Object
    // We use the ID as the repositoryId context for local storage structure if needed,
    // but typically repoId is the source.
    // New Model: plugin/[ID]/...
    // internalName is effectively the ID or derived.
    final plugin = ExtensionPlugin.fromJson(
      manifestMap,
      explicitRepoId ?? 'UnknownRepo',
    );

    // Create Target Directory: plugin/[packageName]/
    final rootDir = await _pluginsDir;
    final targetDir = Directory(p.join(rootDir.path, plugin.packageName));

    if (kDebugMode) {
      debugPrint("PluginStorageService: Extracting to ${targetDir.path}");
    }

    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    // Extract Files
    for (final entity in archive) {
      if (entity.isFile) {
        final filename = entity.name;
        if (filename.contains('..')) continue;

        final data = entity.content as List<int>;
        final outFile = File(p.join(targetDir.path, filename));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
      }
    }

    // Generate meta.json
    final metaFile = File(p.join(targetDir.path, 'meta.json'));
    // Add install time or source info if needed
    final metaData = Map<String, dynamic>.from(manifestMap);
    metaData['repositoryId'] = explicitRepoId; // cache source repo
    await metaFile.writeAsString(jsonEncode(metaData));

    if (kDebugMode) {
      debugPrint(
        "PluginStorageService: Installation complete for ${plugin.packageName}",
      );
    }
    return plugin;
  }

  /// Deletes a plugin directory (by Package Name)
  Future<void> deletePlugin(ExtensionPlugin plugin) async {
    final rootDir = await _pluginsDir;
    final pluginDir = Directory(p.join(rootDir.path, plugin.packageName));
    if (await pluginDir.exists()) {
      await pluginDir.delete(recursive: true);
    }
  }

  /// Deletes an entire repository folder
  Future<void> deleteRepository(String repoId) async {
    final rootDir = await _pluginsDir;
    final repoDir = Directory(p.join(rootDir.path, repoId));

    if (await repoDir.exists()) {
      await repoDir.delete(recursive: true);
    }
  }

  /// List all installed plugins
  Future<List<ExtensionPlugin>> listInstalledPlugins() async {
    final plugins = <ExtensionPlugin>[];
    final rootDir = await _pluginsDir;

    if (!await rootDir.exists()) return [];

    final children = rootDir.listSync();

    for (final entity in children) {
      if (entity is Directory) {
        try {
          // Check for meta.json (New System)
          final metaFile = File(p.join(entity.path, 'meta.json'));
          if (await metaFile.exists()) {
            final content = await metaFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final repoId = json['repositoryId'] as String? ?? 'Local';
            plugins.add(ExtensionPlugin.fromJson(json, repoId));
            continue;
          }

          // Check for plugin.json (Plugin v2 Standard)
          final jsonFile = File(p.join(entity.path, 'plugin.json'));
          if (await jsonFile.exists()) {
            final content = await jsonFile.readAsString();
            final manifest = jsonDecode(content) as Map<String, dynamic>;
            // Auto-generate meta.json if missing
            const repoId = 'Local';
            manifest['repositoryId'] = repoId;
            await metaFile.writeAsString(jsonEncode(manifest));
            plugins.add(ExtensionPlugin.fromJson(manifest, repoId));
            continue;
          }

          // Legacy Folder Structure Loop (Optional: if we still want to see old plugins?)
          // User said "no backward compatibility", so we can ignore nested repo dirs if they don't follow new structure.
        } catch (e) {
          if (kDebugMode) {
            debugPrint("Error reading plugin at ${entity.path}: $e");
          }
        }
      }
    }
    return plugins;
  }

  /// Get full path to the JS file for a plugin
  Future<String> getPluginJsPath(ExtensionPlugin plugin) async {
    if (plugin.repositoryId == 'LocalAssets') {
      return plugin.sourceUrl;
    }

    final rootDir = await _pluginsDir;
    // New Path: plugin/[packageName]/plugin.js
    final jsFile = File(p.join(rootDir.path, plugin.packageName, 'plugin.js'));
    return jsFile.path;
  }

  /// Persists a dynamic settings schema to meta.json
  Future<void> saveSettingsSchema(
    String packageName,
    List<dynamic> schema,
  ) async {
    final rootDir = await _pluginsDir;
    final metaFile = File(p.join(rootDir.path, packageName, 'meta.json'));

    if (await metaFile.exists()) {
      final content = await metaFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      data['settingsSchema'] = schema;
      await metaFile.writeAsString(jsonEncode(data));
      if (kDebugMode) {
        debugPrint(
          "PluginStorageService: Saved settings schema for $packageName",
        );
      }
    }
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'dart:io';
import 'dart:convert';
import '../models/extension_repository.dart';
import '../models/extension_plugin.dart';

class RepositoryService {
  final Dio _dio;

  RepositoryService(this._dio);

  /// Resolves the actual URL from shortcodes or custom schemes
  Future<String?> parseRepoUrl(String url) async {
    final fixedUrl = url.trim();

    // Standard HTTP/HTTPS
    if (RegExp(r'^https?://').hasMatch(fixedUrl)) {
      return fixedUrl;
    } 
    
    // Shortcode (Alphanumeric) -> cutt.ly
    if (RegExp(r'^[a-zA-Z0-9!_-]+$').hasMatch(fixedUrl)) {
      try {
        final response = await _dio.get(
          "https://cutt.ly/sky-$fixedUrl",
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        
        // 3xx status codes usually have location header
        if (response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303 || response.statusCode == 307) {
           final location = response.headers.value('location');
           if (location != null) {
              if (location.startsWith("https://cutt.ly/404") || location.replaceAll(RegExp(r'/$'), '') == "https://cutt.ly") {
                throw Exception("Shortcode not found");
              }
              return location;
           }
        }
        throw Exception("Invalid response from shortcode service");
      } on DioException catch (e) {
        throw Exception("Network error resolving shortcode: ${e.message}");
      } catch (e) {
        throw Exception("Shortcode resolution failed: $e");
      }
    }

    throw Exception("Invalid URL format");
  }

  /// Fetch and parse a Repository from a URL
  Future<ExtensionRepository?> fetchRepository(String url) async {
    try {
      // Resolve Shortcodes / Protocols
      final resolvedUrl = await parseRepoUrl(url);
      if (resolvedUrl == null) {
         // Should be unreachable if parseRepoUrl throws, but for safety:
         throw Exception("Failed to resolve URL");
      }

      // Handle raw github urls -> jsdelivr if needed
      final normalizedUrl = _normalizeUrl(resolvedUrl);
      
      final response = await _dio.get(normalizedUrl);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String 
            ? _jsonDecodeSafe(response.data) 
            : response.data as Map<String, dynamic>;
            
        if (data != null) {
          // Validation: A valid repository must have a name, an ID, and either pluginLists or repos
          final hasName = data.containsKey('name');
          final hasId = data.containsKey('id');
          // Extract lists safely to check content
          final plugins = (data['pluginLists'] as List?) ?? [];
          final repos = (data['repos'] as List?) ?? [];
          
          final hasPlugins = plugins.isNotEmpty;
          final hasRepos = repos.isNotEmpty;

          if (!hasName || !hasId || (!hasPlugins && !hasRepos)) {
             throw Exception('Invalid repository format: Missing name, id, or plugin/repos');
          }
          
          if (hasPlugins && hasRepos) {
             throw Exception("Repository cannot contain both 'pluginLists' and 'repos'. Please separate them.");
          }

          return ExtensionRepository.fromJson(data, url);
        }
      }
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('Failed to fetch repository $url: $e');
    } catch (e) {
       // Rethrow validation exceptions or others
       rethrow;
    }
    return null;
  }

  /// Fetch all plugin listed in a Repository
  Future<List<ExtensionPlugin>> getRepoPlugins(ExtensionRepository repo) async {
    final List<ExtensionPlugin> allPlugins = [];
    
    // Add plugins directly embedded in the repository manifest (Enterprise V2)
    allPlugins.addAll(repo.plugins);

    for (final pluginListUrl in repo.pluginLists) {
      try {
        final normalizedUrl = _normalizeUrl(pluginListUrl);
        final response = await _dio.get(normalizedUrl);
        
        if (response.statusCode == 200 && response.data != null) {
           final List<dynamic>? list = response.data is String 
              ? _jsonDecodeSafe(response.data) as List<dynamic>?
              : response.data as List<dynamic>?;

           if (list != null) {
             final plugins = list.map((e) => ExtensionPlugin.fromJson(e, repo.id)).toList();
             allPlugins.addAll(plugins);
           }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to fetch plugin list $pluginListUrl: $e');
      }
    }
    
    return allPlugins;
  }

  /// Download a plugin file to a temporary location
  Future<File?> downloadPlugin(String url) async {
    try {
      final normalizedUrl = _normalizeUrl(url);
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.sky');
      
      await _dio.download(normalizedUrl, tempFile.path);
      
      if (await tempFile.exists()) {
        return tempFile;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to download plugin $url: $e');
    }
    return null;
  }

  String _normalizeUrl(String url) {
    // Basic normalization, can be expanded to match Native's "convertRawGitUrl"
    if (url.contains('raw.githubusercontent.com')) {
      // Native app converts to jsdelivr for caching/performance
      // Regex: ^https://raw.githubusercontent.com/([A-Za-z0-9-]+)/([A-Za-z0-9_.-]+)/(.*)$
      // Replacement: https://cdn.jsdelivr.net/gh/$1/$2@$3
      // We can implement this later if needed for parity/performance
    }
    return url;
  }

  dynamic _jsonDecodeSafe(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      return null;
    }
  }
}

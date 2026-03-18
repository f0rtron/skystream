import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Represents an external video player that can be launched from Skystream.
class ExternalPlayer {
  final String id;
  final String displayName;
  final IconData icon;
  final Set<TargetPlatform> supportedPlatforms;

  // Platform-specific identifiers
  final String? androidPackage; // e.g. 'org.videolan.vlc'
  final String?
  androidAction; // e.g. 'org.videolan.vlc.player.VideoPlayerActivity'
  final String? iosScheme; // e.g. 'vlc://'
  final String? desktopCommand; // e.g. 'vlc'
  final String? macAppName; // e.g. 'VLC' for `open -a VLC`

  const ExternalPlayer({
    required this.id,
    required this.displayName,
    required this.icon,
    required this.supportedPlatforms,
    this.androidPackage,
    this.androidAction,
    this.iosScheme,
    this.desktopCommand,
    this.macAppName,
  });
}

class ExternalPlayerService {
  ExternalPlayerService._();
  static final ExternalPlayerService instance = ExternalPlayerService._();

  /// All known external players across platforms.
  static const List<ExternalPlayer> allPlayers = [
    ExternalPlayer(
      id: 'vlc',
      displayName: 'VLC',
      icon: Icons.play_circle_filled,
      supportedPlatforms: {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      },
      androidPackage: 'org.videolan.vlc',
      iosScheme: 'vlc://',
      desktopCommand: 'vlc',
      macAppName: 'VLC',
    ),
    ExternalPlayer(
      id: 'mx_player',
      displayName: 'MX Player',
      icon: Icons.ondemand_video,
      supportedPlatforms: {TargetPlatform.android},
      androidPackage: 'com.mxtech.videoplayer.ad',
    ),
    ExternalPlayer(
      id: 'mx_player_pro',
      displayName: 'MX Player Pro',
      icon: Icons.ondemand_video,
      supportedPlatforms: {TargetPlatform.android},
      androidPackage: 'com.mxtech.videoplayer.pro',
    ),
    ExternalPlayer(
      id: 'just_player',
      displayName: 'Just Player',
      icon: Icons.smart_display,
      supportedPlatforms: {TargetPlatform.android},
      androidPackage: 'com.brouken.player',
    ),
    ExternalPlayer(
      id: 'mpv_android',
      displayName: 'mpv (Android)',
      icon: Icons.videocam,
      supportedPlatforms: {TargetPlatform.android},
      androidPackage: 'is.xyz.mpv',
    ),
    ExternalPlayer(
      id: 'mpv',
      displayName: 'mpv',
      icon: Icons.videocam,
      supportedPlatforms: {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      },
      desktopCommand: 'mpv',
    ),
    ExternalPlayer(
      id: 'iina',
      displayName: 'IINA',
      icon: Icons.play_circle,
      supportedPlatforms: {TargetPlatform.macOS},
      desktopCommand: 'iina',
      macAppName: 'IINA',
    ),
    ExternalPlayer(
      id: 'infuse',
      displayName: 'Infuse',
      icon: Icons.live_tv,
      supportedPlatforms: {TargetPlatform.iOS},
      iosScheme: 'infuse://',
    ),
    ExternalPlayer(
      id: 'nplayer',
      displayName: 'nPlayer',
      icon: Icons.video_library,
      supportedPlatforms: {TargetPlatform.iOS},
      iosScheme: 'nplayer-',
    ),
    ExternalPlayer(
      id: 'potplayer',
      displayName: 'PotPlayer',
      icon: Icons.play_circle_outline,
      supportedPlatforms: {TargetPlatform.windows},
      desktopCommand: 'PotPlayerMini64',
    ),
    ExternalPlayer(
      id: 'celluloid',
      displayName: 'Celluloid',
      icon: Icons.movie,
      supportedPlatforms: {TargetPlatform.linux},
      desktopCommand: 'celluloid',
    ),
  ];

  /// Returns players available on the current platform.
  List<ExternalPlayer> getPlayersForPlatform() {
    final platform = defaultTargetPlatform;
    return allPlayers
        .where((p) => p.supportedPlatforms.contains(platform))
        .toList();
  }

  /// Finds a player by its ID.
  ExternalPlayer? getPlayerById(String id) {
    try {
      return allPlayers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Launches a video URL in the specified external player.
  ///
  /// [videoUrl] — direct video stream URL (not the episode data blob)
  /// [headers] — optional HTTP headers for the stream
  /// [playerId] — the external player ID to use
  /// [title] — optional video title for players that support it
  Future<bool> launch(
    String videoUrl, {
    Map<String, String>? headers,
    required String playerId,
    String? title,
  }) async {
    final player = getPlayerById(playerId);
    if (player == null) return false;

    try {
      if (Platform.isAndroid) {
        return await _launchAndroid(
          videoUrl,
          player,
          headers: headers,
          title: title,
        );
      } else if (Platform.isIOS) {
        return await _launchIOS(videoUrl, player);
      } else if (Platform.isMacOS) {
        return await _launchMacOS(videoUrl, player);
      } else if (Platform.isWindows) {
        return await _launchWindows(videoUrl, player);
      } else if (Platform.isLinux) {
        return await _launchLinux(videoUrl, player);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ExternalPlayer launch error: $e');
    }
    return false;
  }

  // -- Android: Intent-based launch via url_launcher --

  Future<bool> _launchAndroid(
    String videoUrl,
    ExternalPlayer player, {
    Map<String, String>? headers,
    String? title,
  }) async {
    // Try intent URI for maximum compatibility
    if (player.androidPackage != null) {
      final intentUri = Uri.parse(
        'intent:$videoUrl#Intent;'
        'action=android.intent.action.VIEW;'
        'category=android.intent.category.DEFAULT;'
        'type=video/*;'
        'package=${player.androidPackage};'
        '${title != null ? "S.title=${Uri.encodeComponent(title)};" : ""}'
        'end',
      );
      try {
        // Don't use canLaunchUrl for intent URIs — it doesn't work reliably
        // on Android. Just attempt the launch directly.
        return await launchUrl(intentUri);
      } catch (e) {
        if (kDebugMode) debugPrint('Android intent launch failed: $e');
      }
    }

    // Fallback: ACTION_VIEW with video MIME type
    final uri = Uri.parse(videoUrl);
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // -- iOS: Custom URL scheme --

  Future<bool> _launchIOS(String videoUrl, ExternalPlayer player) async {
    if (player.iosScheme != null) {
      // VLC: vlc://url
      // Infuse: infuse://x-callback-url/play?url=...
      // nPlayer: nplayer-http://url or nplayer-https://url
      String launchUrl;

      if (player.id == 'vlc') {
        launchUrl = 'vlc://${Uri.encodeComponent(videoUrl)}';
      } else if (player.id == 'infuse') {
        launchUrl =
            'infuse://x-callback-url/play?url=${Uri.encodeComponent(videoUrl)}';
      } else if (player.id == 'nplayer') {
        // nPlayer replaces http:// with nplayer-http://
        launchUrl = videoUrl.replaceFirst(
          RegExp(r'^https?://'),
          'nplayer-http://',
        );
      } else {
        launchUrl = '${player.iosScheme}${Uri.encodeComponent(videoUrl)}';
      }

      final uri = Uri.parse(launchUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl_(uri);
      }
    }
    return false;
  }

  // Wrapper to avoid name collision with url_launcher's launchUrl
  Future<bool> launchUrl_(Uri uri) async {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // -- macOS: open -a or CLI --

  Future<bool> _launchMacOS(String videoUrl, ExternalPlayer player) async {
    try {
      if (player.macAppName != null) {
        final result = await Process.run('open', [
          '-a',
          player.macAppName!,
          videoUrl,
        ]);
        return result.exitCode == 0;
      }
      if (player.desktopCommand != null) {
        final result = await Process.run(player.desktopCommand!, [videoUrl]);
        return result.exitCode == 0;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('macOS launch error: $e');
    }
    return false;
  }

  // -- Windows: Process.run with command --

  Future<bool> _launchWindows(String videoUrl, ExternalPlayer player) async {
    try {
      if (player.desktopCommand != null) {
        try {
          // Try running the command directly (works if it's in PATH)
          final result = await Process.run(player.desktopCommand!, [videoUrl]);
          if (result.exitCode == 0) return true;
        } catch (_) {
          // Command not recognized or not in PATH, proceed to fallback
        }
      }
      // Fallback: try vlc:// protocol handler
      if (player.id == 'vlc') {
        final uri = Uri.parse('vlc://${Uri.encodeComponent(videoUrl)}');
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (player.id == 'potplayer') {
         final uri = Uri.parse('potplayer://${Uri.encodeComponent(videoUrl)}');
         if (await canLaunchUrl(uri)) {
             return await launchUrl(uri, mode: LaunchMode.externalApplication);
         }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Windows launch error: $e');
    }
    return false;
  }

  // -- Linux: Process.run with CLI --

  Future<bool> _launchLinux(String videoUrl, ExternalPlayer player) async {
    try {
      if (player.desktopCommand != null) {
        try {
          final result = await Process.run(player.desktopCommand!, [videoUrl]);
          return result.exitCode == 0;
        } catch (_) {
          // Command not recognized or not in PATH
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Linux launch error: $e');
    }
    return false;
  }
}

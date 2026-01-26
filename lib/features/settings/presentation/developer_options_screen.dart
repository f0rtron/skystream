import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:virtual_mouse/virtual_mouse.dart';

import '../../extensions/providers/extensions_controller.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/domain/entity/multimedia_item.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../shared/widgets/tv_input_widgets.dart';
import 'widgets/settings_widgets.dart';

import 'package:flutter/foundation.dart';

class DeveloperOptionsScreen extends ConsumerStatefulWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  ConsumerState<DeveloperOptionsScreen> createState() =>
      _DeveloperOptionsScreenState();
}

class _DeveloperOptionsScreenState
    extends ConsumerState<DeveloperOptionsScreen> {
  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceProfileProvider);

    final scaffold = Scaffold(
      appBar: AppBar(title: const Text('Developer Options')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsGroup(
            title: 'Debug Tools',
            children: [
              SettingsTile(
                icon: Icons.video_file_rounded,
                title: 'Play local video file',
                subtitle: 'Play any video from device',
                onTap: () => _pickLocalVideo(context),
              ),
              SettingsTile(
                icon: Icons.link_rounded,
                title: 'Stream URL',
                subtitle: 'Play from network URL',
                onTap: () => _showStreamUrlDialog(
                  context,
                  deviceAsync.asData?.value.isTv ?? false,
                ),
              ),
              SettingsTile(
                icon: Icons.stream,
                title: 'Stream torrent',
                subtitle: 'Select a local torrent file to play',
                onTap: () => _pickTorrentFile(context),
              ),
              FutureBuilder<bool>(
                future: Future.value(
                  ref.read(storageServiceProvider).getDevLoadAssets(),
                ),
                builder: (context, snapshot) {
                  final enabled = snapshot.data ?? false;
                  return SettingsTile(
                    icon: Icons.folder_copy_rounded,
                    title: 'Load plugin from assets',
                    subtitle: enabled ? 'Enabled' : 'Disabled',
                    isLast: true,
                    trailing: Switch(
                      value: enabled,
                      onChanged: (val) =>
                          _toggleAssetLoading(context, val, enabled),
                    ),
                    onTap: () =>
                        _toggleAssetLoading(context, !enabled, enabled),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );

    // Wrap with VirtualMouse on TV (this screen bypasses AppScaffold)
    return deviceAsync.when(
      data: (profile) {
        if (profile.isTv) {
          return VirtualMouse(
            visible: true,
            velocity: 5,
            pointerColor: Theme.of(context).colorScheme.primary,
            child: scaffold,
          );
        }
        return scaffold;
      },
      loading: () => scaffold,
      error: (_, __) => scaffold,
    );
  }

  Future<void> _toggleAssetLoading(
    BuildContext context,
    bool newValue,
    bool currentEnabled,
  ) async {
    if (!kDebugMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This feature is only available in Debug builds'),
        ),
      );
      // Ensure UI reflects the blocked state (stays disabled)
      if (context.mounted) setState(() {});
      return;
    }

    await ref.read(storageServiceProvider).setDevLoadAssets(newValue);
    if (context.mounted) setState(() {});

    // Refresh extensions
    ref.read(extensionsControllerProvider.notifier).loadInstalledPlugins();
  }

  Future<void> _pickLocalVideo(BuildContext context) async {
    // Request Permissions for Direct Access
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request();
    }
    if (!await Permission.storage.isGranted) {
      await Permission.storage.request();
    }

    if (!context.mounted) return;

    // Open Direct File Browser
    final String? path = await FilesystemPicker.open(
      title: 'Select Video',
      context: context,
      rootDirectory: Directory('/storage/emulated/0'),
      fsType: FilesystemType.file,
      allowedExtensions: ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv'],
      fileTileSelectMode: FileTileSelectMode.wholeTile,
    );

    if (path != null && context.mounted) {
      final name = path.split('/').last; // Extract filename

      context.push(
        '/player',
        extra: {
          'item': MultimediaItem(
            title: name,
            url: path,
            posterUrl: '',
            provider: 'Local',
            episodes: [Episode(name: name, url: path, posterUrl: '')],
          ),
          'url': path,
        },
      );
    }
  }

  void _showStreamUrlDialog(BuildContext context, bool isTv) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Stream URL'),
        content: TvTextField(
          controller: controller,
          hintText: 'Enter video URL (http, magnet, etc.)',
          autofocus: false, // Start focus on Play button
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TvButton(
            showFocusHighlight: isTv,
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TvButton(
            autofocus: true,
            isPrimary: true,
            showFocusHighlight: isTv,
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                String title = 'Network Stream';
                try {
                  final uri = Uri.parse(url);
                  if (uri.pathSegments.isNotEmpty) {
                    title = uri.pathSegments.last;
                  }
                } catch (_) {}

                Navigator.pop(context);
                context.push(
                  '/player',
                  extra: {
                    'item': MultimediaItem(
                      title: title,
                      url: url, // Unique URL for history
                      posterUrl: '',
                      provider: 'Remote',
                      episodes: [Episode(name: title, url: url, posterUrl: '')],
                    ),
                    'url': url,
                  },
                );
              }
            },
            child: const Text("Play"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTorrentFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null && result.files.single.path != null && context.mounted) {
      final path = result.files.single.path!;
      final name = result.files.single.name;

      context.push(
        '/player',
        extra: {
          'item': MultimediaItem(
            title: name,
            url: path,
            posterUrl: '',
            provider: 'Torrent',
            episodes: [Episode(name: name, url: path, posterUrl: '')],
          ),
          'url': path,
        },
      );
    }
  }
}

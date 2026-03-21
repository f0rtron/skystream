import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/services/download_service.dart';
import 'package:skystream/shared/widgets/custom_widgets.dart';
import 'package:collection/collection.dart';
import '../../../library/presentation/downloads_provider.dart';
import '../playback_launcher.dart';
import '../details_controller.dart';
import '../downloaded_file_provider.dart';

class DownloadManagementDialog extends HookConsumerWidget {
  final MultimediaItem item;
  final Episode? episode;
  final File file;

  const DownloadManagementDialog({
    super.key,
    required this.item,
    this.episode,
    required this.file,
  });

  static Future<void> show(
    BuildContext context,
    MultimediaItem item,
    File file, {
    Episode? episode,
  }) async {
    return showDialog(
      context: context,
      builder: (context) =>
          DownloadManagementDialog(item: item, file: file, episode: episode),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Try to get fresh details from the controller if available
    final detailsState = ref.watch(detailsControllerProvider(item.url));
    final currentItem = detailsState.item ?? item;

    final title = episode != null
        ? '${currentItem.title} - ${episode!.name}'
        : currentItem.title;

    final downloads = ref.watch(downloadsProvider).value ?? [];
    final matchingItem = downloads.firstWhereOrNull((d) =>
        d.item.url == item.url && d.episode?.url == episode?.url);

    return AlertDialog(
      title: Text(title),
      content: const Text(
        'This video is already downloaded. What would you like to do?',
      ),
      actions: [
        CustomButton(
          isPrimary: false,
          onPressed: () => Navigator.pop(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Cancel'),
          ),
        ),
        CustomButton(
          isPrimary: false,
          isOutlined: true,
          onPressed: () => _showDeleteConfirmation(context, ref, matchingItem),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
        CustomButton(
          isPrimary: true,
          onPressed: () {
            Navigator.pop(context);
            _playLocalFile(context, ref, currentItem);
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, size: 20),
                SizedBox(width: 8),
                Text('Play Now'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    DownloadItem? matchingItem,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Download?'),
        content: const Text(
          'Are you sure you want to delete this file? This cannot be undone.',
        ),
        actions: [
          CustomButton(
            isPrimary: false,
            onPressed: () => Navigator.pop(context, false),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No'),
            ),
          ),
          CustomButton(
            isPrimary: true,
            backgroundColor: Colors.red,
            onPressed: () => Navigator.pop(context, true),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Yes, Delete', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (matchingItem != null) {
        await ref.read(downloadsProvider.notifier).removeDownload(matchingItem);
      } else {
        await ref.read(downloadServiceProvider).deleteDownloadedFile(file);
      }

      ref
          .read(downloadedFilesProvider.notifier)
          .removeFile(episode?.url ?? item.url);
      if (context.mounted) Navigator.pop(context);
    }
  }

  void _playLocalFile(
    BuildContext context,
    WidgetRef ref,
    MultimediaItem details,
  ) {
    ref.read(playbackLauncherProvider).play(
      context,
      file.path,
      baseItem: details,
      detailedItem: details,
    );
  }
}

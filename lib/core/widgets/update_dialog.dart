import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/update_provider.dart';
import '../data/models/github_release.dart';

class UpdateDialog extends ConsumerWidget {
  final GithubRelease release;

  const UpdateDialog({super.key, required this.release});

  static void show(BuildContext context, GithubRelease release) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(release: release),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateControllerProvider);

    return PopScope(
      canPop: updateState is! UpdateDownloading,
      child: AlertDialog(
        title: Text('Update Available: ${release.tagName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (updateState is UpdateDownloading) ...[
              const Text('Downloading update...'),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: updateState.progress),
              const SizedBox(height: 10),
              Text('${(updateState.progress * 100).toStringAsFixed(0)}%'),
            ] else if (updateState is UpdateError) ...[
               Text('Error: ${updateState.message}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ] else ...[
               // Truncate body if too long
               ConstrainedBox(
                 constraints: const BoxConstraints(maxHeight: 200),
                 child: SingleChildScrollView(
                   child: Text(release.body),
                 ),
               ),
            ],
          ],
        ),
        actions: [
          if (updateState is! UpdateDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          if (updateState is! UpdateDownloading)
            FilledButton(
              onPressed: () {
                ref.read(updateControllerProvider.notifier).downloadAndInstall(release);
              },
              child: const Text('Update Now'),
            ),
        ],
      ),
    );
  }
}

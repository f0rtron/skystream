import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/models/torrent_status.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/services/notification_service.dart';
import '../../../settings/presentation/player_settings_provider.dart';
import '../player_controller.dart';
import 'player_utils.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../subtitle_search_provider.dart';
import '../../domain/entity/subtitle_model.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

class PlayerBottomSheets {
  static void showSourceSelection({
    required BuildContext context,
    required List<StreamResult>? streams,
    required StreamResult? currentStream,
    required void Function(StreamResult) onStreamSelected,
  }) {
    if (streams == null || streams.isEmpty) return;
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                  child: Text(
                    AppLocalizations.of(context)!.selectSource,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(color: theme.dividerColor),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: streams.length,
                    itemBuilder: (ctx, index) {
                      final s = streams[index];
                      final isSelected = s == currentStream;
                      return ListTile(
                        leading: Icon(
                          Icons.source,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.iconTheme.color,
                        ),
                        title: Text(
                          s.source,
                          style: TextStyle(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          onStreamSelected(s);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void showContentSelection({
    required BuildContext context,
    required TorrentStatus? torrentStatus,
    required void Function(int) onTorrentFileSelected,
  }) {
    if (torrentStatus == null) return;
    final files = torrentStatus.data['file_stats'] as List<dynamic>?;
    if (files == null || files.isEmpty) return;

    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                  child: Text(
                    AppLocalizations.of(context)!.torrentContent,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(color: theme.dividerColor, height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: files.length,
                    itemBuilder: (ctx, index) {
                      final file = files[index];
                      final path =
                          file['path'] as String? ??
                          AppLocalizations.of(context)!.unknown;
                      final length = file['length'] as int? ?? 0;
                      final id =
                          file['id'] as int? ??
                          (index + 1); // Fallback if id missing

                      // Simple check if this looks like a video
                      final isVideo =
                          path.toLowerCase().endsWith(".mp4") ||
                          path.toLowerCase().endsWith(".mkv") ||
                          path.toLowerCase().endsWith(".avi") ||
                          path.toLowerCase().endsWith(".mov");

                      return ListTile(
                        leading: Icon(
                          isVideo
                              ? Icons.movie_creation_outlined
                              : Icons.insert_drive_file_outlined,
                          color: isVideo
                              ? theme.colorScheme.primary
                              : theme.iconTheme.color,
                        ),
                        title: Text(
                          path.split('/').last, // Show filename only
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        subtitle: Text(
                          formatBytes(length),
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          onTorrentFileSelected(id);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void showTracksSelection({
    required BuildContext context,
    required WidgetRef ref,
  }) {
    final controller = ref.read(playerControllerProvider.notifier);
    final snapshot = controller.getTrackSelectionSnapshot();
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(LayoutConstants.spacingMd),
              children: [
                Text(
                  AppLocalizations.of(context)!.audioTracks,
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Divider(color: theme.dividerColor),
                ...snapshot.audioTracks.map((track) {
                  return ListTile(
                    title: Text(
                      track.label,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    subtitle: track.subtitle != null
                        ? Text(
                            track.subtitle!,
                            style: TextStyle(
                              color: theme.textTheme.bodySmall?.color,
                              fontSize: 10,
                            ),
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await controller.selectAudioTrack(track.id);
                    },
                    selected: track.selected,
                    selectedColor: theme.colorScheme.primary,
                    trailing: track.selected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                  );
                }),
                if (snapshot.audioTracks.isEmpty)
                  Text(
                    AppLocalizations.of(context)!.noAudioTracks,
                    style: TextStyle(color: theme.textTheme.bodySmall?.color),
                  ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.subtitles,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showSubtitleOptions(context);
                      },
                      icon: const Icon(Icons.settings, size: 18),
                      label: Text(AppLocalizations.of(context)!.options),
                    ),
                  ],
                ),
                Divider(color: theme.dividerColor),
                ListTile(
                  title: Text(
                    AppLocalizations.of(context)!.off,
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await controller.selectSubtitleTrack(null);
                  },
                  selected: snapshot.subtitlesOffSelected,
                  trailing: snapshot.subtitlesOffSelected
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                ),
                ...snapshot.subtitleTracks.map((track) {
                  return ListTile(
                    title: Text(
                      track.label,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    subtitle: track.subtitle != null
                        ? Text(
                            track.subtitle!,
                            style: TextStyle(
                              color: theme.textTheme.bodySmall?.color,
                              fontSize: 10,
                            ),
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await controller.selectSubtitleTrack(track.id);
                    },
                    selected: track.selected,
                    selectedColor: theme.colorScheme.primary,
                    trailing: track.selected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                  );
                }),
                if (snapshot.subtitleTracks.isEmpty)
                  Text(
                    AppLocalizations.of(context)!.noSubtitlesFound,
                    style: TextStyle(color: theme.textTheme.bodySmall?.color),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static void showSpeedSelection({
    required BuildContext context,
    required double currentSpeed,
    required double maxSpeed,
    required void Function(double) onSpeedSelected,
  }) {
    final theme = Theme.of(context);
    final speeds = [
      0.5,
      0.75,
      1.0,
      1.25,
      1.5,
      1.75,
      2.0,
      2.25,
      2.5,
      2.75,
      3.0,
    ].where((speed) => speed <= maxSpeed + 0.001).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                  child: Text(
                    AppLocalizations.of(context)!.playbackSpeed,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(color: theme.dividerColor),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: speeds.length,
                    itemBuilder: (ctx, index) {
                      final s = speeds[index];
                      final isSelected = s == currentSpeed;
                      return ListTile(
                        leading: Icon(
                          Icons.speed,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.iconTheme.color,
                        ),
                        title: Text(
                          "${s}x",
                          style: TextStyle(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          onSpeedSelected(s);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _showSubtitleOptions(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, child) {
            final supportsExternalSubtitleLoading = ref.watch(
              playerControllerProvider.select(
                (s) => s.supportsExternalSubtitleLoading,
              ),
            );
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                      child: Text(
                        AppLocalizations.of(context)!.subtitleOptions,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Divider(color: theme.dividerColor, height: 1),
                    if (!supportsExternalSubtitleLoading)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.hlsSubtitleWarning,
                                style: TextStyle(
                                  color: Colors.orange.shade200,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.file_open_outlined),
                      title: Text(AppLocalizations.of(context)!.loadFromDevice),
                      onTap: !supportsExternalSubtitleLoading
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              ref
                                  .read(playerControllerProvider.notifier)
                                  .loadExternalSubtitleFile();
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.sync),
                      title: Text(AppLocalizations.of(context)!.syncDelay),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showSubtitleSync(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.style),
                      title: Text(AppLocalizations.of(context)!.styleSettings),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showSubtitleStyles(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.search),
                      title: Text(AppLocalizations.of(context)!.searchOnline),
                      onTap: !supportsExternalSubtitleLoading
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _showSubtitleSearch(context);
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void _showSubtitleSync(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, child) {
            final currentDelay = ref.watch(
              playerControllerProvider.select((s) => s.subtitleDelay),
            );
            final supportsSubtitleDelay = ref.watch(
              playerControllerProvider.select((s) => s.supportsSubtitleDelay),
            );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.subtitleSync,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!supportsSubtitleDelay) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.subtitleDelayWarning,
                                style: TextStyle(
                                  color: Colors.orange.shade200,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: !supportsSubtitleDelay
                              ? null
                              : () => ref
                                    .read(playerControllerProvider.notifier)
                                    .setSubtitleDelay(currentDelay - 0.1),
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          "${currentDelay.toStringAsFixed(1)}s",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: !supportsSubtitleDelay
                                ? Colors.white38
                                : null,
                          ),
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          onPressed: !supportsSubtitleDelay
                              ? null
                              : () => ref
                                    .read(playerControllerProvider.notifier)
                                    .setSubtitleDelay(currentDelay + 0.1),
                          icon: const Icon(Icons.add_circle_outline, size: 32),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: !supportsSubtitleDelay
                          ? null
                          : () => ref
                                .read(playerControllerProvider.notifier)
                                .setSubtitleDelay(0.0),
                      child: Text(AppLocalizations.of(context)!.resetDelay),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static void _showSubtitleStyles(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, child) {
            final supportsSubtitleStyling = ref.watch(
              playerControllerProvider.select((s) => s.supportsSubtitleStyling),
            );
            final settings =
                ref.watch(playerSettingsProvider).asData?.value ??
                const PlayerSettings();

            if (!supportsSubtitleStyling) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.subtitleStyles,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.mediaKitStylingWarning,
                                style: TextStyle(
                                  color: Colors.orange.shade200,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.subtitleStyles,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: AppLocalizations.of(context)!.resetToDefault,
                          onPressed: () {
                            ref
                                .read(playerSettingsProvider.notifier)
                                .resetSubtitleSettings();
                            ref
                                .read(playerControllerProvider.notifier)
                                .applySubtitleSettings();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Font Size
                    Text(
                      AppLocalizations.of(context)!.fontSize,
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                    ),
                    Slider(
                      value: settings.subtitleSize,
                      min: 10,
                      max: 60,
                      onChanged: (v) {
                        ref
                            .read(playerSettingsProvider.notifier)
                            .setSubtitleSettings(
                              v,
                              settings.subtitleColor,
                              settings.subtitleBackgroundColor,
                            );
                        ref
                            .read(playerControllerProvider.notifier)
                            .applySubtitleSettings();
                      },
                    ),

                    // Position
                    Text(
                      AppLocalizations.of(context)!.verticalPosition,
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                    ),
                    Slider(
                      value: settings.subtitlePosition,
                      min: 50,
                      max: 100,
                      onChanged: (v) {
                        ref
                            .read(playerSettingsProvider.notifier)
                            .setSubtitlePosition(v);
                        ref
                            .read(playerControllerProvider.notifier)
                            .applySubtitleSettings();
                      },
                    ),

                    // Color Presets
                    const SizedBox(height: 10),
                    Text(
                      AppLocalizations.of(context)!.textColor,
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            [
                                  _colorCircle(
                                    0xFFFFFFFF,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFFFFFF00,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFF00FFFF,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFFFF00FF,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFF00FF00,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFFFF0000,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFF2196F3,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFFFF9800,
                                    settings.subtitleColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            c,
                                            settings.subtitleBackgroundColor,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                ]
                                .map(
                                  (w) => Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: w,
                                  ),
                                )
                                .toList(),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context)!.backgroundColor,
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            [
                                  _colorCircle(
                                    0x00000000,
                                    settings.subtitleBackgroundColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            settings.subtitleColor,
                                            c,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFF000000,
                                    settings.subtitleBackgroundColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            settings.subtitleColor,
                                            c,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFF333333,
                                    settings.subtitleBackgroundColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            settings.subtitleColor,
                                            c,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFF1A1A1A,
                                    settings.subtitleBackgroundColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            settings.subtitleColor,
                                            c,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                  _colorCircle(
                                    0xFF001F3F,
                                    settings.subtitleBackgroundColor,
                                    (c) {
                                      ref
                                          .read(playerSettingsProvider.notifier)
                                          .setSubtitleSettings(
                                            settings.subtitleSize,
                                            settings.subtitleColor,
                                            c,
                                            settings.subtitleBackgroundOpacity,
                                          );
                                      ref
                                          .read(
                                            playerControllerProvider.notifier,
                                          )
                                          .applySubtitleSettings();
                                    },
                                  ),
                                ]
                                .map(
                                  (w) => Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: w,
                                  ),
                                )
                                .toList(),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.backgroundOpacity,
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                    ),
                    Slider(
                      value: settings.subtitleBackgroundOpacity,
                      min: 0,
                      max: 1,
                      onChanged: (v) {
                        ref
                            .read(playerSettingsProvider.notifier)
                            .setSubtitleBackgroundOpacity(v);
                        ref
                            .read(playerControllerProvider.notifier)
                            .applySubtitleSettings();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _colorCircle(
    int colorValue,
    int selectedColor,
    void Function(int) onSelected,
  ) {
    final isSelected = colorValue == selectedColor;
    return GestureDetector(
      onTap: () => onSelected(colorValue),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(colorValue),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.black54)
            : null,
      ),
    );
  }

  static void _showSubtitleSearch(BuildContext context) {
    final theme = Theme.of(context);
    final TextEditingController queryController = TextEditingController();

    final scrollController = ScrollController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.8,
          padding: EdgeInsets.only(
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer(
                  builder: (context, ref, child) {
                    final playerState = ref.read(playerControllerProvider);
                    final selectedLang = ref.read(subtitleLanguageProvider);

                    // Initial population and auto-search
                    if (queryController.text.isEmpty &&
                        playerState.playerTitle.isNotEmpty) {
                      queryController.text = playerState.playerTitle;
                      Future.microtask(() {
                        if (ref.read(subtitleSearchProvider) is! AsyncLoading) {
                          ref
                              .read(subtitleSearchProvider.notifier)
                              .search(
                                query: queryController.text,
                                imdbId: playerState.imdbId,
                                tmdbId: playerState.tmdbId,
                                language: selectedLang,
                              );
                        }
                      });
                    }

                    return TextField(
                      controller: queryController,
                      autofocus: true,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(
                          context,
                        )!.searchSubtitleNameHint,
                        prefixIcon: Icon(
                          Icons.search,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (queryController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  queryController.clear();
                                  final playerState = ref.read(
                                    playerControllerProvider,
                                  );
                                  final selectedLang = ref.read(
                                    subtitleLanguageProvider,
                                  );
                                  ref
                                      .read(subtitleSearchProvider.notifier)
                                      .search(
                                        query: "",
                                        imdbId: playerState.imdbId,
                                        tmdbId: playerState.tmdbId,
                                        language: selectedLang,
                                      );
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () {
                                final playerState = ref.read(
                                  playerControllerProvider,
                                );
                                final selectedLang = ref.read(
                                  subtitleLanguageProvider,
                                );
                                ref
                                    .read(subtitleSearchProvider.notifier)
                                    .search(
                                      query: queryController.text,
                                      imdbId: playerState.imdbId,
                                      tmdbId: playerState.tmdbId,
                                      language: selectedLang,
                                    );
                              },
                            ),
                          ],
                        ),
                      ),
                      onSubmitted: (val) {
                        final playerState = ref.read(playerControllerProvider);
                        final selectedLang = ref.read(subtitleLanguageProvider);
                        ref
                            .read(subtitleSearchProvider.notifier)
                            .search(
                              query: val,
                              imdbId: playerState.imdbId,
                              tmdbId: playerState.tmdbId,
                              language: selectedLang,
                            );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Language Selector (Targeted Consumer)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer(
                  builder: (context, ref, child) {
                    final selectedLang = ref.watch(subtitleLanguageProvider);
                    return DesktopScrollWrapper(
                      controller: scrollController,
                      isCompact: true,
                      child: SizedBox(
                        height: 40,
                        child: ListView.separated(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          scrollDirection: Axis.horizontal,
                          itemCount: subtitleLanguages.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final entry = subtitleLanguages.entries.elementAt(
                              index,
                            );
                            final isSelected = entry.value == selectedLang;
                            return ChoiceChip(
                              label: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  ref
                                      .read(subtitleLanguageProvider.notifier)
                                      .set(entry.value);
                                  final playerState = ref.read(
                                    playerControllerProvider,
                                  );
                                  ref
                                      .read(subtitleSearchProvider.notifier)
                                      .search(
                                        query: queryController.text,
                                        imdbId: playerState.imdbId,
                                        tmdbId: playerState.tmdbId,
                                        language: entry.value,
                                      );
                                }
                              },
                              selectedColor: theme.colorScheme.primary,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              Expanded(
                child: Consumer(
                  builder: (context, ref, child) {
                    final searchState = ref.watch(subtitleSearchProvider);
                    return searchState.when(
                      data: (results) {
                        if (results == null) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.subtitles_rounded,
                                  size: 64,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.enterSearchSubtitlePrompt,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final settings = ref
                            .watch(playerSettingsProvider)
                            .asData
                            ?.value;
                        final hasAnyCredentials =
                            settings != null &&
                            ((settings.osUsername.isNotEmpty &&
                                    settings.osPassword.isNotEmpty &&
                                    settings.osApiKey.isNotEmpty) ||
                                settings.subdlApiKey.isNotEmpty ||
                                settings.subsourceApiKey.isNotEmpty);

                        if (results.isEmpty) {
                          if (!hasAnyCredentials) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.vpn_key_rounded,
                                        size: 48,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Subtitle Accounts Not Configured',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Discovery requires your personal API keys for OpenSubtitles, SubDL, or SubSource.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    FilledButton.icon(
                                      onPressed: () {
                                        Navigator.pop(ctx); // Close search
                                        // The user is already in the player, we'll suggest they go to main settings
                                        // or we can try to show the specific dialogs here if they were available.
                                        // For now, let's provide a clear toast or action.
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Go to App Settings > Player > Subtitle Accounts to configure.',
                                            ),
                                            duration: Duration(seconds: 4),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.settings_outlined,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'View Settings Instructions',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.subtitles_off_rounded,
                                  size: 64,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.noSubtitleResults,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: results.length,
                          separatorBuilder: (_, _) => Divider(
                            color: theme.dividerColor.withValues(alpha: 0.05),
                            height: 1,
                            indent: 20,
                            endIndent: 20,
                          ),
                          itemBuilder: (context, index) {
                            final sub = results[index];
                            return _buildSubtitleCard(
                              context: context,
                              sub: sub,
                              onTap: () async {
                                ref.read(notificationServiceProvider).showInfo(
                                      AppLocalizations.of(context)!
                                          .downloadingApplyingSubtitle,
                                    );

                                final path = await ref
                                    .read(subtitleSearchProvider.notifier)
                                    .downloadAndPrepare(sub);

                                if (path != null) {
                                  ref
                                      .read(playerControllerProvider.notifier)
                                      .loadExternalSubtitleFile(filePath: path);
                                  if (context.mounted) Navigator.pop(ctx);
                                } else {
                                  if (context.mounted) {
                                    ref.read(notificationServiceProvider).showError(
                                          AppLocalizations.of(context)!
                                              .failedToDownloadSubtitle,
                                        );
                                  }
                                }
                              },
                            );
                          },
                        );
                      },
                      loading: () => _buildShimmerLoading(context),
                      error: (err, stack) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            AppLocalizations.of(context)!.failedToLoadSubtitles,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildShimmerLoading(BuildContext context) {
    final theme = Theme.of(context);
    return Shimmer.fromColors(
      baseColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
      highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.2),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 6,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 200,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 60,
                          height: 18,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 80,
                          height: 14,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSubtitleCard({
    required BuildContext context,
    required OnlineSubtitle sub,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final sourceColor = sub.source.toLowerCase().contains("subsource")
        ? Colors.blueAccent
        : (sub.source.toLowerCase().contains("opensubtitles")
              ? Colors.orangeAccent
              : theme.colorScheme.primary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sub.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: sourceColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    sub.language.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: sourceColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  sub.source,
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
                const Spacer(),
                if (sub.isHearingImpaired)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.hearing,
                      size: 16,
                      color: theme.hintColor.withValues(alpha: 0.5),
                    ),
                  ),
                Icon(
                  Icons.download_for_offline_outlined,
                  size: 20,
                  color: theme.hintColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

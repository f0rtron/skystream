import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/models/torrent_status.dart';
import '../../../../core/utils/layout_constants.dart';
import 'player_utils.dart';

class PlayerBottomSheets {
  static void showSourceSelection({
    required BuildContext context,
    required List<StreamResult>? streams,
    required StreamResult? currentStream,
    required Function(StreamResult) onStreamSelected,
  }) {
    if (streams == null || streams.isEmpty) return;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor:
          theme.bottomSheetTheme.modalBackgroundColor ??
          theme.dialogTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                child: Text(
                  "Select Source",
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
                        Icons.high_quality,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.iconTheme.color,
                      ),
                      title: Text(
                        s.quality,
                        style: TextStyle(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
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
        );
      },
    );
  }

  static void showContentSelection({
    required BuildContext context,
    required TorrentStatus? torrentStatus,
    required Function(int) onTorrentFileSelected,
  }) {
    if (torrentStatus == null) return;
    final files = torrentStatus.data['file_stats'] as List<dynamic>?;
    if (files == null || files.isEmpty) return;

    final theme = Theme.of(context);

    showModalBottomSheet(
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
                    "Torrent Content",
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
                      final path = file['path'] as String? ?? "Unknown";
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
    required Player player,
    required List<SubtitleFile>? externalSubtitles,
  }) {
    final audioTracks = player.state.tracks.audio;
    final subTracks = player.state.tracks.subtitle;
    final theme = Theme.of(context);

    showModalBottomSheet(
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
                  "Audio Tracks",
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Divider(color: theme.dividerColor),
                ...audioTracks.map((e) {
                  final langName = getLanguageName(e.language ?? e.id);
                  final label = e.title != null
                      ? "$langName (${e.title})"
                      : langName;
                  final isSelected = e == player.state.track.audio;

                  return ListTile(
                    title: Text(
                      label,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    onTap: () {
                      player.setAudioTrack(e);
                      Navigator.pop(ctx);
                    },
                    selected: isSelected,
                    selectedColor: theme.colorScheme.primary,
                    trailing: isSelected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                  );
                }),
                if (audioTracks.isEmpty)
                  Text(
                    "No audio tracks found",
                    style: TextStyle(color: theme.textTheme.bodySmall?.color),
                  ),

                const SizedBox(height: 24),
                Text(
                  "Subtitles",
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Divider(color: theme.dividerColor),
                ListTile(
                  title: Text(
                    "Off",
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                  onTap: () {
                    player.setSubtitleTrack(SubtitleTrack.no());
                    Navigator.pop(ctx);
                  },
                  selected: player.state.track.subtitle == SubtitleTrack.no(),
                  trailing: player.state.track.subtitle == SubtitleTrack.no()
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                ),
                // External Subtitles
                if (externalSubtitles != null)
                  ...externalSubtitles.map((s) {
                    final uriTrack = SubtitleTrack.uri(
                      s.url,
                      title: s.label,
                      language: s.lang,
                    );
                    // Check selection by ID (url) or loose match
                    final isSelected =
                        player.state.track.subtitle.id == s.url ||
                        player.state.track.subtitle.title == s.label;

                    return ListTile(
                      title: Text(
                        s.label,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      subtitle: s.lang != null
                          ? Text(
                              getLanguageName(s.lang!),
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 10,
                              ),
                            )
                          : null,
                      onTap: () {
                        player.setSubtitleTrack(uriTrack);
                        Navigator.pop(ctx);
                      },
                      selected: isSelected,
                      selectedColor: theme.colorScheme.primary,
                      trailing: isSelected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                    );
                  }),

                // Embedded Subtitles
                ...subTracks.map((e) {
                  final langName = getLanguageName(e.language ?? e.id);
                  final label = e.title != null
                      ? "$langName (${e.title})"
                      : langName;
                  final isSelected = e == player.state.track.subtitle;

                  return ListTile(
                    title: Text(
                      label,
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    onTap: () {
                      player.setSubtitleTrack(e);
                      Navigator.pop(ctx);
                    },
                    selected: isSelected,
                    selectedColor: theme.colorScheme.primary,
                    trailing: isSelected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../settings/presentation/player_settings_provider.dart';
import './player_controller.dart';

class PlayerSubtitleManager {
  late final PlayerController _controller;

  void initSubtitleManager(PlayerController controller) {
    _controller = controller;
  }

  Future<void> setSubtitleDelay(double seconds) async {
    if (!_controller.currentState.supportsSubtitleDelay) return;

    final native = _controller.player.platform;
    if (native is NativePlayer) {
      await native.setProperty('sub-delay', seconds.toString());
      _controller.updateState((s) => s.copyWith(subtitleDelay: seconds));
    }
  }

  Future<void> applySubtitleSettings(Ref ref) async {
    if (_controller.isDisposed ||
        !_controller.currentState.supportsSubtitleStyling) {
      return;
    }

    final native = _controller.player.platform;
    if (native is NativePlayer) {
      final settings =
          ref.read(playerSettingsProvider).asData?.value ??
          const PlayerSettings();

      await native.setProperty(
        'sub-font-size',
        settings.subtitleSize.toString(),
      );
      await native.setProperty(
        'sub-pos',
        settings.subtitlePosition.round().toString(),
      );

      String colorToMpvHex(int color, [double opacity = 1.0]) {
        final alpha = (opacity * 255).toInt().toRadixString(16).padLeft(2, '0');
        final rgb = color.toRadixString(16).padLeft(8, '0').substring(2);
        return '#$alpha$rgb';
      }

      await native.setProperty(
        'sub-color',
        colorToMpvHex(settings.subtitleColor),
      );
      if (settings.subtitleBackgroundColor != 0x00000000) {
        await native.setProperty(
          'sub-back-color',
          colorToMpvHex(
            settings.subtitleBackgroundColor,
            settings.subtitleBackgroundOpacity,
          ),
        );
      } else {
        await native.setProperty('sub-back-color', '#00000000');
      }
    }
  }

  List<SubtitleFile> effectiveExternalSubtitles(
    List<SubtitleFile>? streamSubs,
    List<SubtitleFile> userSubs,
  ) {
    final merged = <SubtitleFile>[];
    final seenUrls = <String>{};

    for (final SubtitleFile sub in <SubtitleFile>[...(streamSubs ?? []), ...userSubs]) {
      if (seenUrls.add(sub.url)) {
        merged.add(sub);
      }
    }
    return merged;
  }

  Future<void> loadExternalSubtitleFile({String? filePath}) async {
    if (_controller.currentState.useExoPlayer &&
        !_controller.currentState.supportsExternalSubtitleLoading) {
      return;
    }

    String? path = filePath;
    if (path == null) {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
      );
      if (result != null && result.files.single.path != null) {
        path = result.files.single.path!;
      }
    }

    if (path != null) {
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      final baseName = p.basenameWithoutExtension(path).trim();
      final label = baseName.isNotEmpty ? baseName : "External ($ext)";
      final newSub = SubtitleFile(url: path, label: label, lang: "und");

      if (!_controller.userAddedExternalSubtitles.any(
        (sub) => sub.url == newSub.url,
      )) {
        _controller.userAddedExternalSubtitles.add(newSub);
        _controller.updateState(
          (s) => s.copyWith(
            externalSubtitles: effectiveExternalSubtitles(
              s.currentStream?.subtitles,
              _controller.userAddedExternalSubtitles,
            ),
          ),
        );
      }

      if (_controller.currentState.useExoPlayer &&
          _controller.currentState.currentStream != null) {
        _controller.pendingVideoViewSubtitleIdsBeforeReload = _controller
            .videoViewController
            ?.mediaInfo
            .value
            ?.subtitleTracks
            .keys
            .toSet();
        _controller.selectNewestVideoViewSubtitleAfterReload =
            !(Platform.isMacOS || Platform.isIOS);

        await _controller.changeStream(
          _controller.currentState.currentStream!,
          resetPosition: false,
        );
        return;
      }

      await _controller.selectSubtitleTrack('external:${newSub.url}');
    }
  }
}

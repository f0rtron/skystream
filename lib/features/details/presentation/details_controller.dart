import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../../core/storage/library_repository.dart';
import '../../../../core/storage/history_repository.dart';
import '../../library/presentation/library_provider.dart';
import '../../library/presentation/history_provider.dart';
import 'playback_launcher.dart';
import '../../../core/services/download_service.dart';
import 'downloaded_file_provider.dart';

class DetailsState {
  final AsyncValue<MultimediaItem?> details;
  final Map<int, List<Episode>> seasonMap;
  final int selectedSeason;
  final bool isMovie;
  final MultimediaItem? item;
  final bool isLaunching;
  final Episode? targetEpisode;
  final bool isAscending;
  final int selectedRangeIndex;
  final DubStatus selectedDubStatus;

  const DetailsState({
    this.details = const AsyncLoading(),
    this.seasonMap = const {},
    this.selectedSeason = 1,
    this.isMovie = false,
    this.item,
    this.isLaunching = false,
    this.targetEpisode,
    this.isAscending = true,
    this.selectedRangeIndex = 0,
    this.selectedDubStatus = DubStatus.none,
  });

  DetailsState copyWith({
    AsyncValue<MultimediaItem?>? details,
    Map<int, List<Episode>>? seasonMap,
    int? selectedSeason,
    bool? isMovie,
    MultimediaItem? item,
    bool? isLaunching,
    Episode? targetEpisode,
    bool? isAscending,
    int? selectedRangeIndex,
    DubStatus? selectedDubStatus,
  }) {
    return DetailsState(
      details: details ?? this.details,
      seasonMap: seasonMap ?? this.seasonMap,
      selectedSeason: selectedSeason ?? this.selectedSeason,
      isMovie: isMovie ?? this.isMovie,
      item: item ?? this.item,
      isLaunching: isLaunching ?? this.isLaunching,
      targetEpisode: targetEpisode ?? this.targetEpisode,
      isAscending: isAscending ?? this.isAscending,
      selectedRangeIndex: selectedRangeIndex ?? this.selectedRangeIndex,
      selectedDubStatus: selectedDubStatus ?? this.selectedDubStatus,
    );
  }
}

class DetailsController extends Notifier<DetailsState> {
  final String itemUrl;
  DetailsController(this.itemUrl);

  @override
  DetailsState build() {
    ref.listen(activeDownloadsProvider, (prev, next) {
      final details = state.details.asData?.value;
      if (details == null) return;

      // Detect URLs that were active but are no longer active (completed/failed/canceled)
      final previousSet = prev ?? <String>{};
      final finishingUrls = previousSet.difference(next);

      if (finishingUrls.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[DetailsController] Re-checking status immediately after download finished: $finishingUrls',
          );
        }

        // Re-check specific item if its URL finished
        if (finishingUrls.contains(details.url)) {
          ref.read(downloadedFilesProvider.notifier).checkFile(details);
        }

        // Re-check episodes
        final episodes = details.episodes ?? [];
        for (final ep in episodes) {
          if (finishingUrls.contains(ep.url)) {
            ref
                .read(downloadedFilesProvider.notifier)
                .checkFile(details, episode: ep);
          }
        }
      }
    });

    ref.listen(watchHistoryProvider, (prev, next) {
      final details = state.details.asData?.value;
      if (details != null) {
        _processEpisodes(details.episodes, details, isInitial: false);
      }
    });
    return const DetailsState();
  }

  void init(MultimediaItem initialItem) {
    if (state.item == null) {
      state = state.copyWith(item: initialItem);
    }
  }

  void setSeason(int season) {
    if (state.seasonMap.containsKey(season)) {
      state = state.copyWith(selectedSeason: season, selectedRangeIndex: 0);
    }
  }

  void toggleSort() {
    state = state.copyWith(isAscending: !state.isAscending);
  }

  void setRangeIndex(int index) {
    state = state.copyWith(selectedRangeIndex: index);
  }

  void setDubStatus(DubStatus status) {
    state = state.copyWith(selectedDubStatus: status, selectedRangeIndex: 0);
  }

  void setLaunching(bool value) {
    if (state.isLaunching != value) {
      state = state.copyWith(isLaunching: value);
    }
  }

  /// Loads details for [item]. Auto-play is not handled here; the caller
  /// (e.g. DetailsScreen) should trigger play after load completes when
  /// [autoPlay] is true, using [handlePlayPress] with its BuildContext.
  Future<void> loadDetails(MultimediaItem item, {bool autoPlay = false}) async {
    if (state.details is AsyncData) return;

    state = state.copyWith(details: const AsyncLoading());

    final active = ref.read(activeProviderStateProvider);
    final manager = ref.read(extensionManagerProvider.notifier);

    try {
      if (item.provider == 'Local' ||
          item.provider == 'Torrent' ||
          item.provider == 'Remote') {
        var itemToUse = item;
        if (itemToUse.episodes == null || itemToUse.episodes!.isEmpty) {
          itemToUse = itemToUse.copyWith(
            episodes: [
              Episode(
                name: itemToUse.title,
                url: itemToUse.url,
                posterUrl: itemToUse.posterUrl,
              ),
            ],
          );
        }

        _processEpisodes(itemToUse.episodes, itemToUse);
        state = state.copyWith(details: AsyncData(itemToUse));
        return;
      }

      SkyStreamProvider? provider;
      if (item.provider != null) {
        try {
          provider = manager.getAllProviders().firstWhere(
            (p) => p.packageName == item.provider || p.name == item.provider,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('DetailsController.loadDetails: $e');
        }
      }

      provider ??= active;

      if (provider != null) {
        final fetchedItem = await provider.getDetails(item.url);
        if (!ref.mounted) return;

        final withProvider = fetchedItem.copyWith(
          provider: provider.packageName,
        );

        final sortedEpisodes = _processEpisodes(
          withProvider.episodes,
          withProvider,
          isInitial: true,
        );
        state = state.copyWith(
          details: AsyncData(withProvider.copyWith(episodes: sortedEpisodes)),
          item: withProvider.copyWith(episodes: sortedEpisodes),
        );
      } else {
        throw Exception("No provider selected or found for this item");
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = state.copyWith(details: AsyncError(e, st));
      }
    }
  }

  List<Episode>? _processEpisodes(
    List<Episode>? episodes,
    MultimediaItem contextItem, {
    bool isInitial = false,
  }) {
    if (episodes == null || episodes.isEmpty) {
      state = state.copyWith(
        isMovie: contextItem.contentType == MultimediaContentType.movie,
        seasonMap: {},
      );
      return episodes;
    }

    // Episodes are now automatically sorted by the MultimediaItem constructor

    // Determine isMovie based on contentType if available
    bool isMovie =
        contextItem.contentType == MultimediaContentType.movie ||
        contextItem.contentType == MultimediaContentType.livestream;

    // Fallback: If not explicitly movie/livestream, check episode count for legacy support
    if (!isMovie && episodes.length == 1) {
      isMovie = true;
    }

    if (isMovie) {
      state = state.copyWith(
        isMovie: true,
        seasonMap: {1: episodes},
        selectedSeason: 1,
      );
      return episodes;
    }

    final Map<int, List<Episode>> seasonMap = {};
    for (var ep in episodes) {
      final season = ep.season > 0 ? ep.season : 1;
      seasonMap.putIfAbsent(season, () => []).add(ep);
    }

    final sortedSeasons = seasonMap.keys.toList()..sort();
    int selectedSeason = sortedSeasons.isNotEmpty ? sortedSeasons.first : 1;
    Episode? targetEpisode;

    final historyRepo = ref.read(historyRepositoryProvider);

    // Find target episode and auto-select season
    final allEpisodes = episodes;
    final lastEpisodeUrl = historyRepo.getLastEpisodeUrl(contextItem.url);

    if (lastEpisodeUrl != null) {
      int lastIndex = allEpisodes.indexWhere((e) => e.url == lastEpisodeUrl);

      // Fallback: Match by season/episode numbers if URL matching fails
      if (lastIndex == -1) {
        final mainHistoryItem = ref
            .read(watchHistoryProvider)
            .firstWhereOrNull((h) => h.item.url == contextItem.url);
        if (mainHistoryItem != null &&
            mainHistoryItem.season != null &&
            mainHistoryItem.episode != null) {
          lastIndex = allEpisodes.indexWhere(
            (e) =>
                e.season == mainHistoryItem.season &&
                e.episode == mainHistoryItem.episode,
          );
        }
      }

      if (lastIndex != -1) {
        final matchedEp = allEpisodes[lastIndex];
        final pos = historyRepo.getEpisodePosition(
          matchedEp.url,
          mainUrl: contextItem.url,
          season: matchedEp.season,
          episode: matchedEp.episode,
        );
        final dur = historyRepo.getEpisodeDuration(
          matchedEp.url,
          mainUrl: contextItem.url,
          season: matchedEp.season,
          episode: matchedEp.episode,
        );
        final progress = dur > 0 ? pos / dur : 0;

        if (progress > 0.95) {
          if (lastIndex + 1 < allEpisodes.length) {
            targetEpisode = allEpisodes[lastIndex + 1];
          } else {
            targetEpisode = allEpisodes[lastIndex]; // Stay on last if finished
          }
        } else {
          targetEpisode = allEpisodes[lastIndex];
        }
      }
    }

    targetEpisode ??= allEpisodes.first;

    // Auto-select season based on target episode ONLY if initial load
    // or if we haven't manually switched seasons yet (using state.selectedSeason as 1 as a weak hint)
    if (isInitial && targetEpisode.season > 0) {
      selectedSeason = targetEpisode.season;
    } else {
      selectedSeason = state.selectedSeason;
    }

    // Default DubStatus for mixed series (No "All" anymore)
    DubStatus selectedDubStatus = state.selectedDubStatus;
    if (isInitial) {
      final hasSub = episodes.any((e) => e.dubStatus == DubStatus.subbed);
      final hasDub = episodes.any((e) => e.dubStatus == DubStatus.dubbed);
      if (hasSub && hasDub) {
        selectedDubStatus = DubStatus.subbed;
      }
    }

    state = state.copyWith(
      isMovie: false,
      seasonMap: seasonMap,
      selectedSeason: selectedSeason,
      targetEpisode: targetEpisode,
      selectedDubStatus: selectedDubStatus,
    );
    return episodes;
  }

  void toggleLibrary() {
    final item = state.details.value;
    if (item == null) return;

    final libraryRepo = ref.read(libraryRepositoryProvider);
    final wasInLibrary = libraryRepo.isInLibrary(item.url);

    if (wasInLibrary) {
      ref.read(libraryProvider.notifier).removeItem(item.url);
    } else {
      ref.read(libraryProvider.notifier).addItem(item);
    }
  }

  Future<void> handlePlayPress(
    BuildContext context,
    MultimediaItem details, {
    Episode? specificEpisode,
    String? overrideUrl,
  }) async {
    if (overrideUrl != null) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, overrideUrl, baseItem: details);
      return;
    }

    if (specificEpisode != null) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, specificEpisode.url, baseItem: details);
      return;
    }

    if (state.isMovie) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, details.episodes!.first.url, baseItem: details);
      return;
    }

    if (state.targetEpisode != null) {
      await ref
          .read(playbackLauncherProvider)
          .play(context, state.targetEpisode!.url, baseItem: details);
      return;
    }

    final firstSeason = state.seasonMap.keys.toList()..sort();
    if (firstSeason.isNotEmpty) {
      final ep = state.seasonMap[firstSeason.first]?.first;
      if (ep != null) {
        await ref
            .read(playbackLauncherProvider)
            .play(context, ep.url, baseItem: details);
      }
    }
  }
}

final detailsControllerProvider = NotifierProvider.autoDispose
    .family<DetailsController, DetailsState, String>(
      (url) => DetailsController(url),
    );

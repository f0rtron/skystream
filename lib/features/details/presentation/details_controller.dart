import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../core/extensions/base_provider.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../../core/storage/library_repository.dart';
import '../../../../core/storage/history_repository.dart';
import '../../library/presentation/library_provider.dart';
import '../../library/presentation/history_provider.dart';
import 'playback_launcher.dart';

class DetailsState {
  final AsyncValue<MultimediaItem?> details;
  final Map<int, List<Episode>> seasonMap;
  final int selectedSeason;
  final bool isMovie;
  final MultimediaItem? item;
  final bool isLaunching;

  const DetailsState({
    this.details = const AsyncLoading(),
    this.seasonMap = const {},
    this.selectedSeason = 1,
    this.isMovie = false,
    this.item,
    this.isLaunching = false,
  });

  DetailsState copyWith({
    AsyncValue<MultimediaItem?>? details,
    Map<int, List<Episode>>? seasonMap,
    int? selectedSeason,
    bool? isMovie,
    MultimediaItem? item,
    bool? isLaunching,
  }) {
    return DetailsState(
      details: details ?? this.details,
      seasonMap: seasonMap ?? this.seasonMap,
      selectedSeason: selectedSeason ?? this.selectedSeason,
      isMovie: isMovie ?? this.isMovie,
      item: item ?? this.item,
      isLaunching: isLaunching ?? this.isLaunching,
    );
  }
}

class DetailsController extends Notifier<DetailsState> {
  final String itemUrl;
  DetailsController(this.itemUrl);

  @override
  DetailsState build() {
    return const DetailsState();
  }

  void init(MultimediaItem initialItem) {
    if (state.item == null) {
      state = state.copyWith(item: initialItem);
    }
  }

  void setSeason(int season) {
    if (state.seasonMap.containsKey(season)) {
      state = state.copyWith(selectedSeason: season);
    }
  }

  void setLaunching(bool value) {
    if (state.isLaunching != value) {
      state = state.copyWith(isLaunching: value);
    }
  }

  /// Loads details for [item]. Auto-play is not handled here; the caller
  /// (e.g. DetailsScreen) should trigger play after load completes when
  /// [autoPlay] is true, using [handlePlayPress] with its BuildContext.
  Future<void> loadDetails(
    MultimediaItem item, {
    bool autoPlay = false,
  }) async {
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
            (p) => p.id == item.provider || p.name == item.provider,
          );
        } catch (e) {
          debugPrint('DetailsController.loadDetails: $e');
        }
      }

      provider ??= active;

      if (provider != null) {
        final fetchedItem = await provider.getDetails(item.url);
        final withProvider = fetchedItem.copyWith(provider: provider.id);

        _processEpisodes(withProvider.episodes, withProvider);
        state = state.copyWith(details: AsyncData(withProvider));
      } else {
        throw Exception("No provider selected or found for this item");
      }
    } catch (e, st) {
      state = state.copyWith(details: AsyncError(e, st));
    }
  }

  void _processEpisodes(List<Episode>? episodes, MultimediaItem contextItem) {
    // Determine isMovie based on contentType if available
    bool isMovie = contextItem.contentType == MultimediaContentType.movie ||
                   contextItem.contentType == MultimediaContentType.livestream;

    if (episodes == null || episodes.isEmpty) {
      state = state.copyWith(isMovie: isMovie, seasonMap: {});
      return;
    }

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
      return;
    }

    final Map<int, List<Episode>> seasonMap = {};
    for (var ep in episodes) {
      final season = ep.season > 0 ? ep.season : 1;
      seasonMap.putIfAbsent(season, () => []).add(ep);
    }

    final sortedSeasons = seasonMap.keys.toList()..sort();
    final selectedSeason = sortedSeasons.isNotEmpty ? sortedSeasons.first : 1;

    state = state.copyWith(
      isMovie: false,
      seasonMap: seasonMap,
      selectedSeason: selectedSeason,
    );
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

  void handlePlayPress(
    BuildContext context,
    MultimediaItem details, {
    Episode? specificEpisode,
  }) {
    if (specificEpisode != null) {
      ref
          .read(playbackLauncherProvider)
          .play(context, specificEpisode.url, baseItem: details);
      return;
    }

    if (state.isMovie) {
      ref
          .read(playbackLauncherProvider)
          .play(context, details.episodes!.first.url, baseItem: details);
      return;
    }

    final historyRepo = ref.read(historyRepositoryProvider);
    final lastEpisodeUrl = historyRepo.getLastEpisodeUrl(details.url);
    final position = historyRepo.getPosition(details.url);
    final historyHistory = ref.read(watchHistoryProvider);
    final duration = historyHistory
        .firstWhere(
          (i) => i.item.url == details.url,
          orElse: () => HistoryItem(
            item: details,
            position: 0,
            duration: 1,
            timestamp: 0,
          ),
        )
        .duration;

    final progress = duration > 0 ? (position / duration) * 100 : 0;

    if (lastEpisodeUrl != null) {
      final allEpisodes = <Episode>[];
      final sortedSeasons = state.seasonMap.keys.toList()..sort();
      for (var s in sortedSeasons) {
        allEpisodes.addAll(state.seasonMap[s]!);
      }

      final lastIndex = allEpisodes.indexWhere((e) => e.url == lastEpisodeUrl);
      if (lastIndex != -1) {
        if (progress > 95) {
          if (lastIndex + 1 < allEpisodes.length) {
            ref
                .read(playbackLauncherProvider)
                .play(
                  context,
                  allEpisodes[lastIndex + 1].url,
                  baseItem: details,
                );
            return;
          }
        }
        ref
            .read(playbackLauncherProvider)
            .play(context, lastEpisodeUrl, baseItem: details);
        return;
      }
    }

    final firstSeason = state.seasonMap.keys.toList()..sort();
    if (firstSeason.isNotEmpty) {
      final ep = state.seasonMap[firstSeason.first]?.first;
      if (ep != null) {
        ref
            .read(playbackLauncherProvider)
            .play(context, ep.url, baseItem: details);
      }
    }
  }
}

final detailsControllerProvider =
    NotifierProvider.autoDispose.family<DetailsController, DetailsState, String>(
      (url) => DetailsController(url),
    );

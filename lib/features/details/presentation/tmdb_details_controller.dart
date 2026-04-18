import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../discover/data/tmdb_provider.dart';
import '../../discover/data/language_provider.dart';

part 'tmdb_details_controller.g.dart';

class TmdbDetailsState {
  final int selectedSeason;
  final Future<Map<String, dynamic>?>? episodesFuture;

  const TmdbDetailsState({this.selectedSeason = 1, this.episodesFuture});

  TmdbDetailsState copyWith({
    int? selectedSeason,
    Future<Map<String, dynamic>?>? episodesFuture,
  }) {
    return TmdbDetailsState(
      selectedSeason: selectedSeason ?? this.selectedSeason,
      episodesFuture: episodesFuture ?? this.episodesFuture,
    );
  }
}

@riverpod
class TmdbDetailsController extends _$TmdbDetailsController {
  @override
  TmdbDetailsState build(int movieId) {
    // Watch language so we re-fetch if it changes
    final lang = ref.watch(languageProvider);

    // Start fetching season 1 by default
    final future = ref
        .read(tmdbServiceProvider)
        .getTvSeasonDetails(movieId, 1, language: lang);

    return TmdbDetailsState(selectedSeason: 1, episodesFuture: future);
  }

  Future<void> fetchEpisodes(int season) async {
    final lang = ref.read(languageProvider);

    final future = ref
        .read(tmdbServiceProvider)
        .getTvSeasonDetails(movieId, season, language: lang);

    state = state.copyWith(selectedSeason: season, episodesFuture: future);
  }
}

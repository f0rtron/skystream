import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../discover/data/tmdb_provider.dart';
import '../../discover/data/language_provider.dart';

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

class TmdbDetailsController extends Notifier<TmdbDetailsState> {
  final int movieId;

  TmdbDetailsController(this.movieId);

  @override
  TmdbDetailsState build() {
    return const TmdbDetailsState(selectedSeason: 1);
  }

  void fetchEpisodes(int season) async {
    final lang = ref.read(languageProvider);

    final future = ref
        .read(tmdbServiceProvider)
        .getTvSeasonDetails(movieId, season, language: lang);

    state = state.copyWith(selectedSeason: season, episodesFuture: future);
  }
}

final tmdbDetailsControllerProvider = NotifierProvider.autoDispose
    .family<TmdbDetailsController, TmdbDetailsState, int>(
      TmdbDetailsController.new,
    );

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/tmdb_provider.dart';
import '../../../../core/domain/entity/multimedia_item.dart';

class DiscoverSearchState {
  final List<MultimediaItem> suggestions;
  final List<MultimediaItem> results;
  final bool isLoading;
  final String query;
  final int page;
  final bool hasMore;

  const DiscoverSearchState({
    this.suggestions = const [],
    this.results = const [],
    this.isLoading = false,
    this.query = '',
    this.page = 1,
    this.hasMore = true,
  });

  DiscoverSearchState copyWith({
    List<MultimediaItem>? suggestions,
    List<MultimediaItem>? results,
    bool? isLoading,
    String? query,
    int? page,
    bool? hasMore,
  }) {
    return DiscoverSearchState(
      suggestions: suggestions ?? this.suggestions,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      query: query ?? this.query,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class DiscoverSearchController extends Notifier<DiscoverSearchState> {
  Timer? _debounce;

  @override
  DiscoverSearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
    });
    return const DiscoverSearchState();
  }

  void onQueryChanged(String query) {
    if (query == state.query) return;

    if (query.trim().isEmpty) {
      _debounce?.cancel();
      state = state.copyWith(query: query, suggestions: [], isLoading: false);
      return;
    }

    state = state.copyWith(query: query, isLoading: true);

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final tmdb = ref.read(tmdbServiceProvider);
        final results = await tmdb.multiSearch(query: query, language: 'en-US');

        if (state.query == query) {
          state = state.copyWith(
            suggestions: results.take(10).toList(),
            isLoading: false,
          );
        }
      } catch (e) {
        if (state.query == query) {
          state = state.copyWith(isLoading: false);
        }
      }
    });
  }

  Future<void> fetchResults(String query) async {
    if (query == state.query && state.results.isNotEmpty) return;

    state = state.copyWith(
      query: query,
      isLoading: true,
      page: 1,
      hasMore: true,
    );

    try {
      final tmdb = ref.read(tmdbServiceProvider);
      final results = await tmdb.multiSearch(
        query: query,
        language: 'en-US',
        page: 1,
      );

      if (state.query == query) {
        state = state.copyWith(
          results: results,
          isLoading: false,
          hasMore: results.isNotEmpty,
        );
      }
    } catch (e) {
      if (state.query == query) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final tmdb = ref.read(tmdbServiceProvider);
      final nextPage = state.page + 1;
      final results = await tmdb.multiSearch(
        query: state.query,
        language: 'en-US',
        page: nextPage,
      );

      if (results.isEmpty) {
        state = state.copyWith(hasMore: false, isLoading: false);
      } else {
        state = state.copyWith(
          results: [...state.results, ...results],
          page: nextPage,
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void clearSearch() {
    _debounce?.cancel();
    state = const DiscoverSearchState();
  }
}

final discoverSearchControllerProvider =
    NotifierProvider.autoDispose<DiscoverSearchController, DiscoverSearchState>(
      DiscoverSearchController.new,
    );

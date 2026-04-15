import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../discover/data/tmdb_provider.dart';

class ProviderSearchResult {
  final String providerId;
  final String providerName;
  final List<MultimediaItem> results;
  final String? error;

  ProviderSearchResult({
    required this.providerId,
    required this.providerName,
    required this.results,
    this.error,
  });
}

class SearchAggregateState {
  final List<ProviderSearchResult> results;
  final bool isLoading;

  const SearchAggregateState({this.results = const [], this.isLoading = false});
}

// ---------------------------------------------------------------------------
// Background isolate helper — runs title filtering off the main thread.
// ---------------------------------------------------------------------------
class _FilterParams {
  final List<MultimediaItem> items;
  final List<String> queryParts;
  const _FilterParams(this.items, this.queryParts);
}

List<MultimediaItem> _filterItems(_FilterParams params) {
  return params.items.where((item) {
    final titleLower = item.title.toLowerCase();
    final titleParts = titleLower
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    for (final qPart in params.queryParts) {
      bool foundPrefix = false;
      for (final tPart in titleParts) {
        if (tPart.startsWith(qPart)) {
          foundPrefix = true;
          break;
        }
      }
      if (!foundPrefix) return false;
    }
    return true;
  }).toList();
}

// ---------------------------------------------------------------------------
// Core search fan-out — emits incrementally as providers complete.
//
// Key performance improvements vs the old implementation:
//   1. Title filtering runs in a background isolate via compute().
//   2. Stream emissions are THROTTLED: at most one emit per 150ms regardless
//      of how many providers finish simultaneously. This collapses 32 rapid
//      completions into a handful of smooth rebuilds.
//   3. A guaranteed final emit fires when the very last provider finishes,
//      regardless of throttle state.
// ---------------------------------------------------------------------------
Stream<SearchAggregateState> searchAllProviders(
  String query,
  ExtensionManager manager, {
  required bool Function() isCancelled,
}) async* {
  final providers = manager.getAllProviders();

  if (query.isEmpty || providers.isEmpty) {
    yield const SearchAggregateState(results: [], isLoading: false);
    return;
  }

  yield const SearchAggregateState(results: [], isLoading: true);

  final results = <ProviderSearchResult>[];
  final queryLower = query.toLowerCase();
  final queryParts = queryLower.split(' ').where((s) => s.isNotEmpty).toList();

  final controller = StreamController<SearchAggregateState>();
  int activeFutures = providers.length;

  // --- Throttle state ---
  Timer? throttleTimer;
  bool pendingEmit = false;

  void doEmit() {
    if (controller.isClosed || isCancelled()) return;
    controller.add(
      SearchAggregateState(
        results: List.from(results),
        isLoading: activeFutures > 0,
      ),
    );
    pendingEmit = false;
  }

  void scheduleEmit({bool force = false}) {
    if (isCancelled() || controller.isClosed) return;

    if (force) {
      // Final emit — cancel throttle and emit immediately.
      throttleTimer?.cancel();
      throttleTimer = null;
      doEmit();
      return;
    }

    // Throttle: only schedule if not already scheduled.
    pendingEmit = true;
    throttleTimer ??= Timer(const Duration(milliseconds: 150), () {
      throttleTimer = null;
      if (pendingEmit) doEmit();
    });
  }

  for (final provider in providers) {
    Future(() async {
      if (isCancelled()) return;

      try {
        final rawResults = await provider.search(query);
        if (isCancelled()) return;

        final providerItems = rawResults
            .map(
              (item) => MultimediaItem(
                title: item.title,
                url: item.url,
                posterUrl: item.posterUrl,
                bannerUrl: item.bannerUrl,
                description: item.description,
                contentType: item.contentType,
                episodes: item.episodes,
                provider: provider.packageName,
              ),
            )
            .toList();

        // Run filtering in a background isolate so it doesn't block the UI.
        final filtered = await compute(
          _filterItems,
          _FilterParams(providerItems, queryParts),
        );

        if (isCancelled()) return;

        results.add(
          ProviderSearchResult(
            providerId: provider.packageName,
            providerName: provider.name,
            results: filtered,
          ),
        );
      } catch (e) {
        if (isCancelled()) return;
        results.add(
          ProviderSearchResult(
            providerId: provider.packageName,
            providerName: provider.name,
            results: [],
            error: e.toString(),
          ),
        );
      } finally {
        activeFutures--;
        final isLast = activeFutures == 0;
        // Force an immediate emit for the last provider; throttle all others.
        scheduleEmit(force: isLast);
        if (isLast && !controller.isClosed) {
          // Give the final emit a microtask to land before we close.
          Future.microtask(() {
            if (!controller.isClosed) controller.close();
          });
        }
      }
    });
  }

  yield* controller.stream;
}

// ---------------------------------------------------------------------------
// State for the committed (submitted) search query.
// ---------------------------------------------------------------------------
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

// ---------------------------------------------------------------------------
// Incremental search results — delegates to searchAllProviders().
//
// NOT autoDispose: keeps the stream alive when the user switches tabs so
// results aren't thrown away and the search doesn't re-run on return.
// The stream naturally restarts whenever searchQueryProvider changes.
// ---------------------------------------------------------------------------
final searchResultsProvider = StreamProvider<SearchAggregateState>((ref) {
  final query = ref.watch(searchQueryProvider);
  ref.watch(extensionManagerProvider);
  final manager = ref.read(extensionManagerProvider.notifier);

  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  return searchAllProviders(query, manager, isCancelled: () => cancelled);
});

class SearchSuggestionState {
  final List<String> suggestions;
  final bool isLoading;
  final String query;

  const SearchSuggestionState({
    this.suggestions = const [],
    this.isLoading = false,
    this.query = '',
  });

  SearchSuggestionState copyWith({
    List<String>? suggestions,
    bool? isLoading,
    String? query,
  }) {
    return SearchSuggestionState(
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
      query: query ?? this.query,
    );
  }
}

class SearchSuggestionController extends Notifier<SearchSuggestionState> {
  Timer? _debounce;

  @override
  SearchSuggestionState build() {
    ref.onDispose(() {
      _debounce?.cancel();
    });
    return const SearchSuggestionState();
  }

  void onQueryChanged(String query) {
    if (query == state.query) return;

    final trimmed = query.trim();
    if (trimmed.length < 2) {
      _debounce?.cancel();
      state = state.copyWith(
        query: query,
        suggestions: const [],
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(query: query, isLoading: true);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final tmdb = ref.read(tmdbServiceProvider);
        final suggestions = await tmdb.getSuggestions(
          query: query,
          language: 'en-US',
        );
        if (state.query == query) {
          state = state.copyWith(suggestions: suggestions, isLoading: false);
        }
      } catch (_) {
        if (state.query == query) {
          state = state.copyWith(suggestions: const [], isLoading: false);
        }
      }
    });
  }

  void clear() {
    _debounce?.cancel();
    state = const SearchSuggestionState();
  }
}

final searchSuggestionControllerProvider =
    NotifierProvider.autoDispose<
      SearchSuggestionController,
      SearchSuggestionState
    >(SearchSuggestionController.new);

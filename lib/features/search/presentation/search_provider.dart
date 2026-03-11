import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/domain/entity/multimedia_item.dart';

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

/// Shared search orchestration — the single source of truth for provider
/// fan-out, result mapping, and prefix filtering. Returns results
/// incrementally as each provider completes natively concurrently.
///
/// Lifecycle: The [StreamController] is closed when the stream subscription
/// is cancelled (e.g. ref.onDispose in the provider) via [onControllerCreated].
/// In-flight futures check [isCancelled] and avoid adding to a closed controller.
Stream<SearchAggregateState> searchAllProviders(
  String query,
  ExtensionManager manager, {
  required bool Function() isCancelled,
  void Function(StreamController<SearchAggregateState> controller)?
      onControllerCreated,
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
  onControllerCreated?.call(controller);
  int activeFutures = providers.length;

  for (final provider in providers) {
    Future(() async {
      if (isCancelled()) return;

      try {
        final rawResults = await provider.search(query);
        if (isCancelled()) return;

        final providerResults = rawResults
            .map(
              (item) => MultimediaItem(
                title: item.title,
                url: item.url,
                posterUrl: item.posterUrl,
                bannerUrl: item.bannerUrl,
                description: item.description,
                isFolder: item.isFolder,
                episodes: item.episodes,
                provider: provider.id,
              ),
            )
            .toList();

        final filtered = providerResults.where((item) {
          final titleLower = item.title.toLowerCase();
          final titleParts = titleLower
              .split(' ')
              .where((s) => s.isNotEmpty)
              .toList();

          for (final qPart in queryParts) {
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

        results.add(
          ProviderSearchResult(
            providerId: provider.id,
            providerName: provider.name,
            results: filtered,
          ),
        );
      } catch (e) {
        if (isCancelled()) return;

        results.add(
          ProviderSearchResult(
            providerId: provider.id,
            providerName: provider.name,
            results: [],
            error: e.toString(),
          ),
        );
      } finally {
        activeFutures--;
        if (!controller.isClosed && !isCancelled()) {
          controller.add(
            SearchAggregateState(
              results: List.from(results),
              isLoading: activeFutures > 0,
            ),
          );
        }
        if (activeFutures == 0 && !controller.isClosed) {
          controller.close();
        }
      }
    }); // Spawns Future concurrently
  }

  yield* controller.stream;
}

// State for the search query
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

// Incremental search results — delegates to shared searchAllProviders()
final searchResultsProvider = StreamProvider.autoDispose<SearchAggregateState>((
  ref,
) {
  final query = ref.watch(searchQueryProvider);
  ref.watch(extensionManagerProvider); // trigger sub when plugins change
  final manager = ref.read(extensionManagerProvider.notifier);

  var cancelled = false;
  StreamController<SearchAggregateState>? searchController;
  ref.onDispose(() {
    cancelled = true;
    searchController?.close();
  });

  return searchAllProviders(
    query,
    manager,
    isCancelled: () => cancelled,
    onControllerCreated: (c) => searchController = c,
  );
});

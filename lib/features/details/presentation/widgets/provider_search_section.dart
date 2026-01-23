import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import '../details_screen.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';

// Provider Result wrapper
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

// Localized Search Provider (Family to allow specific queries per instance if needed)
final providerSearchProvider = FutureProvider.family
    .autoDispose<List<ProviderSearchResult>, String>((ref, query) async {
      if (query.length < 2) return [];

      final manager = ref.read(extensionManagerProvider.notifier);
      final providers = manager.getAllProviders();

      // Parallel execution of all provider searches
      final futures = providers.map((provider) async {
        try {
          final rawResults = await provider.search(query);

          // Map to MultimediaItem & inject provider ID
          final results = rawResults.map((item) {
            return MultimediaItem(
              title: item.title,
              url: item.url,
              posterUrl: item.posterUrl,
              bannerUrl: item.bannerUrl,
              description: item.description,
              isFolder: item.isFolder,
              episodes: item.episodes,
              provider: provider.id,
            );
          }).toList();

          // Flexible filtering (Prefix match usually works best, but sometimes exact)
          final filtered = results.where((item) {
            final titleLower = item.title.toLowerCase();
            final queryLower = query.toLowerCase();
            // Allow partial matches
            return titleLower.contains(queryLower);
          }).toList();

          return ProviderSearchResult(
            providerId: provider.id,
            providerName: provider.name,
            results: filtered,
          );
        } catch (e) {
          return ProviderSearchResult(
            providerId: provider.id,
            providerName: provider.name,
            results: [],
            error: e.toString(),
          );
        }
      }).toList();

      return await Future.wait(futures);
    });

class ProviderSearchSection extends ConsumerStatefulWidget {
  final String query;

  const ProviderSearchSection({super.key, required this.query});

  @override
  ConsumerState<ProviderSearchSection> createState() =>
      _ProviderSearchSectionState();
}

class _ProviderSearchSectionState extends ConsumerState<ProviderSearchSection> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.isEmpty) return const SizedBox.shrink();

    final plugins = ref.watch(extensionManagerProvider);
    final searchAsync = ref.watch(providerSearchProvider(widget.query));

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(
                  Icons.extension,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  "Available Sources (Beta)",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (plugins.isEmpty)
            Container(
              height: 140,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "No plugins installed",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            )
          else
            searchAsync.when(
              data: (results) {
                // Flatten results into a single list of "Cards"
                // Each card needs: Image, Title, Provider Name
                final allItems = <Map<String, dynamic>>[];
                for (var pResult in results) {
                  for (var item in pResult.results) {
                    allItems.add({
                      'item': item,
                      'providerName': pResult.providerName,
                    });
                  }
                }

                if (allItems.isEmpty) {
                  return Container(
                    height: 140,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "No streams found on installed plugins.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  );
                }

                return SizedBox(
                  height: 140, // Height for the horizontal list
                  child: DesktopScrollWrapper(
                    controller: _scrollController,
                    child: ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: allItems.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final data = allItems[index];
                        final item = data['item'] as MultimediaItem;
                        final providerName = data['providerName'] as String;

                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => DetailsScreen(item: item),
                              ),
                            );
                          },
                          child: Container(
                            width: 220, // Wide card for thumbnail + text
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.3),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Row(
                              children: [
                                // Image
                                SizedBox(
                                  width: 90,
                                  height: double.infinity,
                                  child: item.posterUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: item.posterUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              Container(
                                                color: Colors.grey[800],
                                              ),
                                        )
                                      : Container(
                                          color: Colors.grey[800],
                                          child: const Center(
                                            child: Icon(Icons.movie, size: 24),
                                          ),
                                        ),
                                ),
                                // Details
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            providerName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("Error searching providers: $err"),
              ),
            ),
        ],
      ),
    );
  }
}

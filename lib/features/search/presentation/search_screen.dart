import 'package:skystream/core/providers/device_info_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'search_provider.dart';
import 'widgets/search_result_section.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final device = ref.watch(deviceProfileProvider).asData?.value;
    final isLarge = device?.isLargeScreen ?? false;

    // Matches HomeSection card size
    final double width = isLarge ? 170 : 110;
    final double posterHeight = width * 1.5;
    final double totalHeight = posterHeight + 100;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 48,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: false,
              style: const TextStyle(fontSize: 16),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: 'Search movies, series...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                // fillColor inherited from AppTheme (0xFF22222E)
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          ref.read(searchQueryProvider.notifier).set('');
                        },
                      )
                    : null,
              ),
              onChanged: (val) {
                ref.read(searchQueryProvider.notifier).set(val);
              },
            ),
          ),
        ),
      ),
      body: searchResultsAsync.when(
        data: (providerResults) {
          // Flatten to check for any results
          final allResults = providerResults.expand((e) => e.results).toList();

          if (allResults.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: providerResults.length,
            itemBuilder: (context, index) {
              final pResult = providerResults[index];
              if (pResult.results.isEmpty) return const SizedBox.shrink();

              return SearchResultSection(
                providerName: pResult.providerName,
                providerId: pResult.providerId,
                results: pResult.results,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final query = ref.read(searchQueryProvider);
    if (query.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_rounded,
              size: 64,
              color: Theme.of(context).dividerColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Search for your favorite content',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }
    return const Center(child: Text('No results found.'));
  }
}

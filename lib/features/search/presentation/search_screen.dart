import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/layout_constants.dart';
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
  Timer? _debounce; // P7: Debounce timer to prevent excessive API calls

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel(); // P7: Cancel debounce timer
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 48,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                return TextField(
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
                    suffixIcon: value.text.isNotEmpty
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
                    // P7: Debounce search to avoid triggering on every keystroke
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      ref.read(searchQueryProvider.notifier).set(val);
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
      body: searchResultsAsync.when(
        data: (state) {
          // Flatten to check for any results
          final allResults = state.results.expand((e) => e.results).toList();

          if (allResults.isEmpty && !state.isLoading) {
            return _buildEmptyState(context);
          } else if (allResults.isEmpty && state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: LayoutConstants.spacingMd),
            itemCount: state.results.length,
            itemBuilder: (context, index) {
              final pResult = state.results[index];
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
    final query = ref.watch(searchQueryProvider);
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_rounded,
              size: 64,
              color: Theme.of(context).dividerColor,
            ),
            const SizedBox(height: LayoutConstants.spacingMd),
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

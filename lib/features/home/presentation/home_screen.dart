import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'home_provider.dart';
import 'package:skystream/features/home/presentation/widgets/continue_watching_section.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import '../../discover/presentation/widgets/discover_carousel.dart';
import '../../discover/presentation/widgets/media_horizontal_list.dart';
import '../../discover/presentation/view_all_screen.dart';

import 'package:flutter/rendering.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/router/app_router.dart';
import '../../../core/models/tmdb_item.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isScrolledNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isFabExtended = ValueNotifier<bool>(true);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // Status Bar Logic
    final isScrolled = _scrollController.offset > 200;
    if (isScrolled != _isScrolledNotifier.value) {
      _isScrolledNotifier.value = isScrolled;
    }

    // FAB Logic — uses ValueNotifier to avoid full-tree setState rebuild
    if (_scrollController.position.userScrollDirection ==
            ScrollDirection.reverse &&
        _isFabExtended.value) {
      _isFabExtended.value = false;
    } else if (_scrollController.position.userScrollDirection ==
            ScrollDirection.forward &&
        !_isFabExtended.value) {
      _isFabExtended.value = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isScrolledNotifier.dispose();
    _isFabExtended.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final homeDataAsync = ref.watch(homeDataProvider);
    final history = ref.watch(watchHistoryProvider);

    return ValueListenableBuilder<bool>(
      valueListenable: _isScrolledNotifier,
      builder: (context, isScrolled, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final overlayStyle = isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            systemOverlayStyle: overlayStyle,
            forceMaterialTransparency: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color: isScrolled
                  ? Theme.of(context).scaffoldBackgroundColor
                  : Colors.transparent,
            ),
            title: const Text('SkyStream'),
          ),
          floatingActionButton: ValueListenableBuilder<bool>(
            valueListenable: _isFabExtended,
            builder: (context, isFabExtended, _) {
              return Material(
                elevation: 4,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).dialogTheme.backgroundColor
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showProviderSelector(context, ref),
                  child: Container(
                    height: 56,
                    constraints: const BoxConstraints(minWidth: 56),
                    padding: EdgeInsets.symmetric(
                      horizontal: isFabExtended ? 16 : 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.extension,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: SizedBox(
                            width: isFabExtended ? null : 0,
                            child: isFabExtended
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Builder(
                                      builder: (context) {
                                        final active = ref.watch(
                                          activeProviderStateProvider,
                                        );
                                        final isDebug =
                                            active?.isDebug ?? false;
                                        return Row(
                                          children: [
                                            Text(
                                              active?.name ?? 'None',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.fade,
                                              softWrap: false,
                                            ),
                                            if (isDebug) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'DEBUG',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          body: _buildBody(context, homeDataAsync, history),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<Map<String, List<dynamic>>> homeDataAsync,
    List<dynamic> history,
  ) {
    // Handling initial loading
    final isResolving = ref.watch(providerResolutionLoadingProvider);
    if (isResolving) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    // No active provider selected
    if (ref.watch(activeProviderStateProvider) == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.extension_off_rounded,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              "Select a provider to start watching",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text("Tap the extension icon in the corner"),
          ],
        ),
      );
    }

    // Main content
    return homeDataAsync.when(
      data: (data) {
        final filteredEntries = data.entries
            .where((e) => e.key != 'Trending')
            .toList();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(homeDataProvider.future),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Carousel
              if (data.containsKey('Trending'))
                SliverToBoxAdapter(
                  child: DiscoverCarousel(
                    movies: data['Trending']!
                        .take(7)
                        .cast<MultimediaItem>()
                        .map(_toTmdbItem)
                        .toList(),
                    scrollController: _scrollController,
                    onTap: (tmdbItem) {
                      final item = tmdbItem.sourceItem;
                      if (item != null) {
                        context.push('/details', extra: DetailsRouteExtra(item: item));
                      }
                    },
                  ),
                )
              else if (data.isNotEmpty)
                SliverToBoxAdapter(
                  child: DiscoverCarousel(
                    movies: data.values.first
                        .take(7)
                        .cast<MultimediaItem>()
                        .map(_toTmdbItem)
                        .toList(),
                    scrollController: _scrollController,
                    onTap: (tmdbItem) {
                      final item = tmdbItem.sourceItem;
                      if (item != null) {
                        context.push('/details', extra: DetailsRouteExtra(item: item));
                      }
                    },
                  ),
                ),

              // Continue Watching
              if (history.isNotEmpty)
                SliverToBoxAdapter(
                  child: ContinueWatchingSection(
                    title: 'Continue Watching',
                    items: history.cast<HistoryItem>(),
                  ),
                ),

              // Category sections — lazily built
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= filteredEntries.length) return null;
                    final entry = filteredEntries[index];
                    return RepaintBoundary(
                      child: MediaHorizontalList(
                        title: entry.key,
                        mediaList: entry.value
                            .cast<MultimediaItem>()
                            .map(_toTmdbItem)
                            .toList(),
                        category: ViewAllCategory.trending,
                        showViewAll: false,
                        onTap: (tmdbItem) {
                          final item = tmdbItem.sourceItem;
                          if (item != null) {
                            context.push('/details', extra: DetailsRouteExtra(item: item));
                          }
                        },
                        heroTagPrefix: 'home',
                      ),
                    );
                  },
                  childCount: filteredEntries.length,
                ),
              ),

              // Bottom padding for FAB
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => _buildErrorState(context, err.toString(), ref),
    );
  }

  TmdbItem _toTmdbItem(MultimediaItem item) {
    return TmdbItem(
      id: item.url.hashCode,
      title: item.title,
      posterPath: item.posterUrl,
      mediaType: 'movie',
      releaseDate: '',
      voteAverage: 0.0,
      overview: item.description ?? '',
      sourceItem: item,
    );
  }

  Widget _buildErrorState(BuildContext context, String error, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            const Text(
              'Site Not Reachable',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please try accessing the site with a VPN or checking your internet connection.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                'Error Details: $error',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.refresh(homeDataProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _showProviderSelector(BuildContext context, WidgetRef ref) {
    final extManager = ref.read(extensionManagerProvider.notifier);
    final activeProvider = ref.read(activeProviderStateProvider);
    final providers = extManager.getAllProviders();

    // Find index of selected provider for auto-scroll
    int selectedIndex = 0; // 0 is "None"
    if (activeProvider != null) {
      for (int i = 0; i < providers.length; i++) {
        if (providers[i].id == activeProvider.id) {
          selectedIndex = i + 1; // +1 because "None" is at index 0
          break;
        }
      }
    }

    final scrollController = ScrollController();
    showDialog(
      context: context,
      builder: (context) {
        // Auto-scroll to selected item after dialog opens
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients && selectedIndex > 0) {
            // Approximate height of each RadioListTile
            const itemHeight = 56.0;
            final targetOffset = (selectedIndex * itemHeight) - 100;
            scrollController.animateTo(
              targetOffset.clamp(
                0.0,
                scrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        return AlertDialog(
          title: const Text('Select Provider'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: RadioGroup<String?>(
              groupValue: activeProvider?.id,
              onChanged: (val) {
                if (val == null) {
                  ref.read(activeProviderStateProvider.notifier).set(null);
                } else {
                  final selected = providers.firstWhere((p) => p.id == val);
                  ref.read(activeProviderStateProvider.notifier).set(selected);
                }
                Navigator.pop(context);
                // ignore: unused_result
                ref.refresh(homeDataProvider);
              },
              child: SizedBox(
                width: 400, // Fixed width for better appearance on desktop
                child: ListView.builder(
                  controller: scrollController,
                  shrinkWrap: true,
                  itemCount: providers.length + 1, // +1 for "None"
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // "None" option
                      return const RadioListTile<String?>(
                        title: Text('None'),
                        value: null,
                      );
                    }

                    final p = providers[index - 1];
                    final isDebug = p.isDebug;
                    return RadioListTile<String?>(
                      title: Row(
                        children: [
                          Text(p.name),
                          if (isDebug) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'DEBUG',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      value: p.id,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) => scrollController.dispose());
  }
}

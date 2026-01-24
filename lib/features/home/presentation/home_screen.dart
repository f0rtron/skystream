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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isScrolledNotifier = ValueNotifier<bool>(false);
  bool _isFabExtended = true;

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

    // FAB Logic
    if (_scrollController.position.userScrollDirection ==
            ScrollDirection.reverse &&
        _isFabExtended) {
      setState(() => _isFabExtended = false);
    } else if (_scrollController.position.userScrollDirection ==
            ScrollDirection.forward &&
        !_isFabExtended) {
      setState(() => _isFabExtended = true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isScrolledNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            flexibleSpace: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, child) {
                double offset = 0;
                if (_scrollController.hasClients) {
                  offset = _scrollController.offset * 0.8;
                }
                // Transition to base background color over 300 pixels
                final opacity = (offset / 300).clamp(0.0, 1.0);

                return Opacity(
                  opacity: opacity,
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                );
              },
            ),
            title: const Text('SkyStream'),
          ),
          floatingActionButton: Material(
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
                  horizontal: _isFabExtended ? 16 : 0,
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
                        width: _isFabExtended ? null : 0,
                        child: _isFabExtended
                            ? Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Builder(
                                  builder: (context) {
                                    final active = ref.watch(
                                      activeProviderStateProvider,
                                    );
                                    final isDebug = active?.isDebug ?? false;
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
                                            padding: const EdgeInsets.symmetric(
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
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
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
        if (data.containsKey('Error')) {
          final errorItem = data['Error']!.first as MultimediaItem;
          return _buildErrorState(
            context,
            errorItem.description ?? "Unknown Error",
            ref,
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.refresh(homeDataProvider.future),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 80), // Add padding for FAB
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.containsKey('Trending')) ...[
                  DiscoverCarousel(
                    movies: data['Trending']!
                        .take(7)
                        .cast<MultimediaItem>()
                        .map(_mapItemToMap)
                        .toList(),
                    scrollController: _scrollController,
                    onTap: (movieMap) {
                      final item = movieMap['_originalItem'] as MultimediaItem;
                      context.push('/details', extra: item);
                    },
                  ),
                ] else if (data.isNotEmpty) ...[
                  DiscoverCarousel(
                    movies: data.values.first
                        .take(7)
                        .cast<MultimediaItem>()
                        .map(_mapItemToMap)
                        .toList(),
                    scrollController: _scrollController,
                    onTap: (movieMap) {
                      final item = movieMap['_originalItem'] as MultimediaItem;
                      context.push('/details', extra: item);
                    },
                  ),
                ],

                if (history.isNotEmpty) ...[
                  ContinueWatchingSection(
                    title: 'Continue Watching',
                    items: history.cast<HistoryItem>(),
                  ),
                ],

                ...data.entries.where((e) => e.key != 'Trending').map((entry) {
                  return MediaHorizontalList(
                    title: entry.key,
                    mediaList: entry.value
                        .cast<MultimediaItem>()
                        .map(_mapItemToMap)
                        .toList(),
                    category: ViewAllCategory.trending, // Placeholder
                    showViewAll:
                        false, // Provider sections don't support view all yet
                    onTap: (movieMap) {
                      final item = movieMap['_originalItem'] as MultimediaItem;
                      context.push('/details', extra: item);
                    },
                    heroTagPrefix: 'home',
                  );
                }),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => _buildErrorState(context, err.toString(), ref),
    );
  }

  Map<String, dynamic> _mapItemToMap(MultimediaItem item) {
    return {
      'id': item.url.hashCode, // Fake ID
      'title': item.title,
      'name': item.title, // For TV compatibility
      'poster_path': item.posterUrl,
      'backdrop_path': item.bannerUrl ?? item.posterUrl,
      'overview': item.description,
      // 'media_type': 'movie', // Removed default assignment
      '_originalItem': item, // Store original item for navigation
    };
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Provider'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String?>(
              title: const Text('None'),
              value: null,
              groupValue: activeProvider?.id,
              onChanged: (val) {
                ref.read(activeProviderStateProvider.notifier).set(null);
                Navigator.pop(context);
                ref.refresh(homeDataProvider);
              },
            ),
            ...extManager.getAllProviders().map((p) {
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
                groupValue: activeProvider?.id,
                onChanged: (val) {
                  ref.read(activeProviderStateProvider.notifier).set(p);
                  Navigator.pop(context);
                  ref.refresh(homeDataProvider);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

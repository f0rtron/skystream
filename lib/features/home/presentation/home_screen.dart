import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'home_provider.dart';
import 'package:skystream/features/home/presentation/widgets/continue_watching_section.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import '../../settings/presentation/general_settings_provider.dart';
import '../../discover/presentation/widgets/discover_carousel.dart';
import '../../discover/presentation/widgets/media_horizontal_list.dart';
import '../../discover/presentation/view_all_screen.dart';
import '../../../shared/widgets/desktop_scroll_wrapper.dart';

import 'package:flutter/rendering.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/core/extensions/base_provider.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/router/app_router.dart';
import '../../../core/utils/error_messages.dart';

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
    final generalSettings = ref.watch(generalSettingsProvider);
    final l10n = AppLocalizations.of(context)!;

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
        flexibleSpace: ValueListenableBuilder<bool>(
          valueListenable: _isScrolledNotifier,
          builder: (context, isScrolled, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color: isScrolled
                  ? Theme.of(context).scaffoldBackgroundColor
                  : Colors.transparent,
            );
          },
        ),
        title: Text(l10n.appTitle),
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
                                    final l10n = AppLocalizations.of(context)!;
                                    final active = ref.watch(
                                      activeProviderStateProvider,
                                    );
                                    final isDebug = active?.isDebug ?? false;
                                    return Row(
                                      children: [
                                        Text(
                                          active?.name ?? l10n.none,
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
                                            child: Text(
                                              l10n.debug,
                                              style: const TextStyle(
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
      body: _buildBody(
        context,
        homeDataAsync,
        history,
        generalSettings.watchHistoryEnabled,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<Map<String, List<MultimediaItem>>> homeDataAsync,
    List<dynamic> history,
    bool watchHistoryEnabled,
  ) {
    final l10n = AppLocalizations.of(context)!;
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
            Text(
              l10n.selectProviderToStart,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(l10n.tapExtensionIcon),
          ],
        ),
      );
    }

    // Main content
    return homeDataAsync.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: false,
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
                    movies: data['Trending']!.take(7).toList(),
                    scrollController: _scrollController,
                    onTap: (item) {
                      context.push(
                        '/details',
                        extra: DetailsRouteExtra(item: item),
                      );
                    },
                  ),
                )
              else if (data.isNotEmpty)
                SliverToBoxAdapter(
                  child: DiscoverCarousel(
                    movies: data.values.first.take(7).toList(),
                    scrollController: _scrollController,
                    onTap: (item) {
                      context.push(
                        '/details',
                        extra: DetailsRouteExtra(item: item),
                      );
                    },
                  ),
                ),

              // Continue Watching
              if (watchHistoryEnabled && history.isNotEmpty)
                SliverToBoxAdapter(
                  child: ContinueWatchingSection(
                    title: l10n.continueWatching,
                    items: history.cast<HistoryItem>(),
                  ),
                ),

              // Category sections — lazily built
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index >= filteredEntries.length) return null;
                  final entry = filteredEntries[index];
                  return MediaHorizontalList(
                    title: entry.key,
                    mediaList: entry.value,
                    category: ViewAllCategory.trending,
                    showViewAll: false,
                    onTap: (item) {
                      context.push(
                        '/details',
                        extra: DetailsRouteExtra(item: item),
                      );
                    },
                    heroTagPrefix: 'home',
                  );
                }, childCount: filteredEntries.length),
              ),

              // Bottom padding for FAB
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => _buildErrorState(context, AppErrorMessages.from(err, l10n), ref),
    );
  }

  Widget _buildErrorState(BuildContext context, String error, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bool isOffline = error == l10n.noInternetError;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isOffline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              isOffline ? l10n.noInternetConnection : l10n.siteNotReachable,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isOffline
                  ? l10n.checkConnectionOrDownloads
                  : l10n.tryVpnOrConnection,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!isOffline) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  l10n.errorDetails(error),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => ref.invalidate(homeDataProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.retry),
                ),
                ElevatedButton.icon(
                  onPressed: () => context.push('/library'),
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: Text(l10n.goToDownloads),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showProviderSelector(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final extManager = ref.read(extensionManagerProvider.notifier);
    final activeProvider = ref.read(activeProviderStateProvider);
    final providers = List<SkyStreamProvider>.from(extManager.getAllProviders())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final scrollController = ScrollController();
    final chipsScrollController = ScrollController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.selectProvider),
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Filter Chips
                Consumer(
                  builder: (context, ref, _) {
                    final currentFilter = ref.watch(homeFilterProvider);
                    return DesktopScrollWrapper(
                      controller: chipsScrollController,
                      isCompact: true,
                      child: SingleChildScrollView(
                        controller: chipsScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            FilterChip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              label: Text(l10n.all),
                              selected: currentFilter == null,
                              onSelected: (_) => ref
                                  .read(homeFilterProvider.notifier)
                                  .setFilter(null),
                            ),
                            const SizedBox(width: 8),
                            ...ProviderType.values
                                .where((t) => t != ProviderType.other)
                                .map((type) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      label: Text(_getLocalizedType(type, l10n)),
                                      selected: currentFilter == type,
                                      onSelected: (_) => ref
                                          .read(homeFilterProvider.notifier)
                                          .setFilter(type),
                                    ),
                                  );
                                }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Divider(),
                Flexible(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final filter = ref.watch(homeFilterProvider);
                      final filteredProviders = filter == null
                          ? providers
                          : providers
                                .where((p) => p.supportedTypes.contains(filter))
                                .toList();

                      return RadioGroup<String?>(
                        groupValue: activeProvider?.packageName,
                        onChanged: (val) {
                          final selected = val == null
                              ? null
                              : providers.firstWhere(
                                  (p) => p.packageName == val,
                                );
                          ref
                              .read(activeProviderStateProvider.notifier)
                              .set(selected);
                          Navigator.pop(context);
                          ref.invalidate(homeDataProvider);
                        },
                        child: ListView.builder(
                          controller: scrollController,
                          shrinkWrap: true,
                          itemCount:
                              (filter == null ? 1 : 0) +
                              filteredProviders.length,
                          itemBuilder: (context, index) {
                            if (filter == null && index == 0) {
                              return ListTile(
                                title: Text(l10n.none),
                                leading: const Radio<String?>(value: null),
                                onTap: () {
                                  ref
                                      .read(
                                        activeProviderStateProvider.notifier,
                                      )
                                      .set(null);
                                  Navigator.pop(context);
                                  ref.invalidate(homeDataProvider);
                                },
                              );
                            }

                            final p =
                                filteredProviders[filter == null
                                    ? index - 1
                                    : index];
                            final isDebug = p.isDebug;
                            return ListTile(
                              title: Row(
                                children: [
                                  Expanded(child: Text(p.name)),
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
                                      child: Text(
                                        l10n.debug,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              leading: Radio<String?>(value: p.packageName),
                              onTap: () {
                                ref
                                    .read(activeProviderStateProvider.notifier)
                                    .set(p);
                                Navigator.pop(context);
                                ref.invalidate(homeDataProvider);
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    ).then((_) {
      scrollController.dispose();
    });
  }

  String _getLocalizedType(ProviderType type, AppLocalizations l10n) {
    switch (type) {
      case ProviderType.movie:
        return l10n.movies;
      case ProviderType.series:
        return l10n.series;
      case ProviderType.anime:
        return l10n.anime;
      case ProviderType.livestream:
        return l10n.liveStreams;
      case ProviderType.other:
        return l10n.unknown;
    }
  }
}

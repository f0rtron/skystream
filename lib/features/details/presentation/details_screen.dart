import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/entity/multimedia_item.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/extensions/base_provider.dart';
import '../../library/presentation/library_provider.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../core/storage/storage_service.dart';
import '../../library/presentation/history_provider.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final bool autoPlay;

  const DetailsScreen({super.key, required this.item, this.autoPlay = false});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  late Future<MultimediaItem> _detailsFuture;

  Map<int, List<Episode>> _seasonMap = {};
  int _selectedSeason = 1;
  bool _isMovie = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  void _loadDetails() {
    final active = ref.read(activeProviderStateProvider);
    final manager = ref.read(extensionManagerProvider.notifier);

    // Bypass for Local/Remote items (History/Resume support)
    if (widget.item.provider == 'Local' ||
        widget.item.provider == 'Torrent' ||
        widget.item.provider == 'Remote') {
      // Regenerate episode if missing (fix for history persistence)
      // History items might not store the full episodes list, so we recreate it from the main URL
      var itemToUse = widget.item;
      if (itemToUse.episodes == null || itemToUse.episodes!.isEmpty) {
        itemToUse = itemToUse.copyWith(
          episodes: [
            Episode(
              name: itemToUse.title,
              url: itemToUse
                  .url, // The main item URL is the file path/stream link
              posterUrl: itemToUse.posterUrl,
            ),
          ],
        );
      }

      _detailsFuture = Future.value(itemToUse);
      _processEpisodes(itemToUse.episodes);

      // Auto-play logic if requested (e.g. from history click)
      if (mounted && widget.autoPlay) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handlePlayPress(context, itemToUse);
        });
      }
      return;
    }

    SkyStreamProvider? provider;
    if (widget.item.provider != null) {
      try {
        final val = widget.item.provider!;
        provider = manager.getAllProviders().firstWhere(
          (p) => p.id == val || p.name == val,
        );
      } catch (_) {}
    }

    provider ??= active;

    if (provider != null) {
      _detailsFuture = provider.getDetails(widget.item.url).then((item) {
        // Use ID for persistence
        final withProvider = item.copyWith(provider: provider!.id);
        _processEpisodes(withProvider.episodes);

        // Auto-play logic if requested
        if (mounted && widget.autoPlay) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handlePlayPress(context, withProvider);
          });
        }

        return withProvider;
      });
    } else {
      _detailsFuture = Future.error(
        "No provider selected or found for this item",
      );
    }
  }

  void _processEpisodes(List<Episode>? episodes) {
    if (episodes == null || episodes.isEmpty) {
      _isMovie = false;
      _seasonMap = {};
      return;
    }

    // Treat single episode list as a movie; common in SkyStream
    if (episodes.length == 1) {
      _isMovie = true;
      _seasonMap = {1: episodes};
      _selectedSeason = 1;
      return;
    }

    _isMovie = false;
    _seasonMap = {};
    for (var ep in episodes) {
      final season = ep.season > 0 ? ep.season : 1;
      _seasonMap.putIfAbsent(season, () => []).add(ep);
    }

    final sortedSeasons = _seasonMap.keys.toList()..sort();

    // Pick the first season by default
    if (sortedSeasons.isNotEmpty) {
      _selectedSeason = sortedSeasons.first;
    }
  }

  void _play(BuildContext context, String url, [MultimediaItem? detailedItem]) {
    context.push(
      '/player',
      extra: {'item': detailedItem ?? widget.item, 'url': url},
    );
  }

  void _handlePlayPress(BuildContext context, MultimediaItem details) {
    // Play the single episode for movies
    if (_isMovie) {
      _play(context, details.episodes!.first.url, details);
      return;
    }

    // For Series, check history for "Continue Watching"
    final storage = ref.read(storageServiceProvider);
    final lastEpisodeUrl = storage.getLastEpisodeUrl(widget.item.url);
    final position = storage.getPosition(widget.item.url);
    final duration = ref
        .read(watchHistoryProvider)
        .firstWhere(
          (i) => i.item.url == widget.item.url,
          orElse: () => HistoryItem(
            item: widget.item,
            position: 0,
            duration: 1,
            timestamp: 0,
          ),
        )
        .duration;

    // Calculate progress (safety for zero duration)
    final progress = duration > 0 ? (position / duration) * 100 : 0;

    if (lastEpisodeUrl != null) {
      // Flatten episodes to find index
      final allEpisodes = <Episode>[];
      final sortedSeasons = _seasonMap.keys.toList()..sort();
      for (var s in sortedSeasons) {
        allEpisodes.addAll(_seasonMap[s]!);
      }

      final lastIndex = allEpisodes.indexWhere((e) => e.url == lastEpisodeUrl);
      if (lastIndex != -1) {
        // If > 95% finished, try next episode
        if (progress > 95) {
          if (lastIndex + 1 < allEpisodes.length) {
            _play(context, allEpisodes[lastIndex + 1].url, details);
            return;
          }
        }
        // Else (or if no next episode), resume current
        _play(context, lastEpisodeUrl, details);
        return;
      }
    }

    // Fallback: First episode
    final firstSeason = _seasonMap.keys.toList()..sort();
    if (firstSeason.isNotEmpty) {
      final ep = _seasonMap[firstSeason.first]?.first;
      if (ep != null) _play(context, ep.url, details);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBookmarked = ref.watch(
      libraryProvider.select(
        (items) => items.any((i) => i.url == widget.item.url),
      ),
    );
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final device = ref.watch(deviceProfileProvider).asData?.value;
    final isLarge = device?.isLargeScreen ?? false;

    return Scaffold(
      body: FutureBuilder<MultimediaItem>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          final details = snapshot.data;
          final item = details ?? widget.item;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: isLarge ? 300 : 400,
                stretch: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [
                    StretchMode.zoomBackground,
                    StretchMode.blurBackground,
                  ],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'banner_${item.url}',
                        child: CachedNetworkImage(
                          imageUrl: item.bannerUrl ?? item.posterUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          placeholder: (context, url) =>
                              Container(color: Theme.of(context).dividerColor),
                          errorWidget: (context, url, error) =>
                              Container(color: Colors.grey[900]),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Theme.of(
                                context,
                              ).scaffoldBackgroundColor.withValues(alpha: 0.5),
                              Theme.of(context).scaffoldBackgroundColor,
                            ],
                            stops: const [0.0, 0.6, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: isBookmarked
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                    ),
                    onPressed: () {
                      if (isBookmarked) {
                        libraryNotifier.removeItem(item.url);
                      } else {
                        libraryNotifier.addItem(item);
                      }
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLarge ? 32.0 : 16.0,
                    vertical: 16.0,
                  ),
                  child: isLarge
                      ? _buildDesktopLayout(context, item, details, snapshot)
                      : _buildMobileLayout(context, item, details, snapshot),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    AsyncSnapshot<MultimediaItem> snapshot,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left side: Poster and actions
        SizedBox(
          width: 250,
          child: Column(
            children: [
              Hero(
                tag: 'poster_${item.url}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: item.posterUrl,
                    width: 250,
                    height: 375,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildActionButtons(context, details, vertical: true),
            ],
          ),
        ),
        const SizedBox(width: 32),
        // Right side: Metadata and episodes
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.episodes != null && item.episodes!.length > 1)
                    _buildChip(context, '${item.episodes!.length} Eps'),
                  if (item.provider != null)
                    _buildProviderChip(context, ref, item.provider!),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Synopsis',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.description ?? 'No description available.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 32),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                Text(
                  "Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red),
                )
              else if (_isMovie)
                const SizedBox.shrink() // Movies don't need an episode list
              else if (details?.episodes != null) ...[
                if (_seasonMap.keys.length > 1) _buildSeasonSelector(context),
                const SizedBox(height: 16),
                _buildDesktopEpisodeGrid(
                  context,
                  _seasonMap[_selectedSeason] ?? [],
                  item,
                ),
              ] else
                const Text("No episodes found."),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    MultimediaItem item,
    MultimediaItem? details,
    AsyncSnapshot<MultimediaItem> snapshot,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'poster_${item.url}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: item.posterUrl,
                  width: 100,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (item.episodes != null && item.episodes!.length > 1)
                        _buildChip(context, '${item.episodes!.length} Eps'),
                      if (item.provider != null)
                        _buildProviderChip(context, ref, item.provider!),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildActionButtons(context, details),
        const SizedBox(height: 24),
        Text(
          'Synopsis',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          item.description ?? 'No description available.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).textTheme.bodyMedium?.color,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        if (snapshot.connectionState == ConnectionState.waiting)
          Container(
            height: 100,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          )
        else if (snapshot.hasError)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.red.withOpacity(0.1),
            child: Text("Error: ${snapshot.error}"),
          )
        else if (_isMovie)
          const SizedBox.shrink()
        else if (details?.episodes != null) ...[
          if (_seasonMap.keys.length > 1) _buildSeasonSelector(context),
          const SizedBox(height: 16),
          _buildEpisodeList(context, _seasonMap[_selectedSeason] ?? [], item),
        ] else
          const Text("No episodes found."),
        const SizedBox(height: 50),
      ],
    );
  }

  Widget _buildSeasonSelector(BuildContext context) {
    final seasons = _seasonMap.keys.toList()..sort();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final s = seasons[index];
          final isSelected = s == _selectedSeason;
          return FilterChip(
            label: Text("Season $s"),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedSeason = s),
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            labelStyle: TextStyle(
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    MultimediaItem? details, {
    bool vertical = false,
  }) {
    // Check for resume status (Movies only for now)
    bool isResuming = false;
    if (_isMovie) {
      final storage = ref.watch(storageServiceProvider);
      final pos = storage.getPosition(widget.item.url);
      // Threshold: > 5 seconds and < 95% (handled by remove history logic usually, but checks existing)
      if (pos > 5000) isResuming = true;
    }

    final playBtn = FilledButton.icon(
      onPressed:
          (details != null &&
              details.episodes != null &&
              details.episodes!.isNotEmpty)
          ? () => _handlePlayPress(context, details)
          : null,
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(isResuming ? 'Resume' : 'Play'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: Theme.of(context).colorScheme.primary,
        minimumSize: const Size(double.infinity, 50),
      ),
    );

    final downloadBtn = OutlinedButton.icon(
      onPressed: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Coming soon')));
      },
      icon: const Icon(Icons.download_rounded),
      label: const Text('Download'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
      ),
    );

    if (vertical) {
      return Column(
        children: [playBtn, const SizedBox(height: 12), downloadBtn],
      );
    }

    return Row(
      children: [
        Expanded(child: playBtn),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Coming soon')));
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopEpisodeGrid(
    BuildContext context,
    List<Episode> episodes,
    MultimediaItem parentItem,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isMovie) ...[
          Text(
            "Episodes",
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 3 / 1, // Wider layout for episode cards
          ),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final ep = episodes[index];
            return Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => _play(context, ep.url, parentItem),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ep.posterUrl != null
                            ? CachedNetworkImage(
                                imageUrl: ep.posterUrl!,
                                width: 80,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 80,
                                height: 60,
                                color: Colors.grey[800],
                                child: Center(child: Text("${ep.episode}")),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ep.name.isNotEmpty
                                  ? ep.name
                                  : "Episode ${ep.episode}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            if (ep.description != null)
                              Text(
                                ep.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_circle_outline),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEpisodeList(
    BuildContext context,
    List<Episode> episodes,
    MultimediaItem parentItem,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isMovie) ...[
          Text(
            "Episodes",
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
        ],
        ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final ep = episodes[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: ep.posterUrl != null
                    ? CachedNetworkImage(
                        imageUrl: ep.posterUrl!,
                        width: 80,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.movie),
                      )
                    : Container(
                        width: 80,
                        color: Colors.grey[800],
                        child: Center(child: Text("${ep.episode}")),
                      ),
                title: Text(
                  ep.name.isNotEmpty ? ep.name : "Episode ${ep.episode}",
                ),
                subtitle: Text(ep.description ?? ""),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => _play(context, ep.url, parentItem),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildProviderChip(
    BuildContext context,
    WidgetRef ref,
    String providerName,
  ) {
    bool isDebug = false;
    String displayName = providerName;
    try {
      final manager = ref.read(extensionManagerProvider.notifier);
      final p = manager.getAllProviders().firstWhere(
        (p) => p.id == providerName || p.name == providerName,
      );
      displayName = p.name;
      if (p.isDebug) {
        isDebug = true;
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayName,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (isDebug) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
    );
  }
}

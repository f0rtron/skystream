import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:skystream/core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/history_repository.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/shared/widgets/custom_widgets.dart';
import '../details_controller.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/shared/widgets/thumbnail_error_placeholder.dart';

class DetailsSeasonSelector extends ConsumerWidget {
  final DetailsState state;
  final String itemUrl;

  const DetailsSeasonSelector({super.key, required this.state, required this.itemUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasons = state.seasonMap.keys.toList()..sort();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: LayoutConstants.spacingXs),
        itemBuilder: (context, index) {
          final s = seasons[index];
          final isSelected = s == state.selectedSeason;
          return FilterChip(
            label: Text("Season $s"),
            selected: isSelected,
            onSelected: (_) =>
                ref.read(detailsControllerProvider(itemUrl).notifier).setSeason(s),
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
}

class DetailsActionButtons extends ConsumerWidget {
  final MultimediaItem item;
  final MultimediaItem? details;
  final DetailsState state;
  final bool vertical;

  const DetailsActionButtons({
    super.key,
    required this.item,
    required this.details,
    required this.state,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool isResuming = false;
    if (state.isMovie) {
      final historyRepo = ref.watch(historyRepositoryProvider);
      final pos = historyRepo.getPosition(item.url);
      if (pos > 5000) isResuming = true;
    }

    final playBtn = CustomButton(
      isPrimary: true,
      autofocus: true,
      onPressed:
          (details != null &&
              details!.episodes != null &&
              details!.episodes!.isNotEmpty)
          ? () => ref
                .read(detailsControllerProvider(item.url).notifier)
                .handlePlayPress(context, details!)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(LayoutConstants.spacingMd),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: state.isLaunching
              ? const [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: LayoutConstants.spacingXs),
                  Text('Resolving...'),
                ]
              : [
                  const Icon(Icons.play_arrow_rounded),
                  const SizedBox(width: LayoutConstants.spacingXs),
                  Text(isResuming ? 'Resume' : 'Play'),
                ],
        ),
      ),
    );

    final downloadBtn = CustomButton(
      isPrimary: false,
      isOutlined: true,
      onPressed: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Coming soon')));
      },
      child: const Padding(
        padding: EdgeInsets.all(LayoutConstants.spacingMd),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_rounded),
            SizedBox(width: LayoutConstants.spacingXs),
            Text('Download'),
          ],
        ),
      ),
    );

    if (vertical) {
      return Column(
        children: [playBtn, const SizedBox(height: LayoutConstants.spacingSm), downloadBtn],
      );
    }

    return Row(
      children: [
        Expanded(child: playBtn),
        const SizedBox(width: LayoutConstants.spacingSm),
        Expanded(child: downloadBtn),
      ],
    );
  }
}

class DetailsDesktopEpisodeGrid extends ConsumerWidget {
  final List<Episode> episodes;
  final MultimediaItem parentItem;
  final DetailsState state;

  const DetailsDesktopEpisodeGrid({
    super.key,
    required this.episodes,
    required this.parentItem,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!state.isMovie) ...[
          Text(
            "Episodes",
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: LayoutConstants.spacingMd),
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
              key: ValueKey(ep.url),
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => ref
                    .read(detailsControllerProvider(parentItem.url).notifier)
                    .handlePlayPress(context, parentItem, specificEpisode: ep),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(LayoutConstants.spacingXs),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                                imageUrl: AppImageFallbacks.poster(
                                  ep.posterUrl,
                                  label: ep.name.isNotEmpty
                                      ? ep.name
                                      : 'Episode ${ep.episode}',
                                ),
                                width: 80,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                      ),
                      const SizedBox(width: LayoutConstants.spacingSm),
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
                      state.isLaunching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_circle_outline),
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
}

class DetailsEpisodeList extends ConsumerWidget {
  final List<Episode> episodes;
  final MultimediaItem parentItem;
  final DetailsState state;

  const DetailsEpisodeList({
    super.key,
    required this.episodes,
    required this.parentItem,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!state.isMovie) ...[
          Text(
            "Episodes",
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: LayoutConstants.spacingMd),
        ],
        ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final ep = episodes[index];
            return Card(
              key: ValueKey(ep.url),
              margin: const EdgeInsets.only(bottom: LayoutConstants.spacingXs),
              child: ListTile(
                leading: CachedNetworkImage(
                  imageUrl: AppImageFallbacks.poster(
                    ep.posterUrl,
                    label: ep.name.isNotEmpty
                        ? ep.name
                        : 'Episode ${ep.episode}',
                  ),
                  width: 80,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const ThumbnailErrorPlaceholder(iconSize: 32),
                ),
                title: Text(
                  ep.name.isNotEmpty ? ep.name : "Episode ${ep.episode}",
                ),
                subtitle: Text(ep.description ?? ""),
                trailing: state.isLaunching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_outline),
                onTap: () => ref
                    .read(detailsControllerProvider(parentItem.url).notifier)
                    .handlePlayPress(context, parentItem, specificEpisode: ep),
              ),
            );
          },
        ),
      ],
    );
  }
}

class DetailsChip extends StatelessWidget {
  final String label;

  const DetailsChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
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
}

class DetailsProviderChip extends ConsumerWidget {
  final String providerName;

  const DetailsProviderChip({super.key, required this.providerName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    } catch (e) {
      debugPrint('DetailsProviderChip.build: $e');
    }

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
          Icon(Icons.extension, size: 14, color: Theme.of(context).hintColor),
          const SizedBox(width: 4),
          Text(
            displayName,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (isDebug) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('DEBUG', style: TextStyle(fontSize: 8)),
            ),
          ],
        ],
      ),
    );
  }
}

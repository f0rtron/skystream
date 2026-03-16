import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/history_repository.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/shared/widgets/custom_widgets.dart';
import '../details_controller.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'episode_card.dart';

class DetailsSeasonListWrapper extends ConsumerWidget {
  const DetailsSeasonListWrapper({super.key, required this.itemUrl});
  final String itemUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonMap = ref.watch(detailsControllerProvider(itemUrl).select((s) => s.seasonMap));
    if (seasonMap.keys.length <= 1) return const SizedBox.shrink();
    
    final selectedSeason = ref.watch(detailsControllerProvider(itemUrl).select((s) => s.selectedSeason));
    final seasons = seasonMap.keys.toList()..sort();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: LayoutConstants.spacingXs),
        itemBuilder: (context, index) {
          final s = seasons[index];
          final isSelected = s == selectedSeason;
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
  final String itemUrl;
  final bool vertical;

  const DetailsActionButtons({
    super.key,
    required this.item,
    required this.details,
    required this.itemUrl,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyRepo = ref.watch(historyRepositoryProvider);
    final targetEpisode = ref.watch(detailsControllerProvider(itemUrl).select((s) => s.targetEpisode));
    final isLaunching = ref.watch(detailsControllerProvider(itemUrl).select((s) => s.isLaunching));
    final isMovie = ref.watch(detailsControllerProvider(itemUrl).select((s) => s.isMovie));
    
    final pos = targetEpisode != null 
        ? historyRepo.getEpisodePosition(targetEpisode.url)
        : historyRepo.getPosition(item.url);
    final dur = targetEpisode != null 
        ? historyRepo.getEpisodeDuration(targetEpisode.url)
        : historyRepo.getDuration(item.url);
    
    final bool isResuming = pos > 5000;

    String playLabel = isResuming ? 'Resume' : 'Play';
    if (targetEpisode != null && !isMovie) {
      playLabel = "$playLabel S${targetEpisode.season} E${targetEpisode.episode}";
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
          children: isLaunching
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
                  Text(playLabel),
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

    Widget progressWidget = const SizedBox.shrink();
    if (pos > 0 && dur > 0) {
      final progress = (pos / dur).clamp(0.0, 1.0);
      progressWidget = Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "${(progress * 100).toInt()}% watched${!isMovie && targetEpisode != null ? ' (S${targetEpisode.season} E${targetEpisode.episode})' : ''}",
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          playBtn,
          progressWidget,
          const SizedBox(height: LayoutConstants.spacingSm),
          downloadBtn,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: playBtn),
            const SizedBox(width: LayoutConstants.spacingSm),
            Expanded(child: downloadBtn),
          ],
        ),
        progressWidget,
      ],
    );
  }
}

class DetailsDesktopEpisodeGrid extends ConsumerWidget {
  final MultimediaItem parentItem;
  final String itemUrl;
  final bool isMovie;

  const DetailsDesktopEpisodeGrid({
    super.key,
    required this.parentItem,
    required this.itemUrl,
    required this.isMovie,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodes = ref.watch(detailsControllerProvider(itemUrl).select((s) {
      return s.seasonMap[s.selectedSeason] ?? [];
    }));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMovie) ...[
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
            maxCrossAxisExtent: 320,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.0,
          ),
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final ep = episodes[index];
            return EpisodeCard(
              episode: ep,
              parentItem: parentItem,
              isHorizontal: true,
            );
          },
        ),
      ],
    );
  }
}

class DetailsEpisodeList extends ConsumerWidget {
  final MultimediaItem parentItem;
  final String itemUrl;
  final bool isMovie;

  const DetailsEpisodeList({
    super.key,
    required this.parentItem,
    required this.itemUrl,
    required this.isMovie,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodes = ref.watch(detailsControllerProvider(itemUrl).select((s) {
      return s.seasonMap[s.selectedSeason] ?? [];
    }));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMovie) ...[
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
            return EpisodeCard(
              episode: ep,
              parentItem: parentItem,
              isHorizontal: false,
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
        (p) => p.packageName == providerName || p.name == providerName,
      );
      displayName = p.name;
      if (p.isDebug) {
        isDebug = true;
      }
    } catch (e) {
      debugPrint('DetailsProviderChip.build: $e');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.extension_rounded,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            displayName.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          if (isDebug) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'DEBUG',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
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

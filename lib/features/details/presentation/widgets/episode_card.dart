import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/history_repository.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../library/presentation/history_provider.dart';
import '../details_controller.dart';

class EpisodeCard extends ConsumerStatefulWidget {
  final Episode episode;
  final MultimediaItem parentItem;
  final double? width;
  final bool isHorizontal;

  const EpisodeCard({
    super.key,
    required this.episode,
    required this.parentItem,
    this.width,
    this.isHorizontal = true,
  });

  @override
  ConsumerState<EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends ConsumerState<EpisodeCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    // For series, we store progress per episode URL sometimes, 
    // but the Smart Auto-Advance stores the *series url* as the key with episode metadata.
    // However, for individual episode cards, we might want to check the specific episode URL 
    // if it was watched stand-alone, or just check if it matches the 'last watched' episode in history.
    
    final historyRepo = ref.watch(historyRepositoryProvider);
    final historyItem = ref.watch(watchHistoryProvider).cast<HistoryItem?>().firstWhere(
      (h) => h?.item.url == widget.parentItem.url,
      orElse: () => null,
    );

    final epPos = historyRepo.getEpisodePosition(widget.episode.url);
    final epDur = historyRepo.getEpisodeDuration(widget.episode.url);

    double progress = epDur > 0 ? epPos / epDur : 0;
    String? statusBadge;

    if (progress > 0.02) {
      statusBadge = progress > 0.98 ? "WATCHED" : "WATCHING";
    }

    if (historyItem != null && statusBadge == null) {
      final hSeason = historyItem.season ?? 1;
      final hEpisode = historyItem.episode ?? 1;
      final eSeason = widget.episode.season;
      final eEpisode = widget.episode.episode;

      if (eSeason == hSeason && eEpisode == hEpisode) {
        // If the episode is current in history but doesn't have its own EP_ key yet,
        // it might be using the main series record.
        if (progress <= 0) {
          progress = historyItem.duration > 0 ? historyItem.position / historyItem.duration : 0;
          if (progress > 0.02) {
            statusBadge = progress > 0.98 ? "WATCHED" : "WATCHING";
          } else {
            statusBadge = "NEXT";
          }
        }
      }
    }

    final imageUrl = AppImageFallbacks.tmdbStill(
      widget.episode.posterUrl,
      label: widget.episode.name,
    );

    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: widget.width ?? (widget.isHorizontal ? 300 : double.infinity),
        decoration: BoxDecoration(
          color: _isFocused 
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFocused ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref
              .read(detailsControllerProvider(widget.parentItem.url).notifier)
              .handlePlayPress(context, widget.parentItem, specificEpisode: widget.episode),
          borderRadius: BorderRadius.circular(10),
          child: widget.isHorizontal 
              ? _buildHorizontalLayout(context, imageUrl, progress, statusBadge) 
              : _buildVerticalLayout(context, imageUrl, progress, statusBadge),
        ),
      ),
    );
  }

  Widget _buildHorizontalLayout(BuildContext context, String imageUrl, double progress, String? statusBadge) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => ShimmerPlaceholder.rectangular(borderRadius: 0),
                errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                  label: widget.episode.name,
                ),
              ),
            ),
            if (progress > 0)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.black26,
                  color: Theme.of(context).colorScheme.primary,
                  minHeight: 4,
                ),
              ),
            if (statusBadge != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusBadge == "WATCHED" 
                        ? Colors.green 
                        : Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "E${widget.episode.episode}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.episode.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                if ((widget.episode.runtime ?? 0) > 0)
                  Text(
                    "${widget.episode.runtime} min",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (widget.episode.description != null &&
                    widget.episode.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      widget.episode.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalLayout(BuildContext context, String imageUrl, double progress, String? statusBadge) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: 120,
                  height: 68,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                    label: widget.episode.name,
                    iconSize: 24,
                  ),
                ),
              ),
              if (progress > 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.black26,
                      color: Theme.of(context).colorScheme.primary,
                      minHeight: 3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${widget.episode.episode}. ${widget.episode.name}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (statusBadge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: statusBadge == "WATCHED" 
                              ? Colors.green.withValues(alpha: 0.8) 
                              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.episode.description ?? "No description",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (statusBadge == "WATCHING" || statusBadge == "NEXT")
            Icon(
              Icons.play_circle_fill,
              color: Theme.of(context).colorScheme.primary,
            ),
          if (statusBadge == "WATCHED")
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
            ),
        ],
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/history_repository.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../library/presentation/history_provider.dart';
import '../details_controller.dart';

class EpisodeCard extends ConsumerStatefulWidget {
  final Episode episode;
  final MultimediaItem parentItem;
  final double? width;

  const EpisodeCard({
    super.key,
    required this.episode,
    required this.parentItem,
    this.width,
  });

  @override
  ConsumerState<EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends ConsumerState<EpisodeCard>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() {
      _isFocused = focused;
    });
    if (focused) {
      _scaleController.forward();
    } else {
      _scaleController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    // For series, we store progress per episode URL sometimes,
    // but the Smart Auto-Advance stores the *series url* as the key with episode metadata.
    // However, for individual episode cards, we might want to check the specific episode URL
    // if it was watched stand-alone, or just check if it matches the 'last watched' episode in history.

    final historyRepo = ref.watch(historyRepositoryProvider);
    final historyItem = ref.watch(
      watchHistoryProvider.select(
        (list) => list.whereType<HistoryItem>().firstWhereOrNull(
          (h) => h.item.url == widget.parentItem.url,
        ),
      ),
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
          progress = historyItem.duration > 0
              ? historyItem.position / historyItem.duration
              : 0;
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
      onFocusChange: _onFocusChange,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.width ?? double.infinity,
          decoration: BoxDecoration(
            color: _isFocused
                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => ref
                .read(detailsControllerProvider(widget.parentItem.url).notifier)
                .handlePlayPress(
                  context,
                  widget.parentItem,
                  specificEpisode: widget.episode,
                ),
            borderRadius: BorderRadius.circular(10),
            child: _buildLayout(context, imageUrl, progress, statusBadge),
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(
    BuildContext context,
    String imageUrl,
    double progress,
    String? statusBadge,
  ) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 140,
                      height: 80,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                        label: widget.episode.name,
                        iconSize: 24,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
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
              const SizedBox(width: 16),
              Expanded(
                child: Expanded(
                  child: Text(
                    "${widget.episode.episode}. ${widget.episode.name}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.file_download_outlined),
                onPressed: () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Coming soon')));
                },
              ),
            ],
          ),
          if (widget.episode.description != null &&
              widget.episode.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.episode.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

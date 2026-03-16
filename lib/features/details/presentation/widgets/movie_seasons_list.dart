import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/models/tmdb_details.dart';
import '../tmdb_details_controller.dart';

class MovieSeasonsList extends ConsumerStatefulWidget {
  final int movieId;
  final List<TmdbSeason> seasons;
  final Color? textColor;

  const MovieSeasonsList({
    super.key,
    required this.movieId,
    required this.seasons,
    this.textColor,
  });

  @override
  ConsumerState<MovieSeasonsList> createState() => _MovieSeasonsListState();
}

class _MovieSeasonsListState extends ConsumerState<MovieSeasonsList> {
  late final ScrollController _scrollController;
  late final ScrollController _episodesScrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _episodesScrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _episodesScrollController.dispose();
    super.dispose();
  }

  Widget _buildTmdbLogo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0d253f),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        "TMDB",
        style: TextStyle(
          color: Color(0xFF90cea1),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seasons.isEmpty) return const SizedBox.shrink();

    final isDesktop = context.isDesktop;

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Episodes",
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Consumer(
                  builder: (context, ref, _) {
                    return DropdownButton<int>(
                      value: ref
                          .watch(tmdbDetailsControllerProvider(widget.movieId))
                          .selectedSeason,
                      dropdownColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainer,
                      underline: const SizedBox(),
                      style: TextStyle(color: widget.textColor),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: widget.textColor,
                      ),
                      items: widget.seasons.map<DropdownMenuItem<int>>((s) {
                        final num = s.seasonNumber;
                        final count = s.episodeCount;
                        return DropdownMenuItem(
                          value: num,
                          child: Text("Season $num ($count Episodes)"),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          ref
                              .read(
                                tmdbDetailsControllerProvider(
                                  widget.movieId,
                                ).notifier,
                              )
                              .fetchEpisodes(val);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDesktopEpisodesList(context),
          const SizedBox(height: 50),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Seasons",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: ListView.separated(
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              itemCount: widget.seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final season = widget.seasons[index];
                final seasonNum = season.seasonNumber;

                return Consumer(
                  builder: (context, ref, _) {
                    final isSelected =
                        ref
                            .watch(
                              tmdbDetailsControllerProvider(widget.movieId),
                            )
                            .selectedSeason ==
                        seasonNum;

                    return GestureDetector(
                      onTap: () => ref
                          .read(
                            tmdbDetailsControllerProvider(
                              widget.movieId,
                            ).notifier,
                          )
                          .fetchEpisodes(seasonNum),
                      child: Container(
                        width: 120,
                        decoration: BoxDecoration(
                          border: isSelected
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                )
                              : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CachedNetworkImage(
                                  imageUrl: season.posterImageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorWidget: (_, _, _) =>
                                      ThumbnailErrorPlaceholder(
                                        label: season.name,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              season.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.textColor,
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            Text(
                              '${season.episodeCount} Episodes',
                              style: TextStyle(
                                color: widget.textColor?.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildMobileEpisodesList(context),
          const SizedBox(height: 32),
        ],
      );
    }
  }

  Widget _buildDesktopEpisodesList(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        if (ref
                .watch(tmdbDetailsControllerProvider(widget.movieId))
                .episodesFuture ==
            null) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<Map<String, dynamic>?>(
          future: ref
              .watch(tmdbDetailsControllerProvider(widget.movieId))
              .episodesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const SizedBox.shrink();
            }
            final episodes = List<Map<String, dynamic>>.from(
              snapshot.data!['episodes'] ?? [],
            );
            if (episodes.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 240,
              child: DesktopScrollWrapper(
                controller: _scrollController,
                child: ListView.separated(
                  clipBehavior: Clip.none,
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: episodes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 20),
                  itemBuilder: (context, index) {
                    final ep = episodes[index];
                    final imageUrl = AppImageFallbacks.tmdbStill(
                      ep['still_path'],
                      label: ep['name'] ?? 'Episode',
                    );
                    final voteAverage =
                        (ep['vote_average'] as num?)?.toDouble() ?? 0.0;
                    final runtime = ep['runtime'] as int? ?? 0;
                    final hours = runtime ~/ 60;
                    final minutes = runtime % 60;
                    final runtimeText = hours > 0
                        ? '${hours}h ${minutes}m'
                        : '${minutes}m';

                    return CardsWrapper(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Please select a source from 'Available Sources' above to play.",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 300,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                placeholder: (context, url) =>
                                    ShimmerPlaceholder.rectangular(
                                      borderRadius: 8,
                                    ),
                                errorWidget: (_, _, _) =>
                                    ThumbnailErrorPlaceholder(
                                      label: ep['name'] ?? 'Episode',
                                    ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "E${ep['episode_number']} • ${ep['name']}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      _buildTmdbLogo(context),
                                      const SizedBox(width: 8),
                                      Text(
                                        voteAverage.toStringAsFixed(1),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (runtime > 0)
                                        Text(
                                          runtimeText,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    ep['overview'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileEpisodesList(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        if (ref
                .watch(tmdbDetailsControllerProvider(widget.movieId))
                .episodesFuture ==
            null) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<Map<String, dynamic>?>(
          future: ref
              .watch(tmdbDetailsControllerProvider(widget.movieId))
              .episodesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const SizedBox.shrink();
            }
            final episodes = List<Map<String, dynamic>>.from(
              snapshot.data!['episodes'] ?? [],
            );
            if (episodes.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Episodes",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: episodes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final ep = episodes[index];
                    final imageUrl = AppImageFallbacks.tmdbStill(
                      ep['still_path'],
                      label: ep['name'] ?? 'Episode',
                    );
                    final voteAverage =
                        (ep['vote_average'] as num?)?.toDouble() ?? 0.0;
                    final runtime = (ep['runtime'] as int?) ?? 0;
                    final hours = runtime ~/ 60;
                    final minutes = runtime % 60;
                    final runtimeText = hours > 0
                        ? '${hours}h ${minutes}m'
                        : '${minutes}m';

                    return CardsWrapper(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Please select a source from 'Available Sources' above to play.",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: 120,
                                height: 68,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    ThumbnailErrorPlaceholder(
                                      label: ep['name'] ?? 'Episode',
                                      iconSize: 24,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${ep['episode_number']}. ${ep['name']}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      _buildTmdbLogo(context),
                                      const SizedBox(width: 8),
                                      Text(
                                        voteAverage.toStringAsFixed(1),
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (runtime > 0)
                                        Text(
                                          runtimeText,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    ep['overview'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

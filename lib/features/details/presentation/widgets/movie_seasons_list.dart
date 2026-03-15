import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/models/tmdb_details.dart';
import '../tmdb_details_controller.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../details_controller.dart';
import 'episode_card.dart';

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
                      dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
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
                                      ThumbnailErrorPlaceholder(label: season.name),
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
              height: 300,
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

                    final runtime = (ep['runtime'] as int?) ?? 0;
                    
                    final episode = Episode(
                      name: ep['name'] ?? 'Episode ${ep['episode_number']}',
                      url: '', // TMDB doesn't have URLs, but we handle play via controller
                      season: ep['season_number'] ?? 0,
                      episode: ep['episode_number'] ?? 0,
                      description: ep['overview'],
                      posterUrl: ep['still_path'],
                      rating: (ep['vote_average'] as num?)?.toDouble(),
                      runtime: runtime,
                    );

                    // Get the base MultimediaItem from DetailsController
                    final detailsState = ref.watch(detailsControllerProvider(widget.movieId.toString())); 
                    final parentItem = detailsState.item ?? MultimediaItem(
                      title: "Series", 
                      url: widget.movieId.toString(), 
                      posterUrl: ""
                    );

                    return EpisodeCard(
                      episode: episode,
                      parentItem: parentItem,
                      width: 300,
                      isHorizontal: true,
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

                    final runtime = (ep['runtime'] as int?) ?? 0;

                    final episode = Episode(
                      name: ep['name'] ?? 'Episode ${ep['episode_number']}',
                      url: '', 
                      season: ep['season_number'] ?? 0,
                      episode: ep['episode_number'] ?? 0,
                      description: ep['overview'],
                      posterUrl: ep['still_path'],
                      rating: (ep['vote_average'] as num?)?.toDouble(),
                      runtime: runtime,
                    );

                    final detailsState = ref.watch(detailsControllerProvider(widget.movieId.toString()));
                    final parentItem = detailsState.item ?? MultimediaItem(
                      title: "Series", 
                      url: widget.movieId.toString(), 
                      posterUrl: ""
                    );

                    return EpisodeCard(
                      episode: episode,
                      parentItem: parentItem,
                      isHorizontal: false,
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

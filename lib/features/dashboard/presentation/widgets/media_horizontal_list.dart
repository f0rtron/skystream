import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/config/tmdb_config.dart';
import '../../../details/presentation/tmdb_movie_details_screen.dart';

class MediaHorizontalList extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> mediaList;

  const MediaHorizontalList({
    super.key,
    required this.title,
    required this.mediaList,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Title with Blue Underline Accent
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 20, // Accent width
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent, // Nuvio blue
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),

              // View All Button (Dark Pill)
              GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Text(
                        "View All",
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 10,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // List
        SizedBox(
          height: 200, // Adjusted for 2:3 ratio within list
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: mediaList.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = mediaList[index];
              final posterPath = item['poster_path'];
              final imageUrl = posterPath != null
                  ? '${TmdbConfig.imageBaseUrl}$posterPath'
                  : 'https://via.placeholder.com/150x225';
              final itemTitle = item['title'] ?? item['name'] ?? 'Unknown';
              final uniqueTag =
                  'list_${title}_${item['id']}_${itemTitle.hashCode}';
              final mediaType =
                  item['media_type'] ??
                  (item['title'] != null ? 'movie' : 'tv');

              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => TmdbMovieDetailsScreen(
                        movieId: item['id'],
                        mediaType: mediaType,
                        heroTag: uniqueTag,
                        placeholderPoster: imageUrl,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 130, // Fixed width for poster
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster Image
                      Expanded(
                        child: Hero(
                          tag: uniqueTag,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (context, url) => Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.error_outline,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Title below poster
                      Text(
                        itemTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/models/tmdb_details.dart';
import 'provider_search_section.dart';

/// Desktop hero: backdrop, gradients, and first column (logo, metadata, overview, sources).
/// [child] is the rest of the scroll content (seasons, cast, trailers, stats, etc.).
class TmdbDetailsDesktopHero extends StatelessWidget {
  const TmdbDetailsDesktopHero({
    super.key,
    required this.data,
    required this.isMovie,
    required this.child,
  });

  final TmdbDetails data;
  final bool isMovie;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;
    final textColor = theme.colorScheme.onSurface;
    final textSecondary = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    final title = data.title;
    final overview = data.overview;
    final logoUrl = data.logoUrl;
    final runtime = data.runtime;
    final hours = runtime ~/ 60;
    final minutes = runtime % 60;
    final durationText = hours > 0 ? '${hours}H ${minutes}M' : '${minutes}M';
    final releaseDate = data.releaseDateFull;
    final year = releaseDate.isNotEmpty ? releaseDate.split('-')[0] : '';
    final rating = data.voteAverage.toStringAsFixed(1);
    final genreText = data.genresStr ?? '';
    final certification = data.certification;
    final director = data.director;
    final backdropImageUrl = data.backdropImageUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [scaffoldColor, Colors.transparent],
                stops: const [0.2, 1.0],
              ).createShader(rect);
            },
            blendMode: BlendMode.dstOut,
            child: CachedNetworkImage(
              imageUrl: backdropImageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  scaffoldColor.withValues(alpha: 0.8),
                  scaffoldColor.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [scaffoldColor, Colors.transparent],
                stops: const [0.0, 0.4],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (logoUrl != null)
                        CachedNetworkImage(
                          imageUrl: logoUrl,
                          height: 200,
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.contain,
                          placeholder: (_, _) => Text(
                            title,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                        )
                      else
                        Text(
                          title,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            year.isNotEmpty ? "$year  •  " : "",
                            style: TextStyle(
                              color: textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            durationText,
                            style: TextStyle(
                              color: textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: textSecondary),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              certification,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF01B4E4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "TMDB",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            rating,
                            style: const TextStyle(
                              color: Color(0xFF01B4E4),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (director != "Unknown") ...[
                            const SizedBox(width: 12),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: textSecondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "Director: $director",
                              style: TextStyle(
                                color: textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        overview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        genreText,
                        style: TextStyle(
                          color: textSecondary.withValues(alpha: 0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Icon(
                            Icons.extension,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Available Sources",
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "BETA",
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(
                          maxWidth: 600,
                          maxHeight: 220,
                        ),
                        child: ProviderSearchSection(
                          query: title,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

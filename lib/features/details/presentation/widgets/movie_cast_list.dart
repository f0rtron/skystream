import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/models/tmdb_details.dart';

class MovieCastList extends StatefulWidget {
  final List<TmdbCast> cast;
  final Color? textColor;
  final Color? textSecondary;

  const MovieCastList({
    super.key,
    required this.cast,
    this.textColor,
    this.textSecondary,
  });

  @override
  State<MovieCastList> createState() => _MovieCastListState();
}

class _MovieCastListState extends State<MovieCastList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cast.isEmpty) return const SizedBox.shrink();

    final isDesktop = context.isDesktop;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDesktop) ...[
          Text(
            "Cast",
            style: TextStyle(
              color: widget.textColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140, // Height for Cast Cards
            child: DesktopScrollWrapper(
              controller: _scrollController,
              child: ListView.separated(
                clipBehavior: Clip.none,
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: widget.cast.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: _buildDesktopItem,
              ),
            ),
          ),
          const SizedBox(height: 50),
        ] else ...[
          Text(
            "Cast",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: ListView.builder(
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              itemCount: widget.cast.length,
              itemBuilder: _buildMobileItem,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildDesktopItem(BuildContext context, int index) {
    final actor = widget.cast[index];
    return CardsWrapper(
      onTap: () {},
      borderRadius: BorderRadius.circular(40),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundImage: NetworkImage(actor.profileImageUrl),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 80,
            child: Text(
              actor.name,
              style: TextStyle(color: widget.textColor, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              actor.character,
              style: TextStyle(color: widget.textSecondary, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileItem(BuildContext context, int index) {
    final member = widget.cast[index];
    return CardsWrapper(
      onTap: () {},
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 35,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage: CachedNetworkImageProvider(
                member.profileImageUrl,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              member.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              member.character,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

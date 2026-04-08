import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/storage/history_repository.dart';
import '../player_controller.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

class PlayerEpisodeOverlay extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final bool isVisible;
  final VoidCallback onDismiss;
  final bool isTv;

  const PlayerEpisodeOverlay({
    super.key,
    required this.item,
    required this.isVisible,
    required this.onDismiss,
    this.isTv = false,
  });

  @override
  ConsumerState<PlayerEpisodeOverlay> createState() =>
      _PlayerEpisodeOverlayState();
}

class _PlayerEpisodeOverlayState extends ConsumerState<PlayerEpisodeOverlay> {
  final ScrollController _scrollController = ScrollController();
  final FocusScopeNode _focusScopeNode = FocusScopeNode();
  int? _selectedSeason;
  List<int> _seasons = [];

  @override
  void initState() {
    super.initState();
    _extractSeasons();
    _initSelectedSeason();
  }

  void _extractSeasons() {
    if (widget.item.episodes == null) return;
    final seasonSet = widget.item.episodes!
        .map((e) => e.season)
        .toSet()
        .toList();
    seasonSet.sort();
    _seasons = seasonSet;
  }

  void _initSelectedSeason() {
    if (_seasons.isEmpty) return;

    // Check currently playing episode's season
    final currentEpUrl =
        ref.read(playerControllerProvider).currentStream?.url ??
        ref.read(playerControllerProvider.notifier).currentEpisodeUrl;

    final currentEpisode = widget.item.episodes?.firstWhere(
      (e) => e.url == currentEpUrl,
      orElse: () => widget.item.episodes!.first,
    );

    _selectedSeason = currentEpisode?.season ?? _seasons.first;
  }

  @override
  void didUpdateWidget(PlayerEpisodeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _scrollToCurrentEpisode();
    }
  }

  void _scrollToCurrentEpisode() {
    if (widget.item.episodes == null || widget.item.episodes!.isEmpty) return;

    final filteredEpisodes = widget.item.episodes!
        .where((e) => _selectedSeason == null || e.season == _selectedSeason)
        .toList();

    final controller = ref.read(playerControllerProvider.notifier);
    final currentIndex = filteredEpisodes.indexWhere(
      (e) =>
          e.url == ref.read(playerControllerProvider).currentStream?.url ||
          e.url == controller.currentEpisodeUrl,
    );

    if (currentIndex != -1) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            currentIndex * 100.0, // Estimated item height
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 600;
    final panelWidth = isMobile ? size.width * 0.85 : 360.0;

    return Stack(
      children: [
        // Full screen dismissal background
        if (widget.isVisible)
          GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              width: size.width,
              height: size.height,
              color: Colors.transparent,
            ),
          ),

        // Side Panel (Animated from right)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.fastOutSlowIn,
          right: widget.isVisible ? 0 : -panelWidth - 50,
          top: 0,
          bottom: 0,
          child: Container(
            width: panelWidth,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(-10, 0),
                ),
              ],
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child:
                          widget.item.episodes == null ||
                              widget.item.episodes!.isEmpty
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context)!.noEpisodesFound,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            )
                          : _buildEpisodeList(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.viewPaddingOf(context).top + 20,
        left: 20,
        right: 12,
        bottom: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.video_library_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.episodes,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onDismiss,
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
          if (_seasons.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Theme(
                data: Theme.of(context).copyWith(canvasColor: Colors.grey[900]),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedSeason,
                    elevation: 16,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    items: _seasons.map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(AppLocalizations.of(context)!
                            .seasonWithNumber(value)),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      setState(() {
                        _selectedSeason = newValue;
                      });
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEpisodeList(BuildContext context) {
    final allEpisodes = widget.item.episodes!;
    final episodes = allEpisodes
        .where((e) => _selectedSeason == null || e.season == _selectedSeason)
        .toList();

    final historyRepo = ref.read(historyRepositoryProvider);
    final currentEpUrl = ref.watch(
      playerControllerProvider.select((s) => s.currentStream?.url),
    );

    return FocusTraversalGroup(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: episodes.length,
        itemBuilder: (context, index) {
          final ep = episodes[index];
          final isPlaying = currentEpUrl == ep.url;

          final pos = historyRepo.getEpisodePosition(
            ep.url,
            mainUrl: widget.item.url,
            season: ep.season,
            episode: ep.episode,
          );
          final dur = historyRepo.getEpisodeDuration(
            ep.url,
            mainUrl: widget.item.url,
            season: ep.season,
            episode: ep.episode,
          );
          final progress = (dur > 0) ? (pos / dur) : 0.0;

          return _EpisodeItem(
            episode: ep,
            isPlaying: isPlaying,
            progress: progress,
            isTv: widget.isTv,
            onTap: () {
              ref.read(playerControllerProvider.notifier).loadEpisode(ep);
            },
          );
        },
      ),
    );
  }
}

class _EpisodeItem extends StatefulWidget {
  final Episode episode;
  final bool isPlaying;
  final double progress;
  final bool isTv;
  final VoidCallback onTap;

  const _EpisodeItem({
    required this.episode,
    required this.isPlaying,
    required this.progress,
    required this.isTv,
    required this.onTap,
  });

  @override
  State<_EpisodeItem> createState() => _EpisodeItemState();
}

class _EpisodeItemState extends State<_EpisodeItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowHoverHighlight: (v) => setState(() => _isHovered = v),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: widget.isPlaying
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : (_isHovered
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.transparent),
          child: Row(
            children: [
              // Thumbnail with progress
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    width: 120,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                      image: widget.episode.posterUrl != null
                          ? DecorationImage(
                              image: NetworkImage(widget.episode.posterUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: widget.isPlaying
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          )
                        : null,
                  ),
                  if (widget.progress > 0 && widget.progress < 0.95)
                    Container(
                      height: 3,
                      width: 120,
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(8),
                        ),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: widget.progress,
                        child: Container(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "S${widget.episode.season} : E${widget.episode.episode}",
                      style: TextStyle(
                        color: widget.isPlaying
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.episode.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: widget.isPlaying
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

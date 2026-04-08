import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/features/home/presentation/home_screen.dart';
import 'package:skystream/features/search/presentation/search_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import 'package:skystream/features/library/presentation/library_screen.dart';
import 'package:skystream/features/settings/presentation/settings_screen.dart';
import '../../features/extensions/screens/extensions_screen.dart';
import '../../features/settings/presentation/developer_options_screen.dart';
import '../../features/details/presentation/details_screen.dart';
import '../../features/details/presentation/tmdb_movie_details_screen.dart';
import '../../features/discover/presentation/view_all_screen.dart';
import '../../features/player/presentation/player_screen.dart';
import '../domain/entity/multimedia_item.dart';
import 'package:skystream/shared/widgets/app_scaffold.dart';
import '../../core/storage/settings_repository.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

/// Typed extra for /details. Use when pushing: context.push('/details', extra: DetailsRouteExtra(...)).
class DetailsRouteExtra {
  const DetailsRouteExtra({required this.item, this.autoPlay = false});
  final MultimediaItem item;
  final bool autoPlay;
}

/// Typed extra for /player. Use when pushing: context.push('/player', extra: PlayerRouteExtra(...)).
class PlayerRouteExtra {
  const PlayerRouteExtra({
    required this.item,
    required this.videoUrl,
    this.episode,
  });
  final MultimediaItem item;
  final String videoUrl;
  final Episode? episode;
}

/// Typed extra for /tmdb-details.
class TmdbDetailsRouteExtra {
  const TmdbDetailsRouteExtra({
    required this.movieId,
    this.mediaType = 'movie',
    this.heroTag,
    this.placeholderPoster,
  });
  final int movieId;
  final String mediaType;
  final String? heroTag;
  final String? placeholderPoster;
}

/// Typed extra for /view-all.
class ViewAllRouteExtra {
  const ViewAllRouteExtra({
    required this.title,
    required this.initialMediaList,
    required this.category,
  });
  final String title;
  final List<MultimediaItem> initialMediaList;
  final ViewAllCategory category;
}

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  ref.keepAlive();
  final initial = ref.read(settingsRepositoryProvider).getDefaultHomeScreen();

  return GoRouter(
    initialLocation: initial,
    navigatorKey: rootNavigatorKey,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'extensions',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const ExtensionsScreen(),
                  ),
                  GoRoute(
                    path: 'developer',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const DeveloperOptionsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/details',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! DetailsRouteExtra) {
            return Scaffold(
              body: Center(
                child: Text(AppLocalizations.of(context)!.invalidNavigation),
              ),
            );
          }
          return DetailsScreen(item: extra.item, autoPlay: extra.autoPlay);
        },
      ),
      GoRoute(
        path: '/tmdb-details',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! TmdbDetailsRouteExtra) {
            return Scaffold(
              body: Center(
                child: Text(AppLocalizations.of(context)!.invalidNavigation),
              ),
            );
          }
          return TmdbMovieDetailsScreen(
            movieId: extra.movieId,
            mediaType: extra.mediaType,
            heroTag: extra.heroTag,
            placeholderPoster: extra.placeholderPoster,
          );
        },
      ),
      GoRoute(
        path: '/view-all',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! ViewAllRouteExtra) {
            return Scaffold(
              body: Center(
                child: Text(AppLocalizations.of(context)!.invalidNavigation),
              ),
            );
          }
          return ViewAllScreen(
            title: extra.title,
            initialMediaList: extra.initialMediaList,
            category: extra.category,
          );
        },
      ),
      GoRoute(
        path: '/player',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! PlayerRouteExtra) {
            return Scaffold(
              body: Center(
                child: Text(AppLocalizations.of(context)!.invalidNavigation),
              ),
            );
          }
          return PlayerScreen(
            item: extra.item,
            videoUrl: extra.videoUrl,
            episode: extra.episode,
          );
        },
      ),
    ],
  );
});

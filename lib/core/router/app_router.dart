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
import '../../features/player/presentation/player_screen.dart';
import '../domain/entity/multimedia_item.dart';
import 'package:skystream/shared/widgets/app_scaffold.dart';

/// Typed extra for /details. Use when pushing: context.push('/details', extra: DetailsRouteExtra(...)).
class DetailsRouteExtra {
  const DetailsRouteExtra({required this.item, this.autoPlay = false});
  final MultimediaItem item;
  final bool autoPlay;
}

/// Typed extra for /player. Use when pushing: context.push('/player', extra: PlayerRouteExtra(...)).
class PlayerRouteExtra {
  const PlayerRouteExtra({required this.item, required this.videoUrl});
  final MultimediaItem item;
  final String videoUrl;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  ref.keepAlive();
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final shellNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    initialLocation: '/home',
    navigatorKey: rootNavigatorKey,
    routes: [
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) {
          return AppScaffold(child: child);
        },
        routes: [
          GoRoute(
            path: '/discover',
            builder: (context, state) => const DiscoverScreen(),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryScreen(),
          ),
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
      GoRoute(
        path: '/details',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! DetailsRouteExtra) {
            return const Scaffold(
              body: Center(child: Text('Invalid navigation. Please go back.')),
            );
          }
          return DetailsScreen(item: extra.item, autoPlay: extra.autoPlay);
        },
      ),
      GoRoute(
        path: '/player',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! PlayerRouteExtra) {
            return const Scaffold(
              body: Center(child: Text('Invalid navigation. Please go back.')),
            );
          }
          return PlayerScreen(item: extra.item, videoUrl: extra.videoUrl);
        },
      ),
    ],
  );
});

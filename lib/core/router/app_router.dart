import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/features/home/presentation/home_screen.dart';
import 'package:skystream/features/search/presentation/search_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import 'package:skystream/features/library/presentation/library_screen.dart';
import 'package:skystream/features/settings/presentation/settings_screen.dart';
import '../../features/extensions/screens/extensions_screen.dart';
import '../../features/settings/presentation/developer_options_screen.dart';
import '../../features/details/presentation/details_screen.dart';
import '../../features/player/presentation/player_screen.dart';
import '../domain/entity/multimedia_item.dart';

import 'package:skystream/shared/widgets/app_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final shellNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    initialLocation: '/dashboard',
    navigatorKey: rootNavigatorKey,
    routes: [
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) {
          return AppScaffold(child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
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
          if (state.extra is Map<String, dynamic>) {
            final map = state.extra as Map<String, dynamic>;
            return DetailsScreen(
              item: map['item'] as MultimediaItem,
              autoPlay: map['autoPlay'] as bool? ?? false,
            );
          }
          final item = state.extra as MultimediaItem;
          return DetailsScreen(item: item);
        },
      ),
      GoRoute(
        path: '/player',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extras = state.extra as Map<String, dynamic>;
          final item = extras['item'] as MultimediaItem;
          final videoUrl = extras['url'] as String;
          return PlayerScreen(item: item, videoUrl: videoUrl);
        },
      ),
    ],
  );
});

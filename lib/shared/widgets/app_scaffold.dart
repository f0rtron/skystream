import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/providers/device_info_provider.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/shared/widgets/custom_bottom_nav.dart';
import 'package:virtual_mouse/virtual_mouse.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../features/settings/presentation/general_settings_provider.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  void _onItemTapped(int index, BuildContext context) {
    widget.navigationShell.goBranch(
      index,
      // A common pattern when using bottom navigation bars is to support
      // navigating to the initial location when tapping the item that is
      // already active.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  int _getRouteIndex(String route) {
    switch (route) {
      case '/home':
        return 0;
      case '/search':
        return 1;
      case '/discover':
        return 2;
      case '/library':
        return 3;
      case '/settings':
        return 4;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceProfileAsync = ref.watch(deviceProfileProvider);
    final defaultHome = ref.watch(
      generalSettingsProvider.select((s) => s.defaultHomeScreen),
    );
    final defaultIndex = _getRouteIndex(defaultHome);
    final isAtDefaultHome = widget.navigationShell.currentIndex == defaultIndex;

    return deviceProfileAsync.when(
      data: (profile) {
        // Desktop or TV use Side Navigation
        // Or if the screen is physically wide enough (like iPads/Tablets in landscape)
        // VirtualMouse cursor only shown on TV, not desktop
        if (profile.isTv || context.isTabletOrLarger) {
          final sideNavScaffold = PopScope(
            canPop: isAtDefaultHome,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                widget.navigationShell.goBranch(defaultIndex);
              }
            },
            child: Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    elevation: 8,
                    backgroundColor: Theme.of(
                      context,
                    ).appBarTheme.backgroundColor,
                    selectedIndex: widget.navigationShell.currentIndex,
                    onDestinationSelected: (index) =>
                        _onItemTapped(index, context),
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: 0.0, // Center
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.home_outlined),
                        selectedIcon: const Icon(Icons.home),
                        label: Text(AppLocalizations.of(context)!.home),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.search),
                        label: Text(AppLocalizations.of(context)!.search),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.dashboard_outlined),
                        selectedIcon: const Icon(Icons.dashboard),
                        label: Text(AppLocalizations.of(context)!.discover),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.library_books_outlined),
                        selectedIcon: const Icon(Icons.library_books),
                        label: Text(AppLocalizations.of(context)!.library),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon: const Icon(Icons.settings),
                        label: Text(AppLocalizations.of(context)!.settings),
                      ),
                    ],
                  ),
                  Expanded(child: widget.navigationShell),
                ],
              ),
            ),
          );

          // Wrap with VirtualMouse only on TV
          if (profile.isTv) {
            // Focus wrapper ensures the remote's back key is delivered to Flutter
            // after returning from the player (which captures all key events itself).
            // Without this, back key goes to the OS with nothing focused and is swallowed.
            return VirtualMouse(
              visible: true,
              velocity: 3,
              pointerColor: Theme.of(context).colorScheme.primary,
              child: Focus(
                autofocus: true,
                child: sideNavScaffold,
              ),
            );
          }

          return sideNavScaffold;
        }

        // Mobile uses Bottom Navigation
        return PopScope(
          canPop: isAtDefaultHome,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              widget.navigationShell.goBranch(defaultIndex);
            }
          },
          child: Scaffold(
            body: widget.navigationShell,
            bottomNavigationBar: CustomBottomNavBar(
              currentIndex: widget.navigationShell.currentIndex,
              onTap: (index) => _onItemTapped(index, context),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(
          body: Center(
              child: Text(AppLocalizations.of(context)!.errorPrefix(err.toString())))),
    );
  }
}

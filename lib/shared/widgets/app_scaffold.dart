import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/providers/device_info_provider.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/shared/widgets/custom_bottom_nav.dart';
import 'package:virtual_mouse/virtual_mouse.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final Widget child;
  const AppScaffold({super.key, required this.child});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/discover')) return 2;
    if (location.startsWith('/library')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  bool _isOnHomeTab(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    return location.startsWith('/home');
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/search');
        break;
      case 2:
        context.go('/discover');
        break;
      case 3:
        context.go('/library');
        break;
      case 4:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceProfileAsync = ref.watch(deviceProfileProvider);
    final isHome = _isOnHomeTab(context);

    return deviceProfileAsync.when(
      data: (profile) {
        // Desktop or TV use Side Navigation
        // Or if the screen is physically wide enough (like iPads/Tablets in landscape)
        // VirtualMouse cursor only shown on TV, not desktop
        if (profile.isTv || context.isTabletOrLarger) {
          final sideNavScaffold = PopScope(
            canPop: isHome,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                context.go('/home');
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
                    selectedIndex: _calculateSelectedIndex(context),
                    onDestinationSelected: (index) =>
                        _onItemTapped(index, context),
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: 0.0, // Center
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.search),
                        label: Text('Search'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard),
                        label: Text('Discover'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.library_books_outlined),
                        selectedIcon: Icon(Icons.library_books),
                        label: Text('Library'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                  Expanded(child: widget.child),
                ],
              ),
            ),
          );

          // Wrap with VirtualMouse only on TV
          if (profile.isTv) {
            return VirtualMouse(
              visible: true,
              velocity: 3,
              pointerColor: Theme.of(context).colorScheme.primary,
              child: sideNavScaffold,
            );
          }

          return sideNavScaffold;
        }

        // Mobile uses Bottom Navigation
        return PopScope(
          canPop: isHome,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              context.go('/home');
            }
          },
          child: Scaffold(
            body: widget.child,
            bottomNavigationBar: CustomBottomNavBar(
              currentIndex: _calculateSelectedIndex(context),
              onTap: (index) => _onItemTapped(index, context),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }
}

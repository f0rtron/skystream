import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'widgets/bookmarks_tab.dart';
import 'widgets/downloads_tab.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController();

    // Sync PageView -> TabBar
    _pageController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // Only update TabBar if swipe is happening (not a direct tab tap)
        final page = _pageController.page?.round() ?? 0;
        if (_tabController.index != page) {
          _tabController.animateTo(page);
        }
      }
    });

    // Sync TabBar -> PageView
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _pageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.ease,
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.library),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: AppLocalizations.of(context)!.downloads,
              icon: const Icon(Icons.download_for_offline_rounded),
            ),
            Tab(
              text: AppLocalizations.of(context)!.bookmarks,
              icon: const Icon(Icons.bookmark_rounded),
            ),
          ],
        ),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          _tabController.animateTo(index);
        },
        physics: const BouncingScrollPhysics(),
        children: const [DownloadsTab(), BookmarksTab()],
      ),
    );
  }
}

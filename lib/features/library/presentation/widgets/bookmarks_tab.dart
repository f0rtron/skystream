import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../shared/widgets/multimedia_card.dart';
import '../library_provider.dart';

class BookmarksTab extends ConsumerWidget {
  const BookmarksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryItems = ref.watch(libraryProvider);
    final isLarge = context.isTabletOrLarger;

    final double totalHeight = isLarge ? 180.0 : 150.0;

    if (libraryItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_outline_rounded,
              size: 64,
              color: Theme.of(context).dividerColor,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.libraryEmpty,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(LayoutConstants.spacingMd),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: totalHeight,
        childAspectRatio: 2 / 3.4,
        crossAxisSpacing: LayoutConstants.spacingMd,
        mainAxisSpacing: LayoutConstants.spacingMd,
      ),
      itemCount: libraryItems.length,
      itemBuilder: (context, index) {
        final item = libraryItems[index];
        return MultimediaCard(
          key: ValueKey(item.url),
          imageUrl:
              AppImageFallbacks.poster(item.posterUrl, label: item.title) ?? '',
          title: item.title,
          heroTag: 'lib_bookmark_${item.url}_$index',
          onTap: () =>
              context.push('/details', extra: DetailsRouteExtra(item: item)),
        );
      },
    );
  }
}

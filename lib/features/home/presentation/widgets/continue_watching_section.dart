import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/core/utils/responsive_breakpoints.dart';

import 'package:skystream/features/home/presentation/widgets/continue_watching_card.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import 'package:skystream/shared/widgets/desktop_scroll_wrapper.dart';

class ContinueWatchingSection extends ConsumerStatefulWidget {
  final String title;
  final List<HistoryItem> items;

  const ContinueWatchingSection({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  ConsumerState<ContinueWatchingSection> createState() =>
      _ContinueWatchingSectionState();
}

class _ContinueWatchingSectionState
    extends ConsumerState<ContinueWatchingSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final isLarge = context.isTabletOrLarger;

    final double width = isLarge ? 360.0 : 280.0;
    final double listHeight = isLarge ? 200.0 : 150.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: isLarge ? 24 : 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: isLarge ? 30 : 20,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Clear All History'),
                      content: const Text(
                        'Are you sure you want to remove all items from your watch history?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            ref
                                .read(watchHistoryProvider.notifier)
                                .clearAllHistory();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Watch history cleared'),
                              ),
                            );
                          },
                          child: Text(
                            'Clear All',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear All'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: listHeight,
          child: DesktopScrollWrapper(
            controller: _scrollController,
            showButtons: isLarge, // Show nav buttons on desktop and TV
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: widget.items.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: isLarge ? 24 : 12),
              itemBuilder: (context, index) {
                final historyItem = widget.items[index];
                return ContinueWatchingCard(
                  key: ValueKey(historyItem.item.url),
                  historyItem: historyItem,
                  width: width,
                  isLarge: isLarge,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

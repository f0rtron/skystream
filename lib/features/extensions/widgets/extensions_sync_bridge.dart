import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../providers/extensions_controller.dart';

/// Listens to [extensionsControllerProvider] and syncs installed plugins into
/// [ExtensionManager]. Keeps core independent of the feature; sync is driven from here.
class ExtensionsSyncBridge extends ConsumerWidget {
  const ExtensionsSyncBridge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(extensionsControllerProvider, (previous, next) {
      ref
          .read(extensionManagerProvider.notifier)
          .syncFromPlugins(next.installedPlugins);
    });
    return child;
  }
}

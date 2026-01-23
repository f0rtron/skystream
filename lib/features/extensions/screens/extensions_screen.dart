import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/extensions/models/extension_plugin.dart';
import '../providers/extensions_controller.dart';

class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isFabExtended = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.userScrollDirection ==
            ScrollDirection.reverse &&
        _isFabExtended) {
      setState(() => _isFabExtended = false);
    } else if (_scrollController.position.userScrollDirection ==
            ScrollDirection.forward &&
        !_isFabExtended) {
      setState(() => _isFabExtended = true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for errors
    ref.listen(extensionsControllerProvider, (previous, next) {
      if (previous?.error != next.error && next.error != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Error"),
            content: Text(next.error!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    });

    final state = ref.watch(extensionsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions')),
      body: Builder(
        builder: (context) {
          if (state.isLoading && state.repositories.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.repositories.isEmpty && state.installedPlugins.isEmpty) {
            return const Center(
              child: Text("No repositories or plugins found"),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 80), // Fab space
                itemCount:
                    state.repositories.length +
                    (state.installedPlugins.any((p) => p.isDebug) ? 1 : 0),
                itemBuilder: (context, index) {
                  final debugPlugins = state.installedPlugins
                      .where((p) => p.isDebug)
                      .toList();
                  final hasDebug = debugPlugins.isNotEmpty;

                  // Render Debug Section at index 0 if it exists
                  if (hasDebug && index == 0) {
                    return _buildDebugSection(context, debugPlugins);
                  }

                  // Adjust index for repositories
                  final repoIndex = hasDebug ? index - 1 : index;
                  final repo = state.repositories[repoIndex];
                  final plugins = state.availablePlugins[repo.url] ?? [];

                  return Card(
                    margin: const EdgeInsets.only(
                      bottom: 16,
                      left: 16,
                      right: 16,
                    ),
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      initiallyExpanded: true,
                      backgroundColor: Colors.transparent,
                      collapsedBackgroundColor: Colors.transparent,
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              repo.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () =>
                                _confirmDeleteRepo(context, ref, repo),
                            tooltip: "Remove Repository",
                          ),
                        ],
                      ),
                      children: plugins.asMap().entries.map((entry) {
                        final isLast = entry.key == plugins.length - 1;
                        return Column(
                          children: [
                            if (entry.key == 0)
                              Divider(
                                height: 1,
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.5),
                              ),
                            _PluginTile(plugin: entry.value),
                            if (!isLast)
                              Divider(
                                height: 1,
                                indent: 56,
                                endIndent: 16,
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.5),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: Material(
        elevation: 4,
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0A0A0A)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showAddRepoDialog(context, ref),
          child: Container(
            height: 56,
            constraints: const BoxConstraints(minWidth: 56),
            padding: EdgeInsets.symmetric(horizontal: _isFabExtended ? 16 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: SizedBox(
                    width: _isFabExtended ? null : 0,
                    child: _isFabExtended
                        ? Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              "Add Repo",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugSection(
    BuildContext context,
    List<ExtensionPlugin> debugPlugins,
  ) {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 16,
        left: 16,
        right: 16,
        top: 16, // Extra top padding for first item
      ),
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.orange.withValues(alpha: 0.5),
        ), // Orange border for debug
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: true,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          "Debug Extensions",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
        children: debugPlugins.asMap().entries.map((entry) {
          final isLast = entry.key == debugPlugins.length - 1;
          return Column(
            children: [
              _PluginTile(plugin: entry.value, isDebugSection: true),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _confirmDeleteRepo(BuildContext context, WidgetRef ref, dynamic repo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Remove ${repo.name}?"),
        content: const Text(
          "This will remove the repository and uninstall ALL its plugin.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(extensionsControllerProvider.notifier)
                  .removeRepository(repo.url);
              Navigator.pop(context);
            },
            child: const Text("Remove", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddRepoDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent, // Remove M3 tint
        title: const Text("Add Repository"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Repository URL or Shortcode",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref
                    .read(extensionsControllerProvider.notifier)
                    .addRepository(controller.text);
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}

class _PluginTile extends ConsumerWidget {
  final ExtensionPlugin plugin;
  final bool isDebugSection;

  const _PluginTile({required this.plugin, this.isDebugSection = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If this IS a debug tile, just show basic info
    if (isDebugSection) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.bug_report, color: Colors.orange, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                plugin.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'DEBUG',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          "v${plugin.version} • Asset Plugin",
          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
        ),
        // No actions for debug plugins
      );
    }

    final state = ref.watch(extensionsControllerProvider);

    // Find if installed (STRICT ID match, ignoring debug versions)
    // We explicitly exclude any installed plugin that ends with .debug matching this online plugin
    final installedPlugin = state.installedPlugins
        .cast<ExtensionPlugin?>()
        .firstWhere((p) {
          if (p == null) return false;
          // If the installed plugin is a debug one, NEVER match it to an online plugin
          if (p.isDebug) {
            return false;
          }

          return p.packageId == plugin.packageId ||
              p.internalName == plugin.internalName;
        }, orElse: () => null);

    final isInstalled = installedPlugin != null;
    final updateAvailable = state.availableUpdates[plugin.packageId];

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.extension_outlined,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        plugin.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isInstalled
            ? "v${installedPlugin.version} • Installed"
            : "v${plugin.version} • ${plugin.description ?? ''}",
        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Update Button
          if (isInstalled && updateAvailable != null)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.green),
              tooltip: "Update to v${updateAvailable.version}",
              onPressed: () {
                ref
                    .read(extensionsControllerProvider.notifier)
                    .updatePlugin(updateAvailable);
              },
            ),

          // Install / Delete Button
          if (isInstalled)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                ref
                    .read(extensionsControllerProvider.notifier)
                    .uninstallPlugin(installedPlugin);
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: "Install",
              onPressed: () {
                ref
                    .read(extensionsControllerProvider.notifier)
                    .installPlugin(plugin);
              },
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/extensions/models/extension_plugin.dart';
import '../../../core/extensions/models/extension_repository.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../providers/extensions_controller.dart';
import '../widgets/plugin_settings_dialog.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isFabExtended = ValueNotifier<bool>(true);
  bool _didEnsureInit = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.userScrollDirection ==
            ScrollDirection.reverse &&
        _isFabExtended.value) {
      _isFabExtended.value = false;
    } else if (_scrollController.position.userScrollDirection ==
            ScrollDirection.forward &&
        !_isFabExtended.value) {
      _isFabExtended.value = true;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _isFabExtended.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_didEnsureInit) {
      _didEnsureInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(extensionsControllerProvider.notifier).ensureInitialized();
      });
    }
    // Listen for errors
    ref.listen(extensionsControllerProvider, (previous, next) {
      if (next is ExtensionsError &&
          (previous is! ExtensionsError || previous.message != next.message)) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.error),
            content: Text(next.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
      }
    });

    final state = ref.watch(extensionsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.extensions)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: switch (state) {
            ExtensionsLoading(repositories: []) => const Center(
              child: CircularProgressIndicator(),
            ),
            ExtensionsState()
                when state.repositories.isEmpty &&
                    state.installedPlugins.isEmpty =>
              Center(child: Text(l10n.noReposFound)),
            _ => ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 80), // Fab space
              itemCount: _calculateItemCount(state),
              itemBuilder: (context, index) {
                final debugPlugins = state.installedPlugins
                    .where((p) => p.isDebug)
                    .toList();
                final hasDebug = debugPlugins.isNotEmpty;

                final allAvailablePackageNames = state.availablePlugins.values
                    .expand((list) => list)
                    .map((p) => p.packageName)
                    .toSet();
                final installedOnlyPlugins = state.installedPlugins
                    .where(
                      (p) =>
                          !p.isDebug &&
                          !allAvailablePackageNames.contains(p.packageName),
                    )
                    .toList();
                final hasInstalledOnly = installedOnlyPlugins.isNotEmpty;

                // Render Debug Section
                if (hasDebug && index == 0) {
                  return _buildDebugSection(context, debugPlugins);
                }

                // Render Installed Extensions section
                if (hasInstalledOnly && index == (hasDebug ? 1 : 0)) {
                  return _buildInstalledOnlySection(
                    context,
                    ref,
                    installedOnlyPlugins,
                    hasRepos: state.repositories.isNotEmpty,
                  );
                }

                // Repositories
                final repoIndex =
                    index - (hasDebug ? 1 : 0) - (hasInstalledOnly ? 1 : 0);
                final repo = state.repositories[repoIndex];
                final plugins = state.availablePlugins[repo.url] ?? [];

                return _buildRepositoryCard(
                  context,
                  ref,
                  state,
                  repo,
                  plugins,
                  l10n,
                );
              },
            ),
          },
        ),
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _isFabExtended,
        builder: (context, isFabExtended, _) {
          return Material(
            elevation: 4,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showAddRepoDialog(context, ref),
              child: Container(
                height: 56,
                constraints: const BoxConstraints(minWidth: 56),
                padding: EdgeInsets.symmetric(
                  horizontal: isFabExtended ? LayoutConstants.spacingMd : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: SizedBox(
                        width: isFabExtended ? null : 0,
                        child: isFabExtended
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  left: LayoutConstants.spacingSm,
                                ),
                                child: Text(
                                  l10n.addRepo,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
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
          );
        },
      ),
    );
  }

  Widget _buildInstalledOnlySection(
    BuildContext context,
    WidgetRef ref,
    List<ExtensionPlugin> plugins, {
    required bool hasRepos,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.all(LayoutConstants.spacingMd),
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
          horizontal: LayoutConstants.spacingMd,
          vertical: LayoutConstants.spacingXs,
        ),
        title: Row(
          children: [
            Icon(
              Icons.extension,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: LayoutConstants.spacingSm),
            Text(
              l10n.extensionsNotInRepos,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        subtitle: Text(
          hasRepos ? l10n.noLongerInRepo : l10n.addRepoToBrowse,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        children: plugins.asMap().entries.map((entry) {
          final isLast = entry.key == plugins.length - 1;
          return Column(
            children: [
              if (entry.key == 0)
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              _PluginTile(plugin: entry.value),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDebugSection(
    BuildContext context,
    List<ExtensionPlugin> debugPlugins,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.all(LayoutConstants.spacingMd),
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: true,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: LayoutConstants.spacingMd,
          vertical: LayoutConstants.spacingXs,
        ),
        title: Text(
          l10n.debugExtensions,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.tertiary,
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

  int _calculateItemCount(ExtensionsState state) {
    final hasDebug = state.installedPlugins.any((p) => p.isDebug);
    final allAvailablePackageNames = state.availablePlugins.values
        .expand((list) => list)
        .map((p) => p.packageName)
        .toSet();
    final hasInstalledOnly = state.installedPlugins.any(
      (p) => !p.isDebug && !allAvailablePackageNames.contains(p.packageName),
    );

    return (hasDebug ? 1 : 0) +
        (hasInstalledOnly ? 1 : 0) +
        state.repositories.length;
  }

  Widget _buildRepositoryCard(
    BuildContext context,
    WidgetRef ref,
    ExtensionsState state,
    ExtensionRepository repo,
    List<ExtensionPlugin> plugins,
    AppLocalizations l10n,
  ) {
    // True when every plugin in this repo is already installed (non-debug).
    final allInstalled = plugins.isNotEmpty &&
        plugins.every(
          (p) => state.installedPlugins.any(
            (i) => !i.isDebug && i.packageName == p.packageName,
          ),
        );

    final isLoading = state is ExtensionsLoading;

    return Card(
      margin: const EdgeInsets.only(
        bottom: LayoutConstants.spacingMd,
        left: LayoutConstants.spacingMd,
        right: LayoutConstants.spacingMd,
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
        // Start collapsed — repos can be individually expanded.
        initiallyExpanded: false,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: LayoutConstants.spacingMd,
          vertical: LayoutConstants.spacingXs,
        ),
        // Embed description directly in the title so the buttons stay
        // vertically centred with the whole block and there is no extra
        // gap that the ExpansionTile subtitle property introduces.
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    repo.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (repo.description?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 2),
                    Text(
                      repo.description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              // Download-all / all-installed indicator.
              Semantics(
                button: true,
                label: l10n.downloadAllProviders,
                child: IconButton(
                  focusColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  icon: Icon(
                    allInstalled
                        ? Icons.check_circle_outline
                        : Icons.download,
                    color: allInstalled
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: allInstalled || plugins.isEmpty
                      ? null
                      : () {
                          ref
                              .read(extensionsControllerProvider.notifier)
                              .installPlugins(plugins);
                        },
                  tooltip: allInstalled
                      ? 'All installed'
                      : l10n.downloadAllProviders,
                ),
              ),
              IconButton(
                focusColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _confirmDeleteRepo(context, ref, repo),
                tooltip: l10n.removeRepository,
              ),
            ],
          ],
        ),
        children: plugins.asMap().entries.map((entry) {
          final isLast = entry.key == plugins.length - 1;
          return Column(
            children: [
              if (entry.key == 0)
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              _PluginTile(plugin: entry.value),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _confirmDeleteRepo(
    BuildContext context,
    WidgetRef ref,
    ExtensionRepository repo,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeRepoConfirm(repo.name)),
        content: Text(l10n.removeRepoWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(extensionsControllerProvider.notifier)
                  .removeRepository(repo.url);
              Navigator.pop(context);
            },
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddRepoDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.addRepository),
        content: CustomTextField(
          controller: controller,
          hintText: l10n.repoUrlOrShortcode,
          autofocus: false,
          textInputAction: TextInputAction.done,
        ),
        actions: [
          CustomButton(
            showFocusHighlight: isTv,
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: LayoutConstants.spacingXs),
          CustomButton(
            autofocus: true,
            isPrimary: true,
            showFocusHighlight: isTv,
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref
                    .read(extensionsControllerProvider.notifier)
                    .addRepository(controller.text);
                Navigator.pop(context);
              }
            },
            child: Text(l10n.addRepo),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plugin tile
// ---------------------------------------------------------------------------

class _PluginTile extends ConsumerWidget {
  final ExtensionPlugin plugin;
  final bool isDebugSection;

  const _PluginTile({required this.plugin, this.isDebugSection = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    if (isDebugSection) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(LayoutConstants.spacingXs),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .tertiary
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.bug_report,
            color: Theme.of(context).colorScheme.tertiary,
            size: 20,
          ),
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
            const SizedBox(width: LayoutConstants.spacingXs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.debug,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          "v${plugin.version} • ${l10n.assetPlugin}",
          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
        ),
      );
    }

    final state = ref.watch(extensionsControllerProvider);

    final installedPlugin = state.installedPlugins
        .cast<ExtensionPlugin?>()
        .firstWhere(
          (p) {
            if (p == null) return false;
            if (p.isDebug) return false;
            return p.packageName == plugin.packageName;
          },
          orElse: () => null,
        );

    final isInstalled = installedPlugin != null;
    final updateAvailable = state.availableUpdates[plugin.packageName];

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(LayoutConstants.spacingXs),
        decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
      subtitle: _buildSubtitle(context, isInstalled, installedPlugin),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Update button
          if (isInstalled && updateAvailable != null)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.green),
              tooltip: l10n.updateTo(updateAvailable.version.toString()),
              onPressed: () {
                ref
                    .read(extensionsControllerProvider.notifier)
                    .updatePlugin(updateAvailable);
              },
            ),

          // Settings button (shown when plugin declares domains or providers)
          if (isInstalled &&
              ((installedPlugin.domains?.isNotEmpty ?? false) ||
                  (installedPlugin.providers?.isNotEmpty ?? false)))
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: l10n.settings,
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) =>
                      PluginSettingsDialog(plugin: installedPlugin),
                );
              },
            ),

          // Install / delete button
          if (isInstalled)
            IconButton(
              icon: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: l10n.delete,
              onPressed: () {
                ref
                    .read(extensionsControllerProvider.notifier)
                    .uninstallPlugin(installedPlugin);
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: l10n.install,
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

  /// Subtitle widget: description · version/authors line · language chips.
  Widget _buildSubtitle(
    BuildContext context,
    bool isInstalled,
    ExtensionPlugin? installedPlugin,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Description uses bodyMedium so it's comfortably readable.
    final descStyle = textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    // Version + authors line uses bodySmall.
    final metaStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    // Version from installed copy if present, otherwise from the catalog.
    final version = 'v${isInstalled ? installedPlugin!.version : plugin.version}';

    // Authors: up to 2, prefixed with "By".
    final authors = plugin.authors.take(2).join(', ');

    final metaParts = [
      version,
      if (authors.isNotEmpty) 'By $authors',
    ];
    final metaLine = metaParts.join(' • ');

    final desc = plugin.description;
    final hasDesc = desc != null && desc.isNotEmpty;
    final hasLanguages = plugin.languages.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasDesc)
          Text(
            desc,
            style: descStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 2),
        Text(
          metaLine,
          style: metaStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasLanguages) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: plugin.languages.take(5).map((lang) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  lang.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

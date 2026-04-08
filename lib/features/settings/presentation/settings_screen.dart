import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/theme/theme_provider.dart';

import 'widgets/settings_widgets.dart';
import 'widgets/settings_dialogs.dart';
import 'package:go_router/go_router.dart';
import 'player_settings_provider.dart';
import 'general_settings_provider.dart';

import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/network/doh_service.dart';

// Simple provider for app version
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} +${info.buildNumber}';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionAsync = ref.watch(appVersionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final generalSettings = ref.watch(generalSettingsProvider);

    final playerSettings =
        ref.watch(playerSettingsProvider).asData?.value ??
        const PlayerSettings();

    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.only(bottom: LayoutConstants.spacingLg),
            children: [
              const SizedBox(height: LayoutConstants.spacingXs),
              SettingsGroup(
                title: l10n.general,
                children: [
                  SettingsTile(
                    icon: Icons.dark_mode_rounded,
                    title: l10n.appTheme,
                    subtitle: themeMode == ThemeMode.system
                        ? l10n.system
                        : (themeMode == ThemeMode.dark ? l10n.dark : l10n.light),
                    onTap: () => showThemeDialog(context, ref, themeMode),
                  ),
                  SettingsTile(
                    icon: Icons.history_rounded,
                    title: l10n.recordWatchHistory,
                    subtitle: generalSettings.watchHistoryEnabled
                        ? l10n.enabled
                        : l10n.disabled,
                    trailing: Switch(
                      value: generalSettings.watchHistoryEnabled,
                      onChanged: (val) => ref
                          .read(generalSettingsProvider.notifier)
                          .setWatchHistoryEnabled(val),
                    ),
                    isLast: true,
                    onTap: () => ref
                        .read(generalSettingsProvider.notifier)
                        .setWatchHistoryEnabled(
                          !generalSettings.watchHistoryEnabled,
                        ),
                  ),
                  SettingsTile(
                    icon: Icons.home_rounded,
                    title: l10n.defaultHomeScreen,
                    subtitle: getHomeScreenLabel(generalSettings.defaultHomeScreen, l10n),
                    isLast: true,
                    onTap: () => showDefaultHomeScreenDialog(
                      context,
                      ref,
                      generalSettings.defaultHomeScreen,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.translate_rounded,
                    title: l10n.language,
                    subtitle: Localizations.localeOf(context).languageCode == 'en'
                        ? l10n.english
                        : (Localizations.localeOf(context).languageCode == 'hi'
                            ? l10n.hindi
                            : (Localizations.localeOf(context).languageCode == 'kn'
                                ? l10n.kannada
                                : l10n.unknown)),
                    isLast: true,
                    onTap: () => showLanguageDialog(
                      context,
                      ref,
                      ref.read(localeProvider),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: l10n.player,
                children: [
                  SettingsTile(
                    icon: Icons.smart_display_rounded,
                    title: l10n.defaultPlayer,
                    subtitle: getPlayerDisplayName(
                      playerSettings.preferredPlayer,
                      l10n,
                    ),
                    onTap: () => showDefaultPlayerDialog(
                      context,
                      ref,
                      playerSettings.preferredPlayer,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.swipe_vertical_rounded,
                    title: l10n.leftGesture,
                    subtitle:
                        playerSettings.leftGesture.name[0].toUpperCase() +
                        playerSettings.leftGesture.name.substring(1),
                    onTap: () => showGestureDialog(
                      context,
                      ref,
                      true,
                      playerSettings.leftGesture,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.swipe_vertical_rounded,
                    title: l10n.rightGesture,
                    subtitle:
                        playerSettings.rightGesture.name[0].toUpperCase() +
                        playerSettings.rightGesture.name.substring(1),
                    onTap: () => showGestureDialog(
                      context,
                      ref,
                      false,
                      playerSettings.rightGesture,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.touch_app_rounded,
                    title: l10n.doubleTapToSeek,
                    subtitle: playerSettings.doubleTapEnabled
                        ? l10n.enabled
                        : l10n.disabled,
                    trailing: Switch(
                      value: playerSettings.doubleTapEnabled,
                      onChanged: (val) => ref
                          .read(playerSettingsProvider.notifier)
                          .setDoubleTapEnabled(val),
                    ),
                    onTap: () => ref
                        .read(playerSettingsProvider.notifier)
                        .setDoubleTapEnabled(!playerSettings.doubleTapEnabled),
                  ),
                  SettingsTile(
                    icon: Icons.swipe_rounded,
                    title: l10n.swipeToSeek,
                    subtitle: playerSettings.swipeSeekEnabled
                        ? l10n.enabled
                        : l10n.disabled,
                    trailing: Switch(
                      value: playerSettings.swipeSeekEnabled,
                      onChanged: (val) => ref
                          .read(playerSettingsProvider.notifier)
                          .setSwipeSeekEnabled(val),
                    ),
                    onTap: () => ref
                        .read(playerSettingsProvider.notifier)
                        .setSwipeSeekEnabled(!playerSettings.swipeSeekEnabled),
                  ),
                  SettingsTile(
                    icon: Icons.av_timer_rounded,
                    title: l10n.seekDuration,
                    subtitle: formatSeekDuration(playerSettings.seekDuration, l10n),
                    onTap: () => showDurationDialog(
                      context,
                      ref,
                      playerSettings.seekDuration,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.timer_outlined,
                    title: l10n.bufferDepth,
                    subtitle: formatReadahead(playerSettings.readaheadSeconds, l10n),
                    onTap: () => showReadaheadDialog(
                      context,
                      ref,
                      playerSettings.readaheadSeconds,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.aspect_ratio_rounded,
                    title: l10n.defaultResizeMode,
                    subtitle: playerSettings.defaultResizeMode,
                    onTap: () => showResizeDialog(
                      context,
                      ref,
                      playerSettings.defaultResizeMode,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.high_quality_rounded,
                    title: l10n.hardwareDecoding,
                    subtitle: playerSettings.hardwareDecoding
                        ? '${l10n.enabled} (${l10n.recommended})'
                        : l10n.disabled,
                    trailing: Switch(
                      value: playerSettings.hardwareDecoding,
                      onChanged: (val) => ref
                          .read(playerSettingsProvider.notifier)
                          .setHardwareDecoding(val),
                    ),
                    isLast: true,
                    onTap: () => ref
                        .read(playerSettingsProvider.notifier)
                        .setHardwareDecoding(!playerSettings.hardwareDecoding),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              Builder(
                builder: (context) {
                  final dohState =
                      ref.watch(dohSettingsProvider).asData?.value ??
                      const DohSettings();
                  return SettingsGroup(
                    title: l10n.network,
                    children: [
                      SettingsTile(
                        icon: Icons.dns_rounded,
                        title: l10n.dnsOverHttps,
                        subtitle: dohState.enabled
                            ? '${l10n.on} (${getDohProviderLabel(dohState.provider, dohState.customUrl, l10n)})'
                            : l10n.off,
                        trailing: Switch(
                          value: dohState.enabled,
                          onChanged: (val) {
                            ref
                                .read(dohSettingsProvider.notifier)
                                .setEnabled(val);
                          },
                        ),
                        onTap: () {
                          ref
                              .read(dohSettingsProvider.notifier)
                              .setEnabled(!dohState.enabled);
                        },
                      ),
                      if (dohState.enabled)
                        SettingsTile(
                          icon: Icons.cloud_rounded,
                          title: l10n.dohProvider,
                          subtitle: getDohProviderLabel(
                            dohState.provider,
                            dohState.customUrl,
                            l10n,
                          ),
                          isLast: true,
                          onTap: () => showDohProviderDialog(context, ref),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: l10n.extensions,
                children: [
                  SettingsTile(
                    icon: Icons.extension_rounded,
                    title: l10n.manageExtensions,
                    subtitle: l10n.installRemoveProviders,
                    isLast: true,
                    onTap: () => context.go('/settings/extensions'),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: l10n.appData,
                children: [
                  SettingsTile(
                    icon: Icons.restore_rounded,
                    title: l10n.resetDataKeepExtensions,
                    subtitle: l10n.resetDataSubtitle,
                    onTap: () => showResetDataDialog(context, ref),
                  ),
                  SettingsTile(
                    icon: Icons.delete_forever_rounded,
                    title: l10n.factoryReset,
                    subtitle: l10n.factoryResetSubtitle,
                    isLast: true,
                    onTap: () => showFactoryResetDialog(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: l10n.developer,
                children: [
                  SettingsTile(
                    icon: Icons.developer_mode_rounded,
                    title: l10n.developerOptions,
                    subtitle: l10n.developerOptionsSubtitle,
                    isLast: true,
                    onTap: () => context.go('/settings/developer'),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: l10n.about,
                children: [
                  SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: l10n.version,
                    subtitle: versionAsync.when(
                      data: (v) => v,
                      loading: () => l10n.loading,
                      error: (err, stack) => l10n.unknown,
                    ),
                    trailing: const SizedBox.shrink(),
                    isLast: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

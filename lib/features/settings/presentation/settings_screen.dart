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

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.only(bottom: LayoutConstants.spacingLg),
            children: [
              const SizedBox(height: LayoutConstants.spacingXs),
              SettingsGroup(
                title: 'General',
                children: [
                  SettingsTile(
                    icon: Icons.dark_mode_rounded,
                    title: 'App Theme',
                    subtitle: themeMode == ThemeMode.system
                        ? 'System'
                        : (themeMode == ThemeMode.dark ? 'Dark' : 'Light'),
                    onTap: () => showThemeDialog(context, ref, themeMode),
                  ),
                  SettingsTile(
                    icon: Icons.history_rounded,
                    title: 'Record Watch History',
                    subtitle: generalSettings.watchHistoryEnabled
                        ? 'Enabled'
                        : 'Disabled',
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
                    title: 'Default Home Screen',
                    subtitle: getHomeScreenLabel(generalSettings.defaultHomeScreen),
                    isLast: true,
                    onTap: () => showDefaultHomeScreenDialog(
                      context,
                      ref,
                      generalSettings.defaultHomeScreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: 'Player',
                children: [
                  SettingsTile(
                    icon: Icons.smart_display_rounded,
                    title: 'Default Player',
                    subtitle: getPlayerDisplayName(
                      playerSettings.preferredPlayer,
                    ),
                    onTap: () => showDefaultPlayerDialog(
                      context,
                      ref,
                      playerSettings.preferredPlayer,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.swipe_vertical_rounded,
                    title: 'Left Gesture',
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
                    title: 'Right Gesture',
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
                    title: 'Double Tap to Seek',
                    subtitle: playerSettings.doubleTapEnabled
                        ? 'Enabled'
                        : 'Disabled',
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
                    title: 'Swipe to Seek',
                    subtitle: playerSettings.swipeSeekEnabled
                        ? 'Enabled'
                        : 'Disabled',
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
                    title: 'Seek Duration',
                    subtitle: formatSeekDuration(playerSettings.seekDuration),
                    onTap: () => showDurationDialog(
                      context,
                      ref,
                      playerSettings.seekDuration,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.timer_outlined,
                    title: 'Buffer depth',
                    subtitle: formatReadahead(playerSettings.readaheadSeconds),
                    onTap: () => showReadaheadDialog(
                      context,
                      ref,
                      playerSettings.readaheadSeconds,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.aspect_ratio_rounded,
                    title: 'Default Resize Mode',
                    subtitle: playerSettings.defaultResizeMode,
                    onTap: () => showResizeDialog(
                      context,
                      ref,
                      playerSettings.defaultResizeMode,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.high_quality_rounded,
                    title: 'Hardware Decoding',
                    subtitle: playerSettings.hardwareDecoding
                        ? 'Enabled (Recommended)'
                        : 'Disabled',
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
                    title: 'Network',
                    children: [
                      SettingsTile(
                        icon: Icons.dns_rounded,
                        title: 'DNS over HTTPS',
                        subtitle: dohState.enabled
                            ? 'On (${getDohProviderLabel(dohState.provider, dohState.customUrl)})'
                            : 'Off',
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
                          title: 'DoH Provider',
                          subtitle: getDohProviderLabel(
                            dohState.provider,
                            dohState.customUrl,
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
                title: 'Extensions',
                children: [
                  SettingsTile(
                    icon: Icons.extension_rounded,
                    title: 'Manage Extensions',
                    subtitle: 'Install or remove providers',
                    isLast: true,
                    onTap: () => context.go('/settings/extensions'),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: 'App Data',
                children: [
                  SettingsTile(
                    icon: Icons.restore_rounded,
                    title: 'Reset Data (Keep Extensions)',
                    subtitle: 'Clear settings & database, keep plugin',
                    onTap: () => showResetDataDialog(context, ref),
                  ),
                  SettingsTile(
                    icon: Icons.delete_forever_rounded,
                    title: 'Factory Reset',
                    subtitle: 'Delete all data, settings, and extensions',
                    isLast: true,
                    onTap: () => showFactoryResetDialog(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: 'Developer',
                children: [
                  SettingsTile(
                    icon: Icons.developer_mode_rounded,
                    title: 'Developer Options',
                    subtitle: 'Debug tools & local play',
                    isLast: true,
                    onTap: () => context.go('/settings/developer'),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingLg),
              SettingsGroup(
                title: 'About',
                children: [
                  SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'Version',
                    subtitle: versionAsync.when(
                      data: (v) => v,
                      loading: () => 'Loading...',
                      error: (err, stack) => 'Unknown',
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

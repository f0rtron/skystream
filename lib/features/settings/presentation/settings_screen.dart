import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../core/utils/app_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../shared/widgets/tv_input_widgets.dart';

import 'widgets/settings_widgets.dart';
import 'package:go_router/go_router.dart';
import 'player_settings_provider.dart';

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

    final playerSettings = ref.watch(playerSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SizedBox(height: 8),
              SettingsGroup(
                title: 'General',
                children: [
                  SettingsTile(
                    icon: Icons.dark_mode_rounded,
                    title: 'App Theme',
                    subtitle: themeMode == ThemeMode.system
                        ? 'System'
                        : (themeMode == ThemeMode.dark ? 'Dark' : 'Light'),
                    isLast: true,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          surfaceTintColor: Colors.transparent,
                          title: const Text('Choose Theme'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _themeOption(
                                context,
                                ref,
                                'System',
                                ThemeMode.system,
                                themeMode,
                              ),
                              _themeOption(
                                context,
                                ref,
                                'Dark',
                                ThemeMode.dark,
                                themeMode,
                              ),
                              _themeOption(
                                context,
                                ref,
                                'Light',
                                ThemeMode.light,
                                themeMode,
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SettingsGroup(
                title: 'Player',
                children: [
                  SettingsTile(
                    icon: Icons.swipe_vertical_rounded,
                    title: 'Left Gesture',
                    subtitle:
                        playerSettings.leftGesture.name[0].toUpperCase() +
                        playerSettings.leftGesture.name.substring(1),
                    onTap: () => _showGestureDialog(
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
                    onTap: () => _showGestureDialog(
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
                    subtitle: _formatSeekDuration(playerSettings.seekDuration),
                    onTap: () => _showDurationDialog(
                      context,
                      ref,
                      playerSettings.seekDuration,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.aspect_ratio_rounded,
                    title: 'Default Resize Mode',
                    subtitle: playerSettings.defaultResizeMode,
                    onTap: () => _showResizeDialog(
                      context,
                      ref,
                      playerSettings.defaultResizeMode,
                    ),
                  ),
                  SettingsTile(
                    icon: Icons.subtitles_rounded,
                    title: 'Subtitles',
                    subtitle: 'Customize appearance',
                    onTap: () =>
                        _showSubtitleDialog(context, ref, playerSettings),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 24),
              SettingsGroup(
                title: 'App Data',
                children: [
                  SettingsTile(
                    icon: Icons.restore_rounded,
                    title: 'Reset Data (Keep Extensions)',
                    subtitle: 'Clear settings & database, keep plugin',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          surfaceTintColor: Colors.transparent,
                          title: const Text('Reset Data?'),
                          content: const Text(
                            'This will clear Settings, Favorites, and History. Your installed Extensions will be SAVED.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);

                                // Clear Preferences ONLY
                                await ref
                                    .read(storageServiceProvider)
                                    .clearPreferences();

                                // Restart App
                                if (context.mounted)
                                  await AppUtils.restartApp(context);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.orange,
                              ),
                              child: const Text('Reset Data'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  SettingsTile(
                    icon: Icons.delete_forever_rounded,
                    title: 'Factory Reset',
                    subtitle: 'Delete all data, settings, and extensions',
                    isLast: true,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          surfaceTintColor: Colors.transparent,
                          title: const Text('Factory Reset?'),
                          content: const Text(
                            'This will delete EVERYTHING: Favorites, History, Settings, and ALL Extensions. This cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                // Deep Clean (Extensions, Prefs, Hive)
                                await ref
                                    .read(storageServiceProvider)
                                    .deleteAllData();

                                // Restart App
                                if (context.mounted)
                                  await AppUtils.restartApp(context);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Factory Reset'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 24),
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

  Widget _themeOption(
    BuildContext context,
    WidgetRef ref,
    String title,
    ThemeMode value,
    ThemeMode current,
  ) {
    return RadioListTile<ThemeMode>(
      title: Text(title),
      value: value,
      groupValue: current,
      onChanged: (val) {
        if (val != null) {
          ref.read(themeModeProvider.notifier).setThemeMode(val);
          Navigator.pop(context);
        }
      },
    );
  }

  void _showGestureDialog(
    BuildContext context,
    WidgetRef ref,
    bool isLeft,
    PlayerGesture current,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Text('Select ${isLeft ? "Left" : "Right"} Gesture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: PlayerGesture.values.map((g) {
            return RadioListTile<PlayerGesture>(
              title: Text(g.name[0].toUpperCase() + g.name.substring(1)),
              value: g,
              groupValue: current,
              onChanged: (val) {
                if (val != null) {
                  if (isLeft) {
                    ref
                        .read(playerSettingsProvider.notifier)
                        .setLeftGesture(val);
                  } else {
                    ref
                        .read(playerSettingsProvider.notifier)
                        .setRightGesture(val);
                  }
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatSeekDuration(int seconds) {
    if (seconds >= 60) {
      return '${seconds ~/ 60} min';
    }
    return '$seconds sec';
  }

  void _showDurationDialog(BuildContext context, WidgetRef ref, int current) {
    final options = [5, 10, 15, 20, 30, 60, 120];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Select Seek Duration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((sec) {
            return RadioListTile<int>(
              title: Text(_formatSeekDuration(sec)),
              value: sec,
              groupValue: current,
              onChanged: (val) {
                if (val != null) {
                  ref
                      .read(playerSettingsProvider.notifier)
                      .setSeekDuration(val);
                  Navigator.pop(context);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showResizeDialog(BuildContext context, WidgetRef ref, String current) {
    final options = ["Fit", "Zoom", "Stretch"];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text("Default Resize Mode"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (e) => RadioListTile<String>(
                  title: Text(e),
                  value: e,
                  groupValue: current,
                  onChanged: (val) {
                    if (val != null) {
                      ref
                          .read(playerSettingsProvider.notifier)
                          .setDefaultResizeMode(val);
                      Navigator.pop(ctx);
                    }
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _showSubtitleDialog(
    BuildContext context,
    WidgetRef ref,
    PlayerSettings settings,
  ) {
    double size = settings.subtitleSize;
    bool showBackground = settings.subtitleBackgroundColor != 0;
    final isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            surfaceTintColor: Colors.transparent,
            title: const Text("Subtitle Settings"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Size: ${size.toInt()}"),
                TvSlider(
                  value: size,
                  min: 10,
                  max: 80,
                  divisions: 70,
                  step: 1.0,
                  onChanged: (v) => setState(() => size = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text("Background"),
                  value: showBackground,
                  onChanged: (v) => setState(() => showBackground = v),
                ),
              ],
            ),
            actions: [
              TvButton(
                showFocusHighlight: isTv,
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  "Cancel",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TvButton(
                autofocus: true,
                isPrimary: true,
                showFocusHighlight: isTv,
                onPressed: () {
                  // 0x99000000 is ~60% opacity black
                  final bg = showBackground ? 0x99000000 : 0x00000000;
                  ref
                      .read(playerSettingsProvider.notifier)
                      .setSubtitleSettings(size, settings.subtitleColor, bg);
                  Navigator.pop(ctx);
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/custom_widgets.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../core/services/external_player_service.dart';
import '../../../../core/network/doh_service.dart';
import '../../../../core/storage/settings_repository.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/app_utils.dart';
import '../player_settings_provider.dart';
import '../general_settings_provider.dart';

/// Returns a human-readable label for a home screen route.
String getHomeScreenLabel(String route) {
  switch (route) {
    case '/home':
      return 'Home';
    case '/discover':
      return 'Discover';
    case '/search':
      return 'Search';
    case '/library':
      return 'Library';
    default:
      return 'Home';
  }
}

/// Shows a dialog to pick the default home screen.
void showDefaultHomeScreenDialog(
  BuildContext context,
  WidgetRef ref,
  String current,
) {
  final options = [
    {'label': 'Home', 'route': '/home'},
    {'label': 'Discover', 'route': '/discover'},
    {'label': 'Search', 'route': '/search'},
    {'label': 'Library', 'route': '/library'},
  ];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Default Home Screen'),
      content: RadioGroup<String>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          ref.read(generalSettingsProvider.notifier).setDefaultHomeScreen(val);
          Navigator.pop(context);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            return RadioListTile<String>(
              title: Text(opt['label']!),
              value: opt['route']!,
            );
          }).toList(),
        ),
      ),
    ),
  );
}

/// Helper to create a theme-option RadioListTile.
Widget buildThemeOption(String title, ThemeMode value) {
  return RadioListTile<ThemeMode>(title: Text(title), value: value);
}

/// Formats seek duration for display (e.g. "10 sec", "2 min").
String formatSeekDuration(int seconds) {
  if (seconds >= 60) {
    return '${seconds ~/ 60} min';
  }
  return '$seconds sec';
}

/// Formats readahead seconds for display (e.g. "5 min", "10 min").
String formatReadahead(int seconds) {
  return '${seconds ~/ 60} min';
}

/// Returns a human-readable name for a player ID.
String getPlayerDisplayName(String? playerId) {
  if (playerId == null) return 'Internal (media_kit)';
  final player = ExternalPlayerService.instance.getPlayerById(playerId);
  return player?.displayName ?? playerId;
}

/// Returns a human-readable label for a DoH provider.
String getDohProviderLabel(DohProvider provider, String customUrl) {
  switch (provider) {
    case DohProvider.cloudflare:
      return 'Cloudflare';
    case DohProvider.google:
      return 'Google';
    case DohProvider.adguard:
      return 'AdGuard';
    case DohProvider.dnsWatch:
      return 'DNS.Watch';
    case DohProvider.quad9:
      return 'Quad9';
    case DohProvider.dnsSb:
      return 'DNS.SB';
    case DohProvider.canadianShield:
      return 'Canadian Shield';
    case DohProvider.custom:
      return customUrl.isNotEmpty
          ? Uri.tryParse(customUrl)?.host ?? customUrl
          : 'Custom (not set)';
  }
}

/// Shows a dialog to pick the left/right swipe gesture.
void showGestureDialog(
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
      content: RadioGroup<PlayerGesture>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          if (isLeft) {
            ref.read(playerSettingsProvider.notifier).setLeftGesture(val);
          } else {
            ref.read(playerSettingsProvider.notifier).setRightGesture(val);
          }
          Navigator.pop(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlayerGesture.values.map((g) {
              return RadioListTile<PlayerGesture>(
                title: Text(g.name[0].toUpperCase() + g.name.substring(1)),
                value: g,
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

/// Shows a dialog to pick the seek duration.
void showDurationDialog(BuildContext context, WidgetRef ref, int current) {
  final options = [5, 10, 15, 20, 30, 60, 120];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Select Seek Duration'),
      content: RadioGroup<int>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          ref.read(playerSettingsProvider.notifier).setSeekDuration(val);
          Navigator.pop(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((sec) {
              return RadioListTile<int>(
                title: Text(formatSeekDuration(sec)),
                value: sec,
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

/// Shows a dialog to pick the default resize mode.
void showResizeDialog(BuildContext context, WidgetRef ref, String current) {
  final options = ["Fit", "Zoom", "Stretch"];
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text("Default Resize Mode"),
      content: RadioGroup<String>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          ref.read(playerSettingsProvider.notifier).setDefaultResizeMode(val);
          Navigator.pop(ctx);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((e) => RadioListTile<String>(title: Text(e), value: e))
              .toList(),
        ),
      ),
    ),
  );
}

/// Shows a dialog to pick the readahead duration (5-10 min).
void showReadaheadDialog(BuildContext context, WidgetRef ref, int current) {
  // 1 to 20 minutes in 1-minute steps
  final options = List.generate(20, (i) => (1 + i) * 60);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Select Buffer depth'),
      content: RadioGroup<int>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          ref.read(playerSettingsProvider.notifier).setReadaheadSeconds(val);
          Navigator.pop(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((sec) {
              return RadioListTile<int>(
                title: Text(formatReadahead(sec)),
                value: sec,
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

/// Shows a dialog for subtitle size + background settings.
void showSubtitleDialog(
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
              CustomSlider(
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
            CustomButton(
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
            CustomButton(
              autofocus: true,
              isPrimary: true,
              showFocusHighlight: isTv,
              onPressed: () {
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

/// Shows a dialog to pick the default player (internal or external).
void showDefaultPlayerDialog(
  BuildContext context,
  WidgetRef ref,
  String? currentPlayerId,
) {
  final platformPlayers = ExternalPlayerService.instance
      .getPlayersForPlatform();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Default Player'),
      content: SingleChildScrollView(
        child: RadioGroup<String?>(
          groupValue: currentPlayerId,
          onChanged: (val) {
            ref.read(playerSettingsProvider.notifier).setPreferredPlayer(val);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RadioListTile<String?>(
                title: Text('Internal (media_kit)'),
                subtitle: Text('Built-in player'),
                secondary: Icon(Icons.play_circle_filled_rounded),
                value: null,
              ),
              const Divider(),
              ...platformPlayers.map((player) {
                return RadioListTile<String?>(
                  title: Text(player.displayName),
                  secondary: Icon(player.icon),
                  value: player.id,
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shows a dialog to pick the DNS-over-HTTPS provider.
void showDohProviderDialog(BuildContext context, WidgetRef ref) {
  final initialSettings = ref.read(dohSettingsProvider).asData?.value;
  var currentProvider = initialSettings?.provider ?? DohProvider.cloudflare;
  final controller = TextEditingController(
    text: initialSettings?.customUrl ?? '',
  );

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          surfaceTintColor: Colors.transparent,
          title: const Text('DoH Provider'),
          content: SingleChildScrollView(
            child: RadioGroup<DohProvider>(
              groupValue: currentProvider,
              onChanged: (val) {
                if (val == null) return;

                setState(() {
                  currentProvider = val;
                });

                // Auto-save and close if it's a preset provider
                if (val != DohProvider.custom) {
                  ref.read(dohSettingsProvider.notifier).setProvider(val);
                  ref.read(dohSettingsProvider.notifier).clearCache();
                  Navigator.pop(ctx);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile<DohProvider>(
                    title: Text('Cloudflare'),
                    subtitle: Text('1.1.1.1'),
                    value: DohProvider.cloudflare,
                  ),
                  const RadioListTile<DohProvider>(
                    title: Text('Google'),
                    subtitle: Text('8.8.8.8'),
                    value: DohProvider.google,
                  ),
                  const RadioListTile<DohProvider>(
                    title: Text('AdGuard'),
                    subtitle: Text('dns.adguard.com'),
                    value: DohProvider.adguard,
                  ),
                  const RadioListTile<DohProvider>(
                    title: Text('DNS.Watch'),
                    subtitle: Text('resolver2.dns.watch'),
                    value: DohProvider.dnsWatch,
                  ),
                  const RadioListTile<DohProvider>(
                    title: Text('Quad9'),
                    subtitle: Text('9.9.9.9'),
                    value: DohProvider.quad9,
                  ),
                  const RadioListTile<DohProvider>(
                    title: Text('DNS.SB'),
                    subtitle: Text('doh.dns.sb'),
                    value: DohProvider.dnsSb,
                  ),
                  const RadioListTile<DohProvider>(
                    title: Text('Canadian Shield'),
                    subtitle: Text('private.canadianshield.cira.ca'),
                    value: DohProvider.canadianShield,
                  ),
                  const RadioListTile<DohProvider>(
                    title: Text('Custom'),
                    subtitle: Text('Enter your own DoH URL'),
                    value: DohProvider.custom,
                  ),
                  if (currentProvider == DohProvider.custom)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Custom DoH URL',
                          hintText: 'https://...',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (currentProvider == DohProvider.custom)
              TextButton(
                onPressed: () {
                  final url = controller.text.trim();
                  if (url.isNotEmpty) {
                    ref
                        .read(dohSettingsProvider.notifier)
                        .setProvider(DohProvider.custom);
                    ref.read(dohSettingsProvider.notifier).setCustomUrl(url);
                    ref.read(dohSettingsProvider.notifier).clearCache();
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Save'),
              ),
          ],
        );
      },
    ),
  );
}

/// Shows a dialog to pick the app theme mode.
void showThemeDialog(
  BuildContext context,
  WidgetRef ref,
  ThemeMode currentTheme,
) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Choose Theme'),
      content: RadioGroup<ThemeMode>(
        groupValue: currentTheme,
        onChanged: (val) {
          if (val == null) return;
          ref.read(themeModeProvider.notifier).setThemeMode(val);
          Navigator.pop(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildThemeOption('System', ThemeMode.system),
              buildThemeOption('Dark', ThemeMode.dark),
              buildThemeOption('Light', ThemeMode.light),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shows a dialog to reset data.
void showResetDataDialog(BuildContext context, WidgetRef ref) {
  final callerContext = context;
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Reset Data?'),
      content: const Text(
        'This will clear Settings, Favorites, and History. Your installed Extensions will NOT be deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(dialogContext);

            // Clear Preferences ONLY
            await ref.read(settingsRepositoryProvider).clearPreferences();

            // Restart App - use caller's context; dialog context may be disposed after pop
            if (callerContext.mounted) {
              await AppUtils.restartApp(callerContext);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.tertiary,
          ),
          child: const Text('Reset Data'),
        ),
      ],
    ),
  );
}

/// Shows a dialog to factory reset.
void showFactoryResetDialog(BuildContext context, WidgetRef ref) {
  final callerContext = context;
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Factory Reset?'),
      content: const Text(
        'This will delete EVERYTHING: Favorites, History, Settings, and ALL Extensions. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            // Deep Clean (Extensions, Prefs, Hive)
            await ref.read(settingsRepositoryProvider).deleteAllData();

            // Restart App - use caller's context; dialog context may be disposed after pop
            if (callerContext.mounted) {
              await AppUtils.restartApp(callerContext);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Factory Reset'),
        ),
      ],
    ),
  );
}

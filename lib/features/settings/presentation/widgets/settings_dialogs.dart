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
import '../../../../core/providers/locale_provider.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

/// Returns a localized label for a player gesture.
String getGestureLabel(PlayerGesture gesture, AppLocalizations l10n) {
  switch (gesture) {
    case PlayerGesture.volume:
      return l10n.volume;
    case PlayerGesture.brightness:
      return l10n.brightness;
    case PlayerGesture.none:
      return l10n.none;
  }
}

/// Returns a localized label for a resize mode string.
String getResizeModeLabel(String mode, AppLocalizations l10n) {
  switch (mode.toLowerCase()) {
    case 'fit':
      return l10n.fit;
    case 'zoom':
      return l10n.zoom;
    case 'stretch':
      return l10n.stretch;
    default:
      return mode;
  }
}

/// Returns a human-readable label for a home screen route.
String getHomeScreenLabel(String route, AppLocalizations l10n) {
  switch (route) {
    case '/home':
      return l10n.home;
    case '/discover':
      return l10n.discover;
    case '/search':
      return l10n.search;
    case '/library':
      return l10n.library;
    default:
      return l10n.home;
  }
}

/// Shows a dialog to pick the default home screen.
void showDefaultHomeScreenDialog(
  BuildContext context,
  WidgetRef ref,
  String current,
) {
  final l10n = AppLocalizations.of(context)!;
  final options = [
    {'label': l10n.home, 'route': '/home'},
    {'label': l10n.discover, 'route': '/discover'},
    {'label': l10n.search, 'route': '/search'},
    {'label': l10n.library, 'route': '/library'},
  ];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.defaultHomeScreen),
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
String formatSeekDuration(int seconds, AppLocalizations l10n) {
  if (seconds >= 60) {
    return '${seconds ~/ 60} ${l10n.min}';
  }
  return '$seconds ${l10n.sec}';
}

/// Formats readahead seconds for display (e.g. "5 min", "10 min").
String formatReadahead(int seconds, AppLocalizations l10n) {
  return '${seconds ~/ 60} ${l10n.min}';
}

/// Returns a human-readable name for a player ID.
String getPlayerDisplayName(String? playerId, AppLocalizations l10n) {
  if (playerId == null) return l10n.internalPlayer;
  final player = ExternalPlayerService.instance.getPlayerById(playerId);
  return player?.displayName ?? playerId;
}

/// Returns a human-readable label for a DoH provider.
String getDohProviderLabel(DohProvider provider, String customUrl, AppLocalizations l10n) {
  switch (provider) {
    case DohProvider.cloudflare:
      return l10n.cloudflare;
    case DohProvider.google:
      return l10n.google;
    case DohProvider.adguard:
      return l10n.adguard;
    case DohProvider.dnsWatch:
      return l10n.dnsWatch;
    case DohProvider.quad9:
      return l10n.quad9;
    case DohProvider.dnsSb:
      return l10n.dnsSb;
    case DohProvider.canadianShield:
      return l10n.canadianShield;
    case DohProvider.custom:
      return customUrl.isNotEmpty
          ? Uri.tryParse(customUrl)?.host ?? customUrl
          : l10n.customNotSet;
  }
}

/// Shows a dialog to pick the left/right swipe gesture.
void showGestureDialog(
  BuildContext context,
  WidgetRef ref,
  bool isLeft,
  PlayerGesture current,
) {
  final l10n = AppLocalizations.of(context)!;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.selectGesture(isLeft ? l10n.left : l10n.right)),
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
              String label = getGestureLabel(g, l10n);
              return RadioListTile<PlayerGesture>(
                title: Text(label),
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
  final l10n = AppLocalizations.of(context)!;
  final options = [5, 10, 15, 20, 30, 60, 120];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.selectSeekDuration),
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
                title: Text(formatSeekDuration(sec, l10n)),
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
  final l10n = AppLocalizations.of(context)!;
  final options = [
    {'label': l10n.fit, 'value': 'Fit'},
    {'label': l10n.zoom, 'value': 'Zoom'},
    {'label': l10n.stretch, 'value': 'Stretch'},
  ];
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.defaultResizeMode),
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
              .map((e) => RadioListTile<String>(
                    title: Text(e['label']!),
                    value: e['value']!,
                  ))
              .toList(),
        ),
      ),
    ),
  );
}

/// Shows a dialog to pick the readahead duration (5-10 min).
void showReadaheadDialog(BuildContext context, WidgetRef ref, int current) {
  final l10n = AppLocalizations.of(context)!;
  // 1 to 20 minutes in 1-minute steps
  final options = List.generate(20, (i) => (1 + i) * 60);

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.selectBufferDepth),
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
                title: Text(formatReadahead(sec, l10n)),
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
  final l10n = AppLocalizations.of(context)!;
  double size = settings.subtitleSize;
  bool showBackground = settings.subtitleBackgroundColor != 0;
  final isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          surfaceTintColor: Colors.transparent,
          title: Text(l10n.subtitleSettings),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.size(size.toInt())),
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
                title: Text(l10n.background),
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
                l10n.cancel,
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
              child: Text(l10n.save),
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
  final l10n = AppLocalizations.of(context)!;
  final platformPlayers = ExternalPlayerService.instance
      .getPlayersForPlatform();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.defaultPlayer),
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
              RadioListTile<String?>(
                title: Text(l10n.internalPlayer),
                subtitle: Text(l10n.builtInPlayer),
                secondary: const Icon(Icons.play_circle_filled_rounded),
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
            l10n.cancel,
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
  final l10n = AppLocalizations.of(context)!;
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
          title: Text(l10n.dohProvider),
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
                  RadioListTile<DohProvider>(
                    title: Text(l10n.cloudflare),
                    subtitle: const Text('1.1.1.1'),
                    value: DohProvider.cloudflare,
                  ),
                  RadioListTile<DohProvider>(
                    title: Text(l10n.google),
                    subtitle: const Text('8.8.8.8'),
                    value: DohProvider.google,
                  ),
                  RadioListTile<DohProvider>(
                    title: Text(l10n.adguard),
                    subtitle: const Text('dns.adguard.com'),
                    value: DohProvider.adguard,
                  ),
                  RadioListTile<DohProvider>(
                    title: Text(l10n.dnsWatch),
                    subtitle: const Text('resolver2.dns.watch'),
                    value: DohProvider.dnsWatch,
                  ),
                  RadioListTile<DohProvider>(
                    title: Text(l10n.quad9),
                    subtitle: const Text('9.9.9.9'),
                    value: DohProvider.quad9,
                  ),
                  RadioListTile<DohProvider>(
                    title: Text(l10n.dnsSb),
                    subtitle: const Text('doh.dns.sb'),
                    value: DohProvider.dnsSb,
                  ),
                  RadioListTile<DohProvider>(
                    title: Text(l10n.canadianShield),
                    subtitle: const Text('private.canadianshield.cira.ca'),
                    value: DohProvider.canadianShield,
                  ),
                  RadioListTile<DohProvider>(
                    title: Text(l10n.custom),
                    subtitle: Text(l10n.enterCustomDohUrl),
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
                        decoration: InputDecoration(
                          labelText: l10n.customDohUrlLabel,
                          hintText: 'https://...',
                          border: const OutlineInputBorder(),
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
                l10n.cancel,
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
                child: Text(l10n.save),
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
  final l10n = AppLocalizations.of(context)!;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.chooseTheme),
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
              buildThemeOption(l10n.system, ThemeMode.system),
              buildThemeOption(l10n.dark, ThemeMode.dark),
              buildThemeOption(l10n.light, ThemeMode.light),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.cancel,
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
  final l10n = AppLocalizations.of(context)!;
  final callerContext = context;
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.resetDataDialogTitle),
      content: Text(l10n.resetDataDialogContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(
            l10n.cancel,
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
          child: Text(l10n.resetDataKeepExtensions),
        ),
      ],
    ),
  );
}

/// Shows a dialog to factory reset.
void showFactoryResetDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final callerContext = context;
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.factoryResetDialogTitle),
      content: Text(l10n.factoryResetDialogContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(
            l10n.cancel,
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
          child: Text(l10n.factoryReset),
        ),
      ],
    ),
  );
}

/// Shows a dialog to pick the application language.
void showLanguageDialog(
  BuildContext context,
  WidgetRef ref,
  Locale currentLocale,
) {
  final l10n = AppLocalizations.of(context)!;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.selectLanguage),
      content: FutureBuilder<List<Map<String, dynamic>>>(
        future: Future.wait(
          AppLocalizations.supportedLocales.map((locale) async {
            final localL10n = await AppLocalizations.delegate.load(locale);
            return {'label': localL10n.languageName, 'locale': locale};
          }),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final options = snapshot.data!;

          return RadioGroup<Locale>(
            groupValue: currentLocale,
            onChanged: (val) {
              if (val == null) return;
              ref.read(localeProvider.notifier).setLocale(val);
              Navigator.pop(context);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) {
                final locale = opt['locale'] as Locale;
                return RadioListTile<Locale>(
                  title: Text(opt['label'] as String),
                  value: locale,
                );
              }).toList(),
            ),
          );
        },
      ),
    ),
  );
}

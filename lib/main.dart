import 'dart:async';
import 'dart:io';
import 'package:app_restarter/app_restarter.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kReleaseMode
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/storage/storage_service.dart';
import 'core/network/doh_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'core/utils/app_utils.dart';
import 'features/extensions/providers/extensions_controller.dart';
import 'features/extensions/widgets/extensions_sync_bridge.dart';
import 'core/providers/update_provider.dart';
import 'core/widgets/update_dialog.dart';
import 'core/services/download_service.dart';
import 'core/services/notification_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'core/providers/locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Silence logs in release mode
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Native window init (Desktop) - Run once
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      center: true,
      backgroundColor: Colors
          .black, // Solid black prevents transparency during fullscreen transition
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    unawaited(
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.maximize();
        await windowManager.focus();
      }),
    );
  }

  runApp(const AppRestarter(child: AppRoot()));
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late StorageService _storageService;
  bool _initialized = false;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _storageService = StorageService();
    try {
      await Future.wait([
        _storageService.init(),
        DohService.instance.init(),
        if (Platform.isAndroid)
          FlutterDisplayMode.setHighRefreshRate().catchError((Object e) {
            if (kDebugMode) debugPrint("Error setting high refresh rate: $e");
          }),
      ]);

      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _error = e;
          _stackTrace = stack;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return LaunchErrorApp(
        error: _error!,
        stackTrace: _stackTrace,
        storageService: _storageService,
      );
    }

    if (!_initialized) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final color =
                lightDynamic?.primary ??
                const Color(0xFF6200EE); // Default Purple/Blue
            return ColoredBox(
              color: Colors.black,
              child: Center(child: CircularProgressIndicator(color: color)),
            );
          },
        ),
      );
    }

    return ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(_storageService)],
      child: const ExtensionsSyncBridge(child: MyApp()),
    );
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadServiceProvider).init();
      _checkExtensionsUpdates();
      _checkAppUpdates();
    });
  }

  Future<void> _checkAppUpdates() async {
    if (kDebugMode)
      debugPrint('[Lifecycle] Starting _checkAppUpdates after 5s delay...');
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!mounted) {
      if (kDebugMode)
        debugPrint('[Lifecycle] _checkAppUpdates aborted: MyApp unmounted');
      return;
    }

    try {
      final controller = ref.read(updateControllerProvider.notifier);
      await controller.checkForUpdates();
    } catch (e) {
      if (kDebugMode) {
        debugPrint("[Lifecycle] App update trigger failed: $e");
      }
    }
  }

  Future<void> _checkExtensionsUpdates() async {
    try {
      final controller = ref.read(extensionsControllerProvider.notifier);
      unawaited(controller.ensureInitialized());
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      if (mounted) {
        final count = await controller.checkForUpdates();
        final navContext = _scaffoldMessengerKey.currentContext;
        if (mounted && navContext != null && navContext.mounted) {
          final l10n = AppLocalizations.of(navContext);
          if (l10n != null && count > 0) {
            ref
                .read(notificationServiceProvider)
                .showSuccess(l10n.extensionsUpdated(count));
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Auto-update failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);
    final appRouter = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);

    // Reactive Listener: Keeps UpdateController alive and handles the UI side-effect
    ref.listen<UpdateState>(updateControllerProvider, (previous, next) {
      if (next is UpdateAvailable) {
        final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
        if (navContext != null && navContext.mounted) {
          if (kDebugMode)
            debugPrint(
              '[Lifecycle] State update detected: UpdateAvailable. Showing dialog.',
            );
          UpdateDialog.show(navContext, next.release);
        } else {
          if (kDebugMode)
            debugPrint(
              '[Lifecycle] Update available but navContext not ready/mounted.',
            );
        }
      }
    });

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        ColorScheme? darkScheme;
        if (darkDynamic != null) {
          darkScheme = darkDynamic;
        }

        return MaterialApp.router(
          scaffoldMessengerKey: _scaffoldMessengerKey,
          title: 'SkyStream',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: lightDynamic != null
              ? AppTheme.createLightTheme(lightDynamic)
              : AppTheme.createLightTheme(null),
          darkTheme: AppTheme.createDarkTheme(darkScheme),
          routerConfig: appRouter,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        );
      },
    );
  }
}

class LaunchErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace? stackTrace;
  final StorageService storageService;

  const LaunchErrorApp({
    super.key,
    required this.error,
    this.stackTrace,
    required this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n?.startupError ?? 'Startup Error',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      error.toString(),
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n?.retry ?? 'Retry'),
                      onPressed: () {
                        main();
                      },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                      icon: const Icon(Icons.delete_forever),
                      label: Text(l10n?.factoryReset ?? 'Factory Reset'),
                      onPressed: () async {
                        await storageService.deleteAllData();
                        if (context.mounted) await AppUtils.restartApp(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.orange),
                      ),
                      icon: const Icon(Icons.restore),
                      label: Text(
                        l10n?.resetDataKeepExtensions ??
                            'Reset Data (Keep Extensions)',
                      ),
                      onPressed: () async {
                        await storageService.clearPreferences();
                        if (context.mounted) await AppUtils.restartApp(context);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

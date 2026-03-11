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

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.maximize();
      await windowManager.focus();
    });
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
      await _storageService.init();

      // OPTIMIZATION: Enable High Refresh Rate (120Hz/90Hz) on Android
      if (Platform.isAndroid) {
        try {
          await FlutterDisplayMode.setHighRefreshRate();
        } catch (e) {
          debugPrint("Error setting high refresh rate: $e");
        }
      }

      // Preload DoH settings synchronously
      await DohService.instance.init();

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
      _checkExtensionsUpdates();
      _checkAppUpdates();
    });
  }

  Future<void> _checkAppUpdates() async {
    // Delay slightly to not block UI/Animations on launch
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      final controller = ref.read(updateControllerProvider.notifier);
      await controller.checkForUpdates();
      if (!mounted) return;

      final state = ref.read(updateControllerProvider);
      final appRouter = ref.read(appRouterProvider);
      final navContext = appRouter.routerDelegate.navigatorKey.currentContext;

      if (state is UpdateAvailable &&
          navContext != null &&
          navContext.mounted) {
        UpdateDialog.show(navContext, state.release);
      }
    } catch (e) {
      debugPrint("App update check failed: $e");
    }
  }

  Future<void> _checkExtensionsUpdates() async {
    try {
      final controller = ref.read(extensionsControllerProvider.notifier);
      controller.ensureInitialized();
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final count = await controller.checkForUpdates();
      if (!mounted) return;
      if (count > 0) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text("Updated $count extension${count > 1 ? 's' : ''}"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Auto-update failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final appRouter = ref.watch(appRouterProvider);

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
      home: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'Startup Error',
                  style: TextStyle(
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
                  label: const Text('Retry'),
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
                  label: const Text('Factory Reset'),
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
                  label: const Text('Reset Data (Keep Extensions)'),
                  onPressed: () async {
                    await storageService.clearPreferences();
                    if (context.mounted) await AppUtils.restartApp(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

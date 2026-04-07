import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/settings_repository.dart';

class GeneralSettings {
  final bool watchHistoryEnabled;
  final String defaultHomeScreen;

  const GeneralSettings({
    this.watchHistoryEnabled = true,
    this.defaultHomeScreen = '/home',
  });

  GeneralSettings copyWith({bool? watchHistoryEnabled, String? defaultHomeScreen}) {
    return GeneralSettings(
      watchHistoryEnabled: watchHistoryEnabled ?? this.watchHistoryEnabled,
      defaultHomeScreen: defaultHomeScreen ?? this.defaultHomeScreen,
    );
  }
}

class GeneralSettingsNotifier extends Notifier<GeneralSettings> {
  @override
  GeneralSettings build() {
    final repository = ref.watch(settingsRepositoryProvider);
    return GeneralSettings(
      watchHistoryEnabled: repository.isWatchHistoryEnabled(),
      defaultHomeScreen: repository.getDefaultHomeScreen(),
    );
  }

  Future<void> setWatchHistoryEnabled(bool enabled) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setWatchHistoryEnabled(enabled);
    state = state.copyWith(watchHistoryEnabled: enabled);
  }

  Future<void> setDefaultHomeScreen(String path) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setDefaultHomeScreen(path);
    state = state.copyWith(defaultHomeScreen: path);
  }
}

final generalSettingsProvider =
    NotifierProvider<GeneralSettingsNotifier, GeneralSettings>(
      GeneralSettingsNotifier.new,
    );

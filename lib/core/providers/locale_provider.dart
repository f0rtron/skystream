import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../storage/storage_service.dart';

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(() {
  return LocaleNotifier();
});

class LocaleNotifier extends Notifier<Locale> {
  late final StorageService _storage;

  @override
  Locale build() {
    _storage = ref.read(storageServiceProvider);
    return _parseLocale(_storage.getLanguage());
  }

  static Locale _parseLocale(String langTag) {
    if (langTag.contains('-')) {
      final parts = langTag.split('-');
      return Locale(parts[0], parts[1]);
    }
    return Locale(langTag);
  }

  Future<void> setLocale(Locale locale) async {
    final langTag = locale.countryCode != null 
        ? '${locale.languageCode}-${locale.countryCode}' 
        : locale.languageCode;
    await _storage.setLanguage(langTag);
    state = locale;
  }
}

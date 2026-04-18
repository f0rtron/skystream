import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../storage/storage_service.dart';

part 'locale_provider.g.dart';

@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
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

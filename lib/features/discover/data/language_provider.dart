import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/storage/settings_repository.dart';

part 'language_provider.g.dart';

@Riverpod(keepAlive: true)
class Language extends _$Language {
  @override
  String build() {
    final settings = ref.read(settingsRepositoryProvider);
    return settings.getLanguage();
  }

  Future<void> setLanguage(String language) async {
    await ref.read(settingsRepositoryProvider).setLanguage(language);
    state = language;
  }
}

class LanguageOption {
  final String code;
  final String name;
  final String nativeName;

  const LanguageOption(this.code, this.name, this.nativeName);
}

@Riverpod(keepAlive: true)
List<LanguageOption> languageList(Ref ref) {
  return const [
    LanguageOption('en-US', 'English', 'English'),
    LanguageOption('hi-IN', 'Hindi', 'हिंदी'),
    LanguageOption('kn-IN', 'Kannada', 'ಕನ್ನಡ'),
    LanguageOption('ta-IN', 'Tamil', 'தமிழ்'),
    LanguageOption('te-IN', 'Telugu', 'తెలుగు'),
    LanguageOption('ml-IN', 'Malayalam', 'മലയാളം'),
    LanguageOption('bn-IN', 'Bengali', 'বাংলা'),
    LanguageOption('mr-IN', 'Marathi', 'मराठी'),
    LanguageOption('pa-IN', 'Punjabi', 'ਪੰਜਾਬੀ'),
    LanguageOption('es-ES', 'Spanish', 'Español'),
    LanguageOption('fr-FR', 'French', 'Français'),
    LanguageOption('de-DE', 'German', 'Deutsch'),
    LanguageOption('it-IT', 'Italian', 'Italiano'),
    LanguageOption('ja-JP', 'Japanese', '日本語'),
    LanguageOption('ko-KR', 'Korean', '한국어'),
    LanguageOption('ru-RU', 'Russian', 'Русский'),
  ];
}

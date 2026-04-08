// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Macedonian (`mk`).
class AppLocalizationsMk extends AppLocalizations {
  AppLocalizationsMk([String locale = 'mk']) : super(locale);

  @override
  String get appTitle => 'SkyStream';

  @override
  String get languageName => 'Македонски';

  @override
  String get home => 'Почетна';

  @override
  String get search => 'Пребарај';

  @override
  String get discover => 'Откриј';

  @override
  String get library => 'Библиотека';

  @override
  String get settings => 'Поставки';

  @override
  String get extensions => 'Екстензии';

  @override
  String get updateAvailable => 'Достапно ажурирање';

  @override
  String get retry => 'Обиди се повторно';

  @override
  String get factoryReset => 'Фабричко ресетирање';

  @override
  String get startupError => 'Грешка при стартување';

  @override
  String get general => 'Општо';

  @override
  String get appTheme => 'Тема на апликацијата';

  @override
  String get recordWatchHistory => 'Снимај историја на гледање';

  @override
  String get defaultHomeScreen => 'Стандарден почетен екран';

  @override
  String get player => 'Плеер';

  @override
  String get defaultPlayer => 'Стандарден плеер';

  @override
  String get leftGesture => 'Лев гест';

  @override
  String get rightGesture => 'Десен гест';

  @override
  String get doubleTapToSeek => 'Двојно допирање за пребарување';

  @override
  String get swipeToSeek => 'Повлекување за пребарување';

  @override
  String get seekDuration => 'Времетраење на пребарувањето';

  @override
  String get bufferDepth => 'Длабочина на баферот';

  @override
  String get defaultResizeMode => 'Стандарден режим за големина';

  @override
  String get hardwareDecoding => 'Хардверско декодирање';

  @override
  String get network => 'Мрежа';

  @override
  String get dnsOverHttps => 'DNS преку HTTPS';

  @override
  String get dohProvider => 'DoH провајдер';

  @override
  String get manageExtensions => 'Управување со екстензии';

  @override
  String get appData => 'Податоци на апликацијата';

  @override
  String get resetDataKeepExtensions => 'Ресетирај податоци (задржи екстензии)';

  @override
  String get developer => 'Програмер';

  @override
  String get developerOptions => 'Опции за програмери';

  @override
  String get about => 'За апликацијата';

  @override
  String get version => 'Верзија';

  @override
  String get enabled => 'Овозможено';

  @override
  String get disabled => 'Оневозможено';

  @override
  String get system => 'Системска';

  @override
  String get dark => 'Темна';

  @override
  String get light => 'Светла';

  @override
  String get later => 'Подоцна';

  @override
  String get updateNow => 'Ажурирај сега';

  @override
  String get save => 'Зачувај';

  @override
  String get cancel => 'Откажи';

  @override
  String get close => 'Затвори';

  @override
  String get delete => 'Избриши';

  @override
  String get viewDetails => 'Види детали';

  @override
  String get clearAll => 'Исчисти сè';

  @override
  String get clearAllHistory => 'Исчисти историја на гледање';

  @override
  String get all => 'Сите';

  @override
  String get none => 'Ништо';

  @override
  String get confirmDownload => 'Потврди преземање';

  @override
  String get downloadNow => 'Преземи сега';

  @override
  String get selectSource => 'Избери извор';

  @override
  String get downloadUnavailable => 'Недостапно';

  @override
  String get selectAnotherSource => 'Избери друг извор';

  @override
  String get watchHistoryCleared => 'Историјата на гледање е исчистена';

  @override
  String get downloadingUpdate => 'Преземање ажурирање...';

  @override
  String errorPrefix(String message) {
    return 'Грешка: $message';
  }

  @override
  String updateAvailableTag(String tag) {
    return 'Достапно ажурирање: $tag';
  }

  @override
  String get selectProviderToStart => 'Изберете провајдер за почеток';

  @override
  String get tapExtensionIcon => 'Допрете ја иконата за екстензија во аголот';

  @override
  String get continueWatching => 'Продолжи со гледање';

  @override
  String get noInternetConnection => 'Нема интернет врска';

  @override
  String get siteNotReachable => 'Сајтот е недостапен';

  @override
  String get checkConnectionOrDownloads =>
      'Проверете ја врската или погледнете ги преземањата.';

  @override
  String get tryVpnOrConnection =>
      'Обидете се со VPN или проверете ја врската.';

  @override
  String errorDetails(String error) {
    return 'Детали за грешката: $error';
  }

  @override
  String get goToDownloads => 'Оди до преземања';

  @override
  String get selectProvider => 'Избери провајдер';

  @override
  String get searchHint => 'Пребарај филмови, серии...';

  @override
  String get searchFavoriteContent => 'Пребарајте ја вашата омилена содржина';

  @override
  String get pressSearchOrEnter => 'Притиснете Пребарај или Enter за почеток';

  @override
  String get noResultsFound => 'Нема пронајдени резултати.';

  @override
  String get couldNotLoadTrending => 'Не можеа да се вчитаат трендовите';

  @override
  String get popularMovies => 'Популарни филмови';

  @override
  String get popularTVShows => 'Популарни серии';

  @override
  String get newMovies => 'Нови филмови';

  @override
  String get newTVShows => 'Нови серии';

  @override
  String get featuredMovies => 'Препорачани филмови';

  @override
  String get featuredTVShows => 'Препорачани серии';

  @override
  String get lastVideosTVShows => 'Последни епизоди';

  @override
  String get downloads => 'Преземања';

  @override
  String get bookmarks => 'Обележувачи';

  @override
  String get noDownloadsYet => 'Сè уште нема преземања';

  @override
  String episodesCount(int count, int done) {
    return '$count епизоди • $done завршени';
  }

  @override
  String get deleteAllEpisodes => 'Избриши ги сите епизоди';

  @override
  String confirmDeleteAllEpisodes(int count, String title) {
    return 'Дали сте сигурни дека сакате да ги избришете сите $count епизоди на \"$title\" и нивните датотеки?';
  }

  @override
  String get deleteAll => 'Избриши сè';

  @override
  String get completed => 'Завршено';

  @override
  String get statusQueued => 'Во редица...';

  @override
  String get statusDownloading => 'Преземање...';

  @override
  String get statusFinished => 'Завршено';

  @override
  String get statusFailed => 'Неуспешно';

  @override
  String get statusCanceled => 'Откажано';

  @override
  String get statusPaused => 'Паузирано';

  @override
  String get statusWaiting => 'Чекање...';

  @override
  String get fileNotFoundRemoving =>
      'Датотеката не е пронајдена. Се отстранува записот.';

  @override
  String get fileNotFound => 'Датотеката не е пронајдена';

  @override
  String get deleteDownload => 'Избриши преземање';

  @override
  String get confirmDeleteDownload =>
      'Дали сте сигурни дека сакате да го избришете ова преземање?';

  @override
  String get libraryEmpty => 'Библиотеката е празна';

  @override
  String get language => 'Јазик';

  @override
  String get english => 'Англиски';

  @override
  String get hindi => 'Хинди';

  @override
  String get kannada => 'Канада';

  @override
  String get unknown => 'Непознато';

  @override
  String get recommended => 'Препорачано';

  @override
  String get on => 'Вклучено';

  @override
  String get off => 'Исклучено';

  @override
  String get installRemoveProviders => 'Инсталирај или отстрани провајдери';

  @override
  String get resetDataSubtitle => 'Исчисти поставки и база, задржи приклучоци';

  @override
  String get factoryResetSubtitle =>
      'Избриши ги сите податоци, поставки и екстензии';

  @override
  String get developerOptionsSubtitle =>
      'Алатки за дебагирање и локално пуштање';

  @override
  String get loading => 'Вчитување...';

  @override
  String get sec => 'сек';

  @override
  String get min => 'мин';

  @override
  String get internalPlayer => 'Внатрешен (media_kit)';

  @override
  String get builtInPlayer => 'Вграден плеер';

  @override
  String get customNotSet => 'Приспособено (не е поставено)';

  @override
  String selectGesture(String side) {
    return 'Избери $side гест';
  }

  @override
  String get left => 'лев';

  @override
  String get right => 'десен';

  @override
  String get selectSeekDuration => 'Избери времетраење на пребарувањето';

  @override
  String get selectBufferDepth => 'Избери длабочина на баферот';

  @override
  String get subtitleSettings => 'Поставки за титлови';

  @override
  String size(int size) {
    return 'Големина: $size';
  }

  @override
  String get background => 'Позадина';

  @override
  String get customDohUrlLabel => 'Приспособен DoH URL';

  @override
  String get enterCustomDohUrl => 'Внесете ваш DoH URL';

  @override
  String get chooseTheme => 'Избери тема';

  @override
  String get resetDataDialogTitle => 'Ресетирање податоци?';

  @override
  String get resetDataDialogContent =>
      'Ова ќе ги исчисти Поставките, Омилените и Историјата. Инсталираните екстензии НЕМА да бидат избришани.';

  @override
  String get factoryResetDialogTitle => 'Фабричко ресетирање?';

  @override
  String get factoryResetDialogContent =>
      'Ова ќе избрише СÈ. Оваа акција е неповратна.';

  @override
  String get selectLanguage => 'Избери јазик';

  @override
  String get synopsis => 'Синопсис';

  @override
  String get noDescription => 'Нема достапен опис.';

  @override
  String get videoAlreadyDownloadedPrompt =>
      'Ова видео е веќе преземено. Што сакате да направите?';

  @override
  String get playNow => 'Гледај сега';

  @override
  String get deleteDownloadPrompt => 'Избриши преземање?';

  @override
  String get deleteDownloadConfirmation =>
      'Дали сте сигурни дека сакате да ја избришете оваа датотека? Ова не може да се врати.';

  @override
  String get no => 'Не';

  @override
  String get yesDelete => 'Да, избриши';

  @override
  String get downloadPaused => 'Преземањето е паузирано';

  @override
  String get downloading => 'Преземање';

  @override
  String get speed => 'Брзина';

  @override
  String get remaining => 'Преостанато';

  @override
  String get resume => 'Продолжи';

  @override
  String get pause => 'Пауза';

  @override
  String get torrentContent => 'Содржина на торент';

  @override
  String get audioTracks => 'Аудио записи';

  @override
  String get noAudioTracks => 'Не се пронајдени аудио записи';

  @override
  String get subtitles => 'Титлови';

  @override
  String get options => 'Опции';

  @override
  String get noSubtitlesFound => 'Не се пронајдени титлови';

  @override
  String get playbackSpeed => 'Брзина на репродукција';

  @override
  String get subtitleOptions => 'Опции за титлови';

  @override
  String get hlsSubtitleWarning =>
      'Надворешни титлови не се поддржани за HLS на оваа платформа.';

  @override
  String get loadFromDevice => 'Вчитај од уред';

  @override
  String get syncDelay => 'Синхронизација / Доцнење';

  @override
  String get styleSettings => 'Поставки за стил';

  @override
  String get searchOnline => 'Пребарај онлајн (пребарување титлови)';

  @override
  String get subtitleSync => 'Синхронизација на титлови';

  @override
  String get subtitleDelayWarning =>
      'Доцнењето на титловите не е поддржано од тековниот плеер.';

  @override
  String get resetDelay => 'Ресетирај доцнење';

  @override
  String get subtitleStyles => 'Стилови на титлови';

  @override
  String get mediaKitStylingWarning =>
      'Стилизирањето на титловите е моментално достапно само за media_kit.';

  @override
  String get resetToDefault => 'Врати на стандардно';

  @override
  String get fontSize => 'Големина на фонт';

  @override
  String get verticalPosition => 'Вертикална позиција';

  @override
  String get textColor => 'Боја на текст';

  @override
  String get backgroundColor => 'Боја на позадина';

  @override
  String get backgroundOpacity => 'Проѕирност на позадина';

  @override
  String get subtitleSearch => 'Пребарување титлови';

  @override
  String get searchSubtitleNameHint => 'Име на титл...';

  @override
  String get enterSearchSubtitlePrompt => 'Внесете име за пребарување титлови.';

  @override
  String get noSubtitleResults =>
      'Нема резултати. Обидете се со друго пребарување.';

  @override
  String get downloadingApplyingSubtitle => 'Преземање и применување титл...';

  @override
  String get failedToDownloadSubtitle => 'Неуспешно преземање титл.';

  @override
  String get failedToLoadSubtitles =>
      'Неуспешно вчитување титлови. Обидете се повторно.';

  @override
  String get noReposFound => 'Не се пронајдени репозиториуми или приклучоци';

  @override
  String get downloadAllProviders => 'Преземи ги сите достапни провајдери';

  @override
  String get removeRepository => 'Отстрани репозиториум';

  @override
  String get addRepo => 'Додај репозиториум';

  @override
  String get extensionsNotInRepos => 'Екстензии надвор од репозиториуми';

  @override
  String get noLongerInRepo => 'Веќе не е на списокот во ниеден репозиториум';

  @override
  String get addRepoToBrowse => 'Додајте репозиториум за преглед на приклучоци';

  @override
  String get debugExtensions => 'Дебагирање екстензии';

  @override
  String removeRepoConfirm(String repoName) {
    return 'Отстранување на $repoName?';
  }

  @override
  String get removeRepoWarning =>
      'Ова ќе го отстрани репозиториумот и ќе ги деинсталира сите негови приклучоци.';

  @override
  String get addRepository => 'Додај репозиториум';

  @override
  String get repoUrlOrShortcode => 'URL на репозиториум или краток код';

  @override
  String get assetPlugin => 'Вграден приклучок';

  @override
  String get installed => 'Инсталирано';

  @override
  String updateTo(String version) {
    return 'Ажурирај на $version';
  }

  @override
  String get install => 'Инсталирај';

  @override
  String get error => 'Грешка';

  @override
  String get ok => 'ОК';

  @override
  String pluginSettings(String pluginName) {
    return 'Поставки за $pluginName';
  }

  @override
  String get movies => 'Филмови';

  @override
  String get series => 'Серии';

  @override
  String get anime => 'Аниме';

  @override
  String get liveStreams => 'Стримови во живо';

  @override
  String get debug => 'ДЕБАГИРАЊЕ';

  @override
  String extensionsUpdated(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count екстензии се ажурирани',
      one: '1 екстензија е ажурирана',
    );
    return '$_temp0';
  }

  @override
  String get invalidNavigation => 'Невалидна навигација. Ве молиме вратете се.';

  @override
  String get startOver => 'Почни од почеток';

  @override
  String get goBack => 'Назад';

  @override
  String get resolving => 'Разрешување...';

  @override
  String get downloaded => 'Преземено';

  @override
  String get download => 'Преземи';

  @override
  String get debugOnlyFeature =>
      'Оваа функција е достапна само во дебаг верзии';

  @override
  String get streamUrl => 'URL на стрим';

  @override
  String get play => 'Пушти';

  @override
  String get verifyingSourceSize => 'Проверка на извор и големина...';

  @override
  String get fileSaveLocationNotification =>
      'Датотеката ќе биде зачувана во папката за преземања.';

  @override
  String get resumingPlayback => 'Продолжување со репродукција';

  @override
  String pausedAt(String time) {
    return 'Паузирано на $time';
  }

  @override
  String resumesAutomatically(int count) {
    return 'Автоматски ќе продолжи за $count сек';
  }

  @override
  String get resumeNow => 'Продолжи сега';

  @override
  String get playbackError => 'Грешка при репродукција';

  @override
  String get confirmClearHistory =>
      'Дали сте сигурни дека сакате да ја исчистите целата историја?';

  @override
  String seasonWithNumber(Object number) {
    return 'Сезона $number';
  }

  @override
  String get starting => 'Стартување...';

  @override
  String percentWatched(int percent) {
    return '$percent% изгледано';
  }

  @override
  String get sub => 'Титл';

  @override
  String get dub => 'Дуб';

  @override
  String playEpisode(String label, Object season, Object episode) {
    return '$label С$season Е$episode';
  }

  @override
  String get debugTools => 'Алатки за дебагирање';

  @override
  String get playLocalVideo => 'Локално видео';

  @override
  String get playLocalVideoSubtitle => 'Пушти датотека од уред';

  @override
  String get streamUrlSubtitle => 'Пушти од мрежен URL';

  @override
  String get streamTorrent => 'Стримувај торент';

  @override
  String get streamTorrentSubtitle =>
      'Избери локална торент датотека за пуштање';

  @override
  String get loadPluginFromAssets => 'Вчитај приклучок од асети';

  @override
  String get enterVideoUrlHint => 'Внесете URL на видео (http, magnet итн.)';

  @override
  String get networkStream => 'Мрежен стрим';

  @override
  String removedFromHistory(String title) {
    return 'Отстрането од историја: $title';
  }

  @override
  String get custom => 'Приспособено';

  @override
  String get refreshingLiveStream => 'Освежување на стрим...';

  @override
  String get removeFromHistory => 'Отстрани од историја';

  @override
  String get live => 'ВО ЖИВО';

  @override
  String get volume => 'Јачина на звук';

  @override
  String get brightness => 'Осветленост';

  @override
  String get fit => 'Приспособи';

  @override
  String get zoom => 'Зум';

  @override
  String get stretch => 'Растегни';

  @override
  String titleWithParam(String title) {
    return 'Наслов: $title';
  }

  @override
  String sourceWithParam(String source) {
    return 'Извор: $source';
  }

  @override
  String sizeWithParam(String size) {
    return 'Големина: $size';
  }

  @override
  String usingInternalPlayerError(String error) {
    return 'Грешка: $error. Се користи внатрешен плеер.';
  }

  @override
  String playerNotDetected(String playerName) {
    return '$playerName не е пронајден. Се стартува внатрешниот плеер.';
  }

  @override
  String seasonWithEpisodes(Object number, int count) {
    return 'Сезона $number ($count епиз.)';
  }

  @override
  String get cloudflare => 'Cloudflare';

  @override
  String get google => 'Google';

  @override
  String get adguard => 'AdGuard';

  @override
  String get dnsWatch => 'DNS.Watch';

  @override
  String get quad9 => 'Quad9';

  @override
  String get dnsSb => 'DNS.SB';

  @override
  String get canadianShield => 'Canadian Shield';

  @override
  String get tmdb => 'TMDB';

  @override
  String selectSourceForPlayer(String playerName) {
    return 'Извор за $playerName';
  }

  @override
  String get noPluginsInstalled => 'Нема инсталирано приклучоци';

  @override
  String get availableSources => 'Достапни извори';

  @override
  String get seasons => 'Сезони';

  @override
  String get episodes => 'Епизоди';

  @override
  String get selectSourceToPlay =>
      'Ве молиме изберете извор од листата погоре.';

  @override
  String episodeCountOnly(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count епизоди',
      one: '1 епизода',
    );
    return '$_temp0';
  }

  @override
  String get noEpisodesFound => 'Не се пронајдени епизоди';

  @override
  String get local => 'Локално';

  @override
  String get remote => 'Далечинско';

  @override
  String get torrent => 'Торент';

  @override
  String get unlock => 'Отклучи';

  @override
  String get lock => 'Заклучи';

  @override
  String get sources => 'Извори';

  @override
  String get tracks => 'Записи';

  @override
  String get content => 'Содржина';

  @override
  String get stats => 'Статистика';

  @override
  String get resize => 'Големина';

  @override
  String get next => 'Следно';

  @override
  String get pip => 'PiP';

  @override
  String get rotate => 'Ротирај';

  @override
  String get windowed => 'Прозорец';

  @override
  String get fullscreen => 'Цел екран';

  @override
  String get movieDetails => 'Детали за филмот';

  @override
  String get showDetails => 'Види детали';

  @override
  String get tagline => 'Таглајн';

  @override
  String get status => 'Статус';

  @override
  String get releaseDate => 'Датум на издавање';

  @override
  String get firstAirDate => 'Прво емитување';

  @override
  String get originalLanguage => 'Оригинален јазик';

  @override
  String get originCountry => 'Земја на потекло';

  @override
  String get budgetLabel => 'Буџет';

  @override
  String get revenueLabel => 'Приход';

  @override
  String get paused => 'Паузирано';

  @override
  String get watched => 'Изгледано';

  @override
  String get watching => 'Гледање';

  @override
  String get lastWatched => 'Последно гледано';

  @override
  String get movie => 'Филм';

  @override
  String get tvShow => 'Серија';

  @override
  String get failedToLoadContent => 'Неуспешно вчитување';

  @override
  String get director => 'Режисер';

  @override
  String get creator => 'Креатор';

  @override
  String get showMore => 'Повеќε';

  @override
  String get showLess => 'Помалку';

  @override
  String get viewAll => 'Види ги сите';

  @override
  String seasonsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сезони',
      one: '1 сезона',
    );
    return '$_temp0';
  }

  @override
  String get noInternetError => 'Нема интернет';

  @override
  String get timeoutError => 'Времето истече. Обидете се повторно.';

  @override
  String get serverError => 'Грешка на серверот. Обидете се подоцна.';

  @override
  String get contentNotFoundError => 'Не е пронајдено.';

  @override
  String get accessDeniedError => 'Пристапот е одбиен.';

  @override
  String get serviceUnavailableError => 'Услугата е недостапна.';

  @override
  String get generalError => 'Се појави проблем.';

  @override
  String get skip => 'Прескокни';

  @override
  String get goLive => 'Оди во живо';

  @override
  String get dismiss => 'Отфрли';

  @override
  String get nextUp => 'Следно';

  @override
  String sourceAttempt(int index, int total) {
    return 'Извор $index од $total';
  }

  @override
  String get trying => 'Се обидува';

  @override
  String get failed => 'Неуспешно';

  @override
  String get selected => 'Избрано';

  @override
  String get playing => 'Репродуцира';

  @override
  String get pending => 'Во исчекување';
}

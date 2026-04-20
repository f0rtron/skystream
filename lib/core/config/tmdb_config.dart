class TmdbConfig {
  /// TMDB API key loaded from environment.
  /// Pass via: flutter run --dart-define=TMDB_API_KEY=your_key_here
  static const String apiKey = String.fromEnvironment('TMDB_API_KEY');
  static const String baseUrl = 'https://api.themoviedb.org/3';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/w500';
  static const String posterSizeUrl = 'https://image.tmdb.org/t/p/w500';
  static const String backdropSizeUrl = 'https://image.tmdb.org/t/p/w1280';
  static const String profileSizeUrl = 'https://image.tmdb.org/t/p/w185';
}

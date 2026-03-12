class ExtensionPlugin {
  final String id; // Unique Plugin ID (e.g. "com.hexated.superstream")
  final String name; // Display Name (e.g. "SuperStream")
  final String internalName; // Internal Class Name (e.g. "SuperStream")
  final String repositoryId; // "com.hexated" or "LocalAssets"
  final String sourceUrl; // Download Link or Local Path
  final int version;
  final String? iconUrl;

  // Metadata (Native Parity)
  final List<String> authors; // e.g. ["Hexated"]
  final String? description; // e.g. "Watch movies and TV shows"
  final List<String> categories; // e.g. ["Movie", "Anime"]
  final List<String> languages; // e.g. ["en"]
  final int? fileSize; // In bytes
  final int status; // 0: Down, 1: Ok, 2: Slow, 3: Beta
  final Map<String, dynamic> manifest; // Raw JSON manifest

  ExtensionPlugin({
    required this.id,
    required this.name,
    required this.internalName,
    required this.repositoryId,
    required this.sourceUrl,
    required this.version,
    this.status = 1,
    this.iconUrl,
    this.authors = const [],
    this.description,
    this.categories = const [],
    this.languages = const [],
    this.fileSize,
    this.manifest = const {},
  });

  /// The Globally Unique ID
  String get packageId => id;

  /// Helper to check if this is a debug/asset plugin
  bool get isDebug => id.endsWith('.debug');

  /// Local File Path relative to plugin root
  /// e.g. "plugin/[id]/plugin.js"
  /// Updated to use ID as directory name for uniqueness
  String get filePath => "$repositoryId/$id/plugin.js";

  static List<String> _readList(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      if (value is String && value.trim().isNotEmpty) {
        return [value];
      }
    }
    return const [];
  }

  /// Factory constructor to parse from JSON (SitePlugin format or meta.json)
  factory ExtensionPlugin.fromJson(
    Map<String, dynamic> json,
    String repositoryId,
  ) {
    final internal = json['internalName'] as String? ?? json['name']?.toString().toUpperCase().replaceAll(RegExp(r'\s+'), '') ?? 'UNKNOWN';
    final fallbackId = "$repositoryId.${internal.toLowerCase()}";

    return ExtensionPlugin(
      id: (json['id'] as String?) ?? (json['package-name'] as String?) ?? fallbackId,
      name: json['name'] as String? ?? 'Unknown Plugin',
      internalName: internal,
      repositoryId: repositoryId,
      sourceUrl: json['url'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      status: json['status'] as int? ?? 1,
      iconUrl: json['iconUrl'] as String?,
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      description: json['description'] as String?,
      categories: _readList(json, ['categories', 'types', 'tvTypes']),
      languages: _readList(json, ['languages', 'language', 'lang']),
      fileSize: json['fileSize'] as int?,
      manifest: json,
    );
  }
}

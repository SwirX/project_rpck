import 'source_option.dart';

/// One entry in a site's repack index.
class GameIndexEntry {
  final String title;
  final Uri pageUri;

  const GameIndexEntry({required this.title, required this.pageUri});

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': pageUri.toString(),
      };

  factory GameIndexEntry.fromJson(Map<String, dynamic> json) {
    final url = json['url'] as String?;
    final parsed = url == null ? null : Uri.tryParse(url);
    if (parsed == null) {
      throw FormatException('index entry has no usable url', json.toString());
    }
    return GameIndexEntry(
      title: json['title'] as String? ?? parsed.host,
      pageUri: parsed,
    );
  }

  /// Key used to deduplicate across syncs. Derived from the page url because
  /// titles are edited upstream and would otherwise look like a new entry.
  String get cacheKey => pageUri.toString();

  @override
  bool operator ==(Object other) =>
      other is GameIndexEntry && other.pageUri == pageUri;

  @override
  int get hashCode => pageUri.hashCode;
}

/// A repack page, normalised across every source.
///
/// The prototype declared `List torrent` and `List magnets` as raw
/// `List<dynamic>` and re-fetched data it then dropped: `repackFeatures` and
/// `backwardCompatibility` were written into the cache JSON but no field here
/// read them back.
class Repack {
  final String title;
  final Uri sourceUri;
  final String sourceId;
  final String description;
  final List<String> screenshots;
  final Map<String, String> info;
  final List<String> repackFeatures;
  final String? backwardCompatibility;
  final List<SourceOption> sources;
  final String? contentId;

  const Repack({
    required this.title,
    required this.sourceUri,
    required this.sourceId,
    required this.description,
    required this.screenshots,
    required this.info,
    required this.repackFeatures,
    required this.sources,
    this.backwardCompatibility,
    this.contentId,
  });

  /// Artwork used as the grid cover. Empty when the page exposed none, which
  /// callers must tolerate rather than index blindly.
  String get coverUrl => screenshots.isEmpty ? '' : screenshots.first;

  bool get hasMagnet =>
      sources.any((option) => option is MagnetOption);

  bool get hasTorrentFile =>
      sources.any((option) => option is TorrentFileOption);

  bool get hasDirect =>
      sources.any((option) => option is DirectOption);

  /// Torrent files first: they carry embedded trackers and find more peers than
  /// a DHT-only magnet.
  List<SourceOption> get preferredOrder {
    return <SourceOption>[
      ...sources.whereType<TorrentFileOption>(),
      ...sources.whereType<MagnetOption>(),
      ...sources.whereType<DirectOption>(),
    ];
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': sourceUri.toString(),
        'source_id': sourceId,
        'description': description,
        'screenshots': screenshots,
        'info': info,
        'repack_features': repackFeatures,
        'backward_compatibility': backwardCompatibility,
        'content_id': contentId,
        'sources': sources.map(_encodeOption).toList(),
      };

  factory Repack.fromJson(Map<String, dynamic> json) {
    return Repack(
      title: json['title'] as String? ?? 'Unknown',
      sourceUri: Uri.parse(json['url'] as String),
      sourceId: json['source_id'] as String? ?? 'unknown',
      description: json['description'] as String? ?? '',
      screenshots: (json['screenshots'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      info: (json['info'] as Map? ?? const {})
          .map((key, value) => MapEntry(key.toString(), value.toString())),
      repackFeatures: (json['repack_features'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      backwardCompatibility: json['backward_compatibility'] as String?,
      contentId: json['content_id'] as String?,
      sources: (json['sources'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_decodeOption)
          .whereType<SourceOption>()
          .toList(growable: false),
    );
  }

  static Map<String, dynamic> _encodeOption(SourceOption option) =>
      switch (option) {
        MagnetOption(:final magnet) => {'kind': 'magnet', 'value': magnet},
        TorrentFileOption(:final torrentUri) =>
          {'kind': 'torrent', 'value': torrentUri.toString()},
        DirectOption(:final url) => {'kind': 'direct', 'value': url.toString()},
      };

  static SourceOption? _decodeOption(Map<String, dynamic> json) {
    final value = json['value'] as String?;
    if (value == null) return null;
    switch (json['kind'] as String?) {
      case 'magnet':
        return MagnetOption(value);
      case 'torrent':
        final uri = Uri.tryParse(value);
        return uri == null ? null : TorrentFileOption(uri);
      case 'direct':
        final uri = Uri.tryParse(value);
        return uri == null ? null : DirectOption(uri);
      default:
        return null;
    }
  }
}
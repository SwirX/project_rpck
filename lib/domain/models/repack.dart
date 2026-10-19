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
          .whereType<Map>()
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
        TorrentIndexOption(:final listingUri, :final indexName) => {
            'kind': 'torrent_index',
            'value': listingUri.toString(),
            'index': indexName,
          },
        DirectOption(:final host, :final parts) => {
            'kind': 'direct',
            'host': host,
            'parts': [
              for (final part in parts)
                {'url': part.url.toString(), 'ordinal': part.ordinal},
            ],
          },
      };

  /// Rebuilds a mirror bundle, keeping part order.
  ///
  /// A bundle whose parts cannot be parsed is dropped rather than half
  /// restored, because a mirror missing a part yields a corrupt payload.
  static DirectOption? _decodeDirectBundle(Map<dynamic, dynamic> json) {
    final host = json['host'] as String?;
    final rawParts = json['parts'] as List?;
    if (host == null || rawParts == null) return null;

    // A decoded JSON object is a Map<String, dynamic>, but one produced by
    // toJson is a Map<String, Object>; both have to be accepted or a bundle
    // silently disappears on the first round trip.
    final parts = <DirectPart>[];
    for (final raw in rawParts.whereType<Map>()) {
      final url = Uri.tryParse(raw['url'] as String? ?? '');
      final ordinal = (raw['ordinal'] as num?)?.toInt();
      if (url == null || ordinal == null) return null;
      parts.add(DirectPart(url, ordinal));
    }
    if (parts.isEmpty) return null;

    parts.sort((left, right) => left.ordinal.compareTo(right.ordinal));
    return DirectOption(host: host, parts: parts);
  }

  static SourceOption? _decodeOption(Map<dynamic, dynamic> json) {
    // A mirror bundle carries host and parts rather than a single value, so
    // the value check belongs inside the cases that use it.
    switch (json['kind'] as String?) {
      case 'magnet':
        final magnet = json['value'] as String?;
        return magnet == null ? null : MagnetOption(magnet);
      case 'torrent':
        final uri = Uri.tryParse(json['value'] as String? ?? '');
        return uri == null ? null : TorrentFileOption(uri);
      case 'torrent_index':
        final listing = Uri.tryParse(json['value'] as String? ?? '');
        return listing == null
            ? null
            : TorrentIndexOption(
                listingUri: listing,
                indexName: json['index'] as String? ?? 'Tracker',
              );
      case 'direct':
        return _decodeDirectBundle(json);
      default:
        return null;
    }
  }
}
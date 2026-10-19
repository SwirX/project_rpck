/// The ways a repack can be fetched.
///
/// Sealed so a `switch` over the variants is exhaustive: adding a new way to
/// acquire a payload becomes a compile error at every site that handles the
/// others, instead of a silently ignored branch.
sealed class SourceOption {
  const SourceOption();

  /// Human readable name shown in the picker.
  String get label;

  /// Tracker or mirror the bytes are served from, when one is known.
  Uri? get uri;

  /// Ordering weight, lowest first, used to rank the picker.
  int get rank;

  /// Mirrors that serve a `.torrent` to hand to the torrent engine.
  ///
  /// They carry embedded trackers and find more peers than a DHT-only magnet,
  /// so they are always offered first.
  static const torrentRank = 0;

  /// A `magnet:` link, resolved over the DHT at download time.
  static const magnetRank = 1;

  /// A plain HTTP mirror, used when nothing better is offered.
  static const directRank = 2;
}

/// A `magnet:` link.
final class MagnetOption extends SourceOption {
  final String magnet;

  const MagnetOption(this.magnet);

  @override
  String get label => 'Magnet';

  @override
  Uri? get uri => Uri.tryParse(magnet);

  @override
  int get rank => SourceOption.magnetRank;
}

/// A torrent index listing page that has to be expanded before use.
///
/// FitGirl links a tracker's listing page rather than the `.torrent` file, so
/// the engine resolves this into a real torrent file or magnet first. Kept
/// distinct from [TorrentFileOption] because handing a listing page straight to
/// the torrent engine would try to parse HTML as bencode.
final class TorrentIndexOption extends SourceOption {
  final Uri listingUri;

  /// Which index this is, shown as the label.
  final String indexName;

  const TorrentIndexOption({required this.listingUri, this.indexName = 'Tracker'});

  @override
  String get label => '$indexName index';

  @override
  Uri? get uri => listingUri;

  @override
  int get rank => SourceOption.torrentRank;
}

/// A `.torrent` file to fetch, then hand to the torrent engine.
final class TorrentFileOption extends SourceOption {
  final Uri torrentUri;

  const TorrentFileOption(this.torrentUri);

  @override
  String get label => 'Torrent file';

  @override
  Uri? get uri => torrentUri;

  @override
  int get rank => SourceOption.torrentRank;
}

/// One part of a split plain-HTTP mirror.
///
/// Part files exist so a host does not have to serve a multi-gigabyte single
/// object. The parts of one host are always downloaded together, in the order
/// the listing gave them, because they reassemble into one payload only in that
/// order.
final class DirectPart {
  final Uri url;

  /// Ordinal within its bundle, starting at 1.
  final int ordinal;

  const DirectPart(this.url, this.ordinal);

  /// Bytes, when the listing advertised a size.
  final int? sizeBytes = null;
}

/// A set of plain HTTP mirrors served by one host.
///
/// A single-part host is one part. A multi-part host is the "part1, part2" set,
/// presented as one button and transferred one after another.
final class DirectOption extends SourceOption {
  final String host;
  final List<DirectPart> parts;

  const DirectOption({required this.host, required this.parts});

  /// True when this host splits the payload across several files.
  bool get isMultiPart => parts.length > 1;

  @override
  String get label => parts.length > 1 ? '$host (${parts.length} parts)' : host;

  @override
  Uri? get uri => parts.firstOrNull?.url;

  @override
  int get rank => SourceOption.directRank;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
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
}

/// A `magnet:` link, resolved over the DHT at download time.
final class MagnetOption extends SourceOption {
  final String magnet;

  const MagnetOption(this.magnet);

  @override
  String get label => 'Magnet';

  @override
  Uri? get uri => Uri.tryParse(magnet);
}

/// A `.torrent` file to fetch, then hand to the torrent engine.
final class TorrentFileOption extends SourceOption {
  final Uri torrentUri;

  const TorrentFileOption(this.torrentUri);

  @override
  String get label => 'Torrent file';

  @override
  Uri? get uri => torrentUri;
}

/// A plain HTTP mirror that serves the payload without a torrent client.
final class DirectOption extends SourceOption {
  final Uri url;

  const DirectOption(this.url);

  @override
  String get label => url.host;

  @override
  Uri? get uri => url;
}
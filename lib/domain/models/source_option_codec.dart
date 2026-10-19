import 'package:project_rpck/domain/models/source_option.dart';

/// Converts [SourceOption] to and from JSON.
///
/// The journal is what makes "resume transfers on launch" mean anything: a
/// transfer has to survive a restart as the option it was dispatched with, not
/// just as a title, or there is nothing to hand back to an engine.
///
/// Lives beside the model rather than inside it because the sealed hierarchy is
/// already at its size limit.
abstract final class SourceOptionCodec {
  /// Serialises every variant.
  ///
  /// A `switch` over a sealed class, so a new variant fails to compile here
  /// instead of vanishing from the journal.
  static Map<String, dynamic> encode(SourceOption option) =>
      switch (option) {
        MagnetOption(:final magnet) =>
          {'kind': 'magnet', 'magnet': magnet},
        TorrentFileOption(:final torrentUri) => {
            'kind': 'torrentFile',
            'uri': torrentUri.toString(),
          },
        TorrentIndexOption(:final listingUri, :final indexName) => {
            'kind': 'torrentIndex',
            'uri': listingUri.toString(),
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

  /// Reads a previously encoded option, or null when the record is unusable.
  ///
  /// Returns null rather than throwing: a journal written by an older build may
  /// name a variant that no longer exists, and one unreadable entry must not
  /// cost the user every other transfer.
  static SourceOption? decode(Object? raw) {
    if (raw is! Map) return null;
    final uri = Uri.tryParse('${raw['uri'] ?? raw['magnet'] ?? ''}');
    return switch (raw['kind']) {
      'magnet' =>
        raw['magnet'] is String ? MagnetOption(raw['magnet'] as String) : null,
      'torrentFile' => uri == null || uri.host.isEmpty
          ? null
          : TorrentFileOption(uri),
      'torrentIndex' =>
        uri == null || uri.host.isEmpty
            ? null
            : TorrentIndexOption(
                listingUri: uri,
                indexName: raw['index'] as String? ?? 'Tracker',
              ),
      'direct' => _direct(raw['host'], raw['parts']),
      _ => null,
    };
  }

  static DirectOption? _direct(Object? host, Object? parts) {
    if (parts is! List || parts.isEmpty) return null;
    final decoded = <DirectPart>[];
    for (final entry in parts) {
      if (entry is! Map) continue;
      final url = Uri.tryParse('${entry['url'] ?? ''}');
      if (url == null || url.host.isEmpty) continue;
      decoded.add(DirectPart(url, (entry['ordinal'] as num?)?.toInt() ?? 1));
    }
    // A bundle whose every part failed to decode is dropped rather than
    // restored as an empty bundle that would report success instantly.
    if (decoded.isEmpty) return null;
    return DirectOption(host: host is String ? host : decoded.first.url.host,
        parts: decoded);
  }
}
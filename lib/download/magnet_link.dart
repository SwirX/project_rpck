import '../core/result.dart';

/// A parsed `magnet:` link.
///
/// `dtorrent_parser` cannot parse magnets — `Torrent.parse` accepts only a file
/// path or a byte buffer — so the link is decomposed here and the info hash is
/// normalised to the lowercase hex form `MetadataDownloader` requires.
class MagnetLink {
  /// 40 lowercase hex characters.
  final String infoHashHex;
  final String? displayName;
  final List<Uri> trackers;

  const MagnetLink({
    required this.infoHashHex,
    required this.trackers,
    this.displayName,
  });

  static Result<MagnetLink> parse(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.toLowerCase().startsWith('magnet:')) {
      return const FailureResult(
        Failure(FailureKind.parse, 'not a magnet uri'),
      );
    }

    final parameters = _parseQuery(trimmed.substring('magnet:'.length));
    final exactTopic = parameters['xt'] ?? const <String>[];
    final btihTopic = exactTopic.firstWhere(_isBtih, orElse: () => '');
    final btih = _topicValue(btihTopic);

    if (btih.isEmpty) {
      return const FailureResult(
        Failure(FailureKind.parse, 'magnet has no urn:btih exact topic'),
      );
    }

    final hex = _normalizeInfoHash(btih);
    if (hex == null) {
      return const FailureResult(
        Failure(FailureKind.parse, 'info hash is neither hex nor base32'),
      );
    }

    final name = parameters['dn']?.firstOrNull;
    final trackers = <Uri>[];
    for (final tracker in (parameters['tr'] ?? const <String>[])) {
      final uri = Uri.tryParse(tracker);
      if (uri != null && uri.hasScheme) trackers.add(uri);
    }

    return Success(
      MagnetLink(
        infoHashHex: hex,
        displayName: name == null || name.isEmpty ? null : name,
        trackers: trackers,
      ),
    );
  }

  /// Decodes a magnet query string.
  ///
  /// `Uri.splitQueryString` is not usable here: a magnet may carry the same key
  /// more than once (`tr` is the normal case) and separators are unencoded.
  static Map<String, List<String>> _parseQuery(String body) {
    final body_ = body.startsWith('?') ? body.substring(1) : body;
    final fields = <String, List<String>>{};
    for (final pair in body_.split('&')) {
      if (pair.isEmpty) continue;
      final split = pair.indexOf('=');
      if (split <= 0) continue;
      final key = _decode(pair.substring(0, split)).toLowerCase();
      final value = _decode(pair.substring(split + 1));
      fields.putIfAbsent(key, () => <String>[]).add(value);
    }
    return fields;
  }

  /// Decodes a magnet query component.
  ///
  /// Magnet parameters are form encoded, where `+` stands for a space.
  /// `Uri.decodeComponent` does not make that substitution, so `dn=Some+Game`
  /// would otherwise arrive as `Some+Game`.
  static String _decode(String component) =>
      Uri.decodeComponent(component.replaceAll('+', ' '));

  static String _topicValue(String topic) {
    final parts = topic.split(':');
    return parts.length >= 3 ? parts.sublist(2).join(':') : '';
  }

  static bool _isBtih(String value) =>
      value.toLowerCase().startsWith('urn:btih:');

  /// Accepts either a 40 character hex hash or the 32 character base32 form.
  static String? _normalizeInfoHash(String raw) {
    final value = raw.split(':').last.trim();
    if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value)) {
      return value.toLowerCase();
    }
    final base32 = value.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (RegExp(r'^[A-Z2-7]{32}$').hasMatch(base32)) {
      return _base32ToHex(base32);
    }
    return null;
  }

  static const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Converts RFC 4648 base32 to lowercase hex.
  ///
  /// 32 base32 characters carry 160 bits, exactly the width of an info hash.
  static String? _base32ToHex(String input) {
    var bits = 0;
    var value = 0;
    final buffer = StringBuffer();

    for (final character in input.toUpperCase().split('')) {
      final index = _base32Alphabet.indexOf(character);
      if (index < 0) return null;
      value = (value << 5) | index;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        final byte = (value >> bits) & 0xFF;
        buffer.write(byte.toRadixString(16).padLeft(2, '0'));
      }
    }
    return buffer.toString().toLowerCase();
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
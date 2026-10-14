import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/download/magnet_link.dart';

/// Reference vector: RFC 4648 base32 of a 20 byte info hash.
const _hexHash = '0123456789abcdef0123456789abcdef01234567';
const _base32Hash = 'AERUKZ4JVPG66AJDIVTYTK6N54ASGRLH';

void main() {
  group('MagnetLink.parse', () {
    test('rejects a string that is not a magnet', () {
      final result = MagnetLink.parse('https://example.com/game.torrent');
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.parse);
    });

    test('rejects an empty string', () {
      expect(MagnetLink.parse('').isSuccess, isFalse);
    });

    test('rejects a magnet with no exact topic', () {
      final result = MagnetLink.parse('magnet:?dn=Some+Game');
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.message, contains('btih'));
    });

    test('rejects an exact topic that is not btih', () {
      final result = MagnetLink.parse(
        'magnet:?xt=urn:sha1:0123456789abcdef0123456789abcdef01234567&dn=x',
      );
      expect(result.isSuccess, isFalse);
    });

    test('reads a hex info hash', () {
      final link = MagnetLink.parse('magnet:?xt=urn:btih:$_hexHash').valueOrNull!;
      expect(link.infoHashHex, _hexHash);
    });

    test('lowercases an uppercase hex hash', () {
      final link = MagnetLink
          .parse('magnet:?xt=urn:btih:${_hexHash.toUpperCase()}')
          .valueOrNull!;
      expect(link.infoHashHex, _hexHash);
    });

    test('converts a base32 info hash to hex', () {
      final link = MagnetLink.parse('magnet:?xt=urn:btih:$_base32Hash').valueOrNull!;
      expect(link.infoHashHex, _hexHash);
    });

    test('accepts a lower case base32 hash', () {
      final link = MagnetLink
          .parse('magnet:?xt=urn:btih:${_base32Hash.toLowerCase()}')
          .valueOrNull!;
      expect(link.infoHashHex, _hexHash);
    });

    test('rejects a hash of the wrong length', () {
      expect(MagnetLink.parse('magnet:?xt=urn:btih:abcd').isSuccess, isFalse);
    });

    test('rejects a 39 character hex hash', () {
      expect(
        MagnetLink.parse('magnet:?xt=urn:btih:${_hexHash.substring(1)}')
            .isSuccess,
        isFalse,
      );
    });

    test('rejects a non alphanumeric hash', () {
      expect(
        MagnetLink.parse('magnet:?xt=urn:btih:${'z' * 40}').isSuccess,
        isFalse,
      );
    });

    test('reads the display name', () {
      final link = MagnetLink
          .parse('magnet:?xt=urn:btih:$_hexHash&dn=Cyberpunk+2077').valueOrNull!;
      expect(link.displayName, 'Cyberpunk 2077');
    });

    test('decodes a percent encoded display name', () {
      final link = MagnetLink
          .parse('magnet:?xt=urn:btih:$_hexHash&dn=100%25%20Done').valueOrNull!;
      expect(link.displayName, '100% Done');
    });

    test('leaves the name null when absent', () {
      final link = MagnetLink.parse('magnet:?xt=urn:btih:$_hexHash').valueOrNull!;
      expect(link.displayName, isNull);
    });

    test('collects every repeated tracker', () {
      final link = MagnetLink.parse(
        'magnet:?xt=urn:btih:$_hexHash'
        '&tr=udp%3A%2F%2Ftracker.one%3A1337%2Fannounce'
        '&tr=udp%3A%2F%2Ftracker.two%3A1337%2Fannounce'
        '&tr=wss%3A%2F%2Ftracker.three',
      ).valueOrNull!;
      expect(link.trackers.length, 3);
      expect(link.trackers.first.host, 'tracker.one');
      expect(link.trackers.last.scheme, 'wss');
    });

    test('drops a tracker without a scheme', () {
      final link = MagnetLink
          .parse('magnet:?xt=urn:btih:$_hexHash&tr=tracker.example').valueOrNull!;
      expect(link.trackers, isEmpty);
    });

    test('parses a full real-world shaped link', () {
      final link = MagnetLink.parse(
        'magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a'
        '&dn=Elden+Ring+v1.10+FitGirl+Repack'
        '&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce'
        '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'
        '&tr=udp%3A%2F%2Fexodus.desync.com%3A6969%2Fannounce',
      );
      expect(link.isSuccess, isTrue);
      expect(link.valueOrNull!.infoHashHex,
          'c12fe1c06bba254a9dc9f519b335aa7c1367a88a');
      expect(link.valueOrNull!.displayName, 'Elden Ring v1.10 FitGirl Repack');
      expect(link.valueOrNull!.trackers.length, 3);
    });

    test('tolerates a bare leading question mark with no parameters', () {
      expect(MagnetLink.parse('magnet:?').isSuccess, isFalse);
    });

    test('tolerates stray ampersands and empty pairs', () {
      final link = MagnetLink
          .parse('magnet:?xt=urn:btih:$_hexHash&&&dn=x').valueOrNull!;
      expect(link.infoHashHex, _hexHash);
      expect(link.displayName, 'x');
    });

    test('ignores a value with no key', () {
      final link = MagnetLink
          .parse('magnet:?xt=urn:btih:$_hexHash&orphan').valueOrNull!;
      expect(link.infoHashHex, _hexHash);
    });

    test('is case insensitive about the magnet scheme', () {
      expect(MagnetLink.parse('MAGNET:?xt=urn:btih:$_hexHash').isSuccess, isTrue);
    });

    test('is case insensitive about the urn prefix', () {
      expect(
        MagnetLink.parse('magnet:?xt=URN:BTIH:$_hexHash').isSuccess,
        isTrue,
      );
    });
  });
}
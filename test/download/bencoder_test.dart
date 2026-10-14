import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/download/engine/bencoder.dart';

/// Minimal bencode reader used only to assert on encoder output.
Object? decodeBencode(List<int> bytes) {
  var offset = 0;

  Object? readValue() {
    final marker = bytes[offset];
    if (marker == 0x64) {
      offset++;
      final map = <String, Object?>{};
      while (bytes[offset] != 0x65) {
        final key = readValue()! as String;
        map[key] = readValue();
      }
      offset++;
      return map;
    }
    if (marker == 0x6c) {
      offset++;
      final list = <Object?>[];
      while (bytes[offset] != 0x65) {
        list.add(readValue());
      }
      offset++;
      return list;
    }
    if (marker == 0x69) {
      offset++;
      final end = bytes.indexOf(0x65, offset);
      final value = String.fromCharCodes(bytes.sublist(offset, end));
      offset = end + 1;
      return value;
    }
    final colon = bytes.indexOf(0x3a, offset);
    final length = int.parse(
      latin1.decode(bytes.sublist(offset, colon)),
    );
    final start = colon + 1;
    offset = start + length;
    return latin1.decode(bytes.sublist(start, offset));
  }

  return readValue();
}

void main() {
  // A real single-file torrent info dictionary.
  final infoDictionary = Uint8List.fromList(utf8.encode(
    'd6:lengthi1024e4:name8:test.txt12:piece lengthi16384e6:pieces20:'
    '0123456789abcdefghij3:foo3:bare',
  ));
  final infoHash = sha1.convert(infoDictionary).toString();

  group('encodeTorrentEnvelope', () {
    test('produces a decodable dictionary', () {
      final encoded = encodeTorrentEnvelope(infoDictionary: infoDictionary);
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      expect(decoded.keys, containsAll(<String>['info']));
    });

    test('preserves the info dictionary byte for byte', () {
      final encoded = encodeTorrentEnvelope(infoDictionary: infoDictionary);
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      final info = decoded['info']! as String;
      expect(info, latin1.decode(infoDictionary));
    });

    test('keeps the info hash valid after splicing', () {
      // This is the reason the raw bytes are spliced rather than decoded and
      // re-encoded: the SHA1 must still match the magnet.
      final encoded = encodeTorrentEnvelope(
        announce: 'udp://tracker.example:1337/announce',
        infoDictionary: infoDictionary,
      );
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      final rebuilt = Uint8List.fromList(
        latin1.encode(decoded['info']! as String).toList(),
      );
      expect(sha1.convert(rebuilt).toString(), infoHash);
    });

    test('includes an announce when supplied', () {
      final encoded = encodeTorrentEnvelope(
        announce: 'udp://tracker.example:1337/announce',
        infoDictionary: infoDictionary,
      );
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      expect(decoded['announce'], 'udp://tracker.example:1337/announce');
    });

    test('omits announce when absent', () {
      final encoded = encodeTorrentEnvelope(infoDictionary: infoDictionary);
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      expect(decoded.containsKey('announce'), isFalse);
    });

    test('omits an empty announce', () {
      final encoded = encodeTorrentEnvelope(
        announce: '',
        infoDictionary: infoDictionary,
      );
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      expect(decoded.containsKey('announce'), isFalse);
    });

    test('includes a comment when supplied', () {
      final encoded = encodeTorrentEnvelope(
        comment: 'prjct_rpck',
        infoDictionary: infoDictionary,
      );
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      expect(decoded['comment'], 'prjct_rpck');
    });

    test('starts with a dictionary marker and ends with its terminator', () {
      final encoded = encodeTorrentEnvelope(infoDictionary: infoDictionary);
      expect(encoded.first, 0x64); // 'd'
      expect(encoded.last, 0x65); // 'e'
    });

    test('declares the info length correctly', () {
      final encoded = encodeTorrentEnvelope(infoDictionary: infoDictionary);
      final text = latin1.decode(encoded);
      expect(text, contains('${infoDictionary.length}:'));
    });

    test('handles an empty info dictionary', () {
      final encoded = encodeTorrentEnvelope(infoDictionary: Uint8List(0));
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      expect(decoded['info'], '');
    });

    test('handles an info dictionary larger than nine bytes', () {
      final large = Uint8List.fromList(List<int>.filled(300, 0x61));
      final encoded = encodeTorrentEnvelope(infoDictionary: large);
      final decoded = decodeBencode(encoded) as Map<String, Object?>;
      expect((decoded['info']! as String).length, 300);
    });
  });
}
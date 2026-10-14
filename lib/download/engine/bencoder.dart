import 'dart:convert';
import 'dart:typed_data';

/// Minimal bencode encoder able to splice an already encoded dictionary.
///
/// BEP 9 hands back the raw bytes of the `info` dictionary. Decoding and
/// re-encoding it would work, but it risks a byte difference on any value the
/// decoder represents imperfectly, and the info hash is a SHA1 over exactly
/// those bytes. Splicing the original bytes keeps the hash valid by
/// construction.
Uint8List encodeTorrentEnvelope({
  String? announce,
  String? comment,
  required Uint8List infoDictionary,
}) {
  final fields = <int>[];

  // The dictionary marker opens the buffer; every field follows it.
  fields.add(0x64); // 'd'

  if (announce != null && announce.isNotEmpty) {
    fields
      ..addAll(_encodeBytes(utf8.encode('announce')))
      ..addAll(_encodeBytes(utf8.encode(announce)));
  }
  if (comment != null && comment.isNotEmpty) {
    fields
      ..addAll(_encodeBytes(utf8.encode('comment')))
      ..addAll(_encodeBytes(utf8.encode(comment)));
  }

  // `info` is emitted last so its bytes are copied verbatim.
  // The dictionary marker opens the buffer, before every field.
  fields
    ..addAll(_encodeBytes(utf8.encode('info')))
    ..addAll(utf8.encode('${infoDictionary.length}:'))
    ..addAll(infoDictionary)
    ..add(0x65); // 'e'

  return Uint8List.fromList(fields);
}

List<int> _encodeBytes(List<int> bytes) => [
      ...utf8.encode('${bytes.length}:'),
      ...bytes,
    ];
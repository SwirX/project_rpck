import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/models/source_option_codec.dart';
import 'transfer.dart';

/// Remembers transfers across a restart.
///
/// Without this there was nothing for "resume transfers on launch" to resume:
/// the registry lived in memory, so every transfer was simply gone the next
/// time the app opened. Engines already continue from their `.partial` files,
/// so restoring the record is enough to make a resumed transfer pick up where
/// it stopped.
class TransferJournal {
  final File _file;

  TransferJournal(this._file);

  /// Opens the journal inside the application support directory.
  static Future<TransferJournal> open(String supportDirectory) async {
    final directory = Directory('$supportDirectory/transfers');
    if (!await directory.exists()) await directory.create(recursive: true);
    return TransferJournal(File('${directory.path}/journal.json'));
  }

  /// Records the current set of transfers.
  ///
  /// Failures are reported, not thrown. The journal is a convenience, and a
  /// read-only or full disk must not take down a running download.
  Future<void> save(List<Transfer> transfers) async {
    try {
      final payload = jsonEncode({
        'version': _version,
        'transfers': [
          for (final transfer in transfers)
            {
              'id': transfer.id,
              'title': transfer.title,
              'savePath': transfer.savePath,
              'status': transfer.status.name,
              'downloadedBytes': transfer.downloadedBytes,
              'totalBytes': transfer.totalBytes,
              'source': SourceOptionCodec.encode(transfer.source),
            },
        ],
      });
      await _file.writeAsString(payload, flush: true);
    } catch (error) {
      debugPrint('transfer journal could not be written: $error');
    }
  }

  /// Reads back whatever survives.
  ///
  /// A corrupt or unreadable journal yields an empty list rather than an error:
  /// the worst outcome is that the downloads list starts empty, which the user
  /// can fix by starting a download again.
  Future<List<Transfer>> load() async {
    try {
      if (!await _file.exists()) return const [];
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map) return const [];
      final entries = decoded['transfers'];
      if (entries is! List) return const [];

      final restored = <Transfer>[];
      for (final entry in entries) {
        if (entry is! Map) continue;
        final transfer = _decode(entry);
        if (transfer != null) restored.add(transfer);
      }
      return restored;
    } catch (error) {
      debugPrint('transfer journal could not be read: $error');
      return const [];
    }
  }

  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (error) {
      debugPrint('transfer journal could not be cleared: $error');
    }
  }

  static Transfer? _decode(Map<Object?, Object?> entry) {
    final id = entry['id'];
    final title = entry['title'];
    final savePath = entry['savePath'];
    final source = SourceOptionCodec.decode(entry['source']);
    if (id is! String || title is! String || savePath is! String) return null;
    if (source == null) return null;

    // Anything unfinished when the process died comes back queued, because
    // nothing is running behind it and re-resolving a magnet needs the engine.
    // A finished transfer keeps its terminal status, or it would be downloaded
    // a second time on every launch.
    final recorded = TransferStatus.values
        .where((status) => status.name == entry['status'])
        .firstOrNull;

    return Transfer(
      id: id,
      title: title,
      source: source,
      status: recorded != null && recorded.isTerminal ? recorded : TransferStatus.queued,
      downloadedBytes: (entry['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (entry['totalBytes'] as num?)?.toInt() ?? 0,
      bytesPerSecond: 0,
      connectedPeers: 0,
      availablePeers: 0,
      savePath: savePath,
    );
  }

  static const _version = 1;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
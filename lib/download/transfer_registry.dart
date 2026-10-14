import 'dart:async';

import '../core/result.dart';
import '../domain/models/source_option.dart';
import 'engine/direct_engine.dart';
import 'engine/download_engine.dart';
import 'engine/magnet_engine.dart';
import 'engine/torrent_engine.dart';
import 'transfer.dart';

/// Dispatches a [SourceOption] to the engine that can handle it and keeps the
/// latest snapshot of every transfer.
///
/// The prototype had a `TorrentManager` that nothing instantiated, and a
/// downloads screen rendering three hardcoded games. Both are replaced here.
///
/// The stream carries the whole ordered list rather than one transfer, so a
/// removal is representable without a sentinel value.
class TransferRegistry {
  final List<DownloadEngine> _engines;
  final StreamController<List<Transfer>> _snapshots =
      StreamController<List<Transfer>>.broadcast();

  final Map<String, Transfer> _byId = {};

  TransferRegistry({List<DownloadEngine>? engines})
      : _engines = engines ??
            [TorrentEngine(), MagnetEngine(), DirectEngine()];

  Stream<List<Transfer>> get snapshots => _snapshots.stream;

  List<Transfer> get all => _byId.values.toList(growable: false);

  Iterable<Transfer> get active =>
      _byId.values.where((transfer) => transfer.isActive);

  Iterable<Transfer> get completed => _byId.values
      .where((transfer) => transfer.status == TransferStatus.completed);

  Transfer? byId(String id) => _byId[id];

  /// The engine registered for [option], or null when none accepts it.
  DownloadEngine? engineFor(SourceOption option) {
    for (final engine in _engines) {
      if (engine.supports(option)) return engine;
    }
    return null;
  }

  void _publish(Transfer transfer) {
    _byId[transfer.id] = transfer;
    _publishAll();
  }

  void _publishAll() {
    if (_snapshots.isClosed) return;
    _snapshots.add(all);
  }

  /// Registers a queued transfer without starting it.
  Transfer enqueue(Transfer transfer) {
    _publish(transfer);
    return transfer;
  }

  /// Starts [transfer] on whichever engine supports its source.
  Future<Result<Transfer>> start(Transfer transfer) async {
    final engine = engineFor(transfer.source);
    if (engine == null) {
      final message =
          'no engine handles ${transfer.source.runtimeType}';
      _publish(transfer.copyWith(
        status: TransferStatus.failed,
        errorMessage: message,
      ));
      return FailureResult(Failure(FailureKind.unknown, message));
    }

    _publish(transfer.copyWith(status: TransferStatus.queued));

    unawaited(() async {
      try {
        final stream = await engine.start(transfer);
        await stream.listen(
          _publish,
          onError: (Object error) => _publish(transfer.copyWith(
            status: TransferStatus.failed,
            errorMessage: '$error',
          )),
        ).asFuture<void>();
      } catch (error) {
        _publish(transfer.copyWith(
          status: TransferStatus.failed,
          errorMessage: '$error',
        ));
      }
    }());

    return Success(transfer);
  }

  /// Forgets a transfer. The downloaded bytes are left on disk deliberately.
  void remove(String id) {
    _byId.remove(id);
    _publishAll();
  }

  void clear() {
    _byId.clear();
    _publishAll();
  }

  Future<void> dispose() => _snapshots.close();
}
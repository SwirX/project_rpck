import 'dart:async';

import '../core/result.dart';
import '../domain/models/source_option.dart';
import 'engine/direct_engine.dart';
import 'engine/download_engine.dart';
import 'engine/magnet_engine.dart';
import 'engine/torrent_engine.dart';
import '../ui/settings_controller.dart';
import 'transfer.dart';
import 'transfer_journal.dart';

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

  /// Fires once per transfer that reaches `completed`, for the completion
  /// notice. Separate from [snapshots] because the notice must not re-render
  /// the whole downloads list.
  final StreamController<Transfer> _completions =
      StreamController<Transfer>.broadcast();

  final Map<String, Transfer> _byId = {};

  /// Absent in tests that do not exercise persistence.
  final TransferJournal? _journal;

  final SettingsController? _settings;

  TransferRegistry({
    List<DownloadEngine>? engines,
    TransferJournal? journal,
    SettingsController? settings,
  })  : _engines = engines ?? [TorrentEngine(), MagnetEngine(), DirectEngine()],
        _journal = journal,
        _settings = settings;

  Stream<List<Transfer>> get snapshots => _snapshots.stream;

  Stream<Transfer> get completions => _completions.stream;

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
    final previous = _byId[transfer.id];
    _byId[transfer.id] = transfer;

    // Announce once, on the transition, not on every progress tick that still
    // reports the same finished state.
    if (transfer.status == TransferStatus.completed &&
        previous?.status != TransferStatus.completed &&
        !_completions.isClosed) {
      _completions.add(transfer);
    }
    if (previous?.status != transfer.status) _persist();

    _publishAll();
  }

  void _persist() {
    final journal = _journal;
    if (journal == null) return;
    unawaited(journal.save(all));
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

  /// Restores what a previous session left behind.
  ///
  /// Completed and failed transfers come back as history so the list is not
  /// silently emptied; only unfinished ones are restarted, and only when the
  /// user has asked for that. Returns how many were picked back up.
  Future<int> restorePending() async {
    final journal = _journal;
    if (journal == null) return 0;

    final restored = await journal.load();
    if (restored.isEmpty) return 0;

    for (final transfer in restored) {
      _byId[transfer.id] = transfer;
    }
    _publishAll();

    if (!(_settings?.current.resumeTransfersOnLaunch ?? true)) return 0;

    var resumed = 0;
    for (final transfer in restored.where((t) => !t.isTerminal)) {
      if (engineFor(transfer.source) == null) continue;
      await start(transfer);
      resumed++;
    }
    return resumed;
  }

  /// Forgets a transfer. The downloaded bytes are left on disk deliberately.
  void remove(String id) {
    _byId.remove(id);
    _persist();
    _publishAll();
  }

  void clear() {
    _byId.clear();
    unawaited(_journal?.clear() ?? Future<void>.value());
    _publishAll();
  }

  Future<void> dispose() async {
    await _snapshots.close();
    await _completions.close();
  }
}
import 'dart:async';

import '../../domain/models/source_option.dart';
import '../transfer.dart';

/// Acquire a payload and report progress.
///
/// Three implementations exist: `TorrentEngine` for a `.torrent` mirror,
/// `MagnetEngine` for a `magnet:` link, and `DirectEngine` for a plain HTTP
/// mirror. The UI depends only on this interface.
abstract interface class DownloadEngine {
  /// Whether this engine can handle [option].
  bool supports(SourceOption option);

  /// Starts the transfer and returns a stream of snapshots.
  ///
  /// The stream stays open until the transfer reaches a terminal state. The
  /// returned future completes once the engine has accepted the request.
  Future<Stream<Transfer>> start(Transfer transfer);
}

/// Coalesces a fast event source into a bounded-rate stream.
///
/// `dtorrent_task` emits per-piece, which for a healthy swarm is several events
/// a second per transfer. Forwarding every one to the UI rebuilds the subtree
/// far more often than a person can read, so updates are sampled.
Stream<T> throttleStream<T>(
  Stream<T> source, {
  Duration interval = const Duration(milliseconds: 250),
}) {
  Timer? timer;
  T? pending;
  var hasPending = false;

  final controller = StreamController<T>();
  late final StreamSubscription<T> subscription;

  void flush() {
    if (!hasPending) return;
    hasPending = false;
    controller.add(pending as T);
  }

  subscription = source.listen(
    (value) {
      pending = value;
      hasPending = true;
      timer ??= Timer(interval, () {
        timer = null;
        flush();
      });
    },
    onError: controller.addError,
    onDone: () async {
      timer?.cancel();
      flush();
      await controller.close();
    },
  );

  controller.onCancel = () async {
    timer?.cancel();
    await subscription.cancel();
  };

  return controller.stream;
}
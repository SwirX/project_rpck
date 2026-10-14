import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';

import '../../domain/models/source_option.dart';
import '../transfer.dart';
import 'download_engine.dart';

/// Drives a torrent download through `dtorrent_task`.
///
/// `dtorrent_task` is pure Dart, so the same engine covers Windows, Linux and
/// Android without a per-platform native client.
///
/// Progress comes from the task's own `TaskCompleted`/`AllComplete` events
/// rather than by polling `progress`, and the resulting stream is throttled
/// because the task emits per-piece under a healthy swarm.
class TorrentEngine implements DownloadEngine {
  final Dio _client;

  TorrentEngine({Dio? client})
      : _client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              maxRedirects: 8,
            ));

  @override
  bool supports(SourceOption option) => option is TorrentFileOption;

  @override
  Future<Stream<Transfer>> start(Transfer transfer) async {
    final option = transfer.source as TorrentFileOption;
    try {
      final bytes = await _fetchTorrentFile(option.torrentUri);
      return startFromBytes(bytes, transfer);
    } catch (error) {
      return Stream.value(failedSnapshot(transfer, option, '$error'));
    }
  }

  /// Starts a transfer from an in-memory `.torrent`.
  ///
  /// Used directly by [TorrentFileOption] paths and by `MagnetEngine`, which
  /// synthesises the same bytes once BEP 9 has resolved the info dictionary.
  Stream<Transfer> startFromBytes(Uint8List torrentBytes, Transfer transfer) {
    final option = transfer.source;
    final controller = StreamController<Transfer>();
    TorrentTask? task;
    void Function()? cancelEvents;

    void emit(TransferStatus status, {String? error}) {
      if (controller.isClosed) return;
      controller.add(
        Transfer(
          id: transfer.id,
          title: transfer.title,
          status: status,
          downloadedBytes: task?.downloaded ?? 0,
          totalBytes: task?.metaInfo.length ?? 0,
          bytesPerSecond: task?.averageDownloadSpeed ?? 0,
          connectedPeers: task?.connectedPeersNumber ?? 0,
          availablePeers: task?.allPeersNumber ?? 0,
          savePath: transfer.savePath,
          source: option,
          errorMessage: error,
        ),
      );
    }

    unawaited(() async {
      try {
        final model = await Torrent.parse(torrentBytes);
        final started = TorrentTask.newTask(model, transfer.savePath);
        task = started;
        cancelEvents = started.events.listen((event) {
          try {
            if (event is AllComplete || event is TaskCompleted) {
              emit(TransferStatus.completed);
              cancelEvents?.call();
              unawaited(controller.close());
            } else {
              emit(TransferStatus.downloading);
            }
          } catch (error) {
            emit(TransferStatus.failed, error: '$error');
            cancelEvents?.call();
            unawaited(controller.close());
          }
        });

        await started.start();
        emit(TransferStatus.downloading);
      } catch (error) {
        emit(TransferStatus.failed, error: '$error');
        await controller.close();
      }
    }());

    controller.onCancel = () async {
      cancelEvents?.call();
      await task?.stop();
    };

    return throttleStream(controller.stream);
  }

  Future<Uint8List> _fetchTorrentFile(Uri uri) async {
    final response = await _client.get<List<int>>(
      uri.toString(),
      options: Options(responseType: ResponseType.bytes),
    );
    final status = response.statusCode ?? 0;
    if (status != 200) {
      throw StateError('torrent file request returned HTTP $status');
    }
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw StateError('torrent file at $uri was empty');
    }
    return Uint8List.fromList(data);
  }
}

/// Snapshot used when a transfer cannot be started at all.
Transfer failedSnapshot(Transfer transfer, SourceOption source, String error) =>
    transfer.copyWith(status: TransferStatus.failed, errorMessage: error);
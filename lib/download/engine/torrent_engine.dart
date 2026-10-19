import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:events_emitter2/events_emitter2.dart' show CancelListenFunc;

import '../../core/result.dart';
import '../../domain/models/source_option.dart';
import '../magnet_link.dart';
import 'bencoder.dart';
import 'index_access_strategy.dart';
import '../transfer.dart';
import 'download_engine.dart';
import 'torrent_index_resolver.dart';

/// Drives a torrent download through `dtorrent_task`.
///
/// `dtorrent_task` is pure Dart, so the same engine covers Windows, Linux and
/// Android without a native client.
///
/// Three entry points are accepted: a `.torrent` file, a tracker listing page
/// that has to be expanded first, and, as the fallback when an index is blocked,
/// a magnet recovered from that index.
///
/// Progress comes from the task's own `AllComplete` and `TaskCompleted` events,
/// and the resulting stream is throttled because the task emits per-piece.
class TorrentEngine implements DownloadEngine {
  final Dio _client;
  final TorrentIndexResolver _indexResolver;

  /// Optional explicit path to a headless browser the user installed.
  final String? configuredBrowserPath;

  TorrentEngine({
    Dio? client,
    TorrentIndexResolver? indexResolver,
    this.configuredBrowserPath,
  })
      : _client = client ?? _defaultClient(),
        _indexResolver = indexResolver ??
            TorrentIndexResolver(
              chainFactory: (uri) => buildDefaultChain(
                host: uri.host,
                configuredBrowserPath: configuredBrowserPath,
              ),
            );

  static Dio _defaultClient() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: true,
          maxRedirects: 8,
          validateStatus: (_) => true,
        ),
      );

  /// The default access chain: browser headers, then an installed headless
  /// browser if one exists, then a handoff to the user's own browser.
  ///
  /// Built lazily because discovering a browser binary shells out, which must
  /// not happen on every construction.
  static Future<List<IndexAccessStrategy>> buildDefaultChain({
    required String host,
    String? configuredBrowserPath,
  }) async {
    // ignore: unnecessary_lambdas
    return <IndexAccessStrategy>[
      HeaderSpoofingStrategy(
        userAgent: _defaultClient().options.headers['User-Agent'] ?? '',
        host: host,
      ),
      StealthBrowserStrategy(
        executablePath:
            await StealthBrowserStrategy.discover(configuredPath: configuredBrowserPath),
      ),
      BrowserHandoffStrategy(),
    ];
  }

  @override
  bool supports(SourceOption option) =>
      option is TorrentFileOption || option is TorrentIndexOption;

  @override
  Future<Stream<Transfer>> start(Transfer transfer) async {
    try {
      final source = transfer.source;
      if (source is TorrentFileOption) {
        return startFromBytes(await _fetchTorrentFile(source.torrentUri), transfer);
      }
      if (source is TorrentIndexOption) {
        return await _startFromIndex(transfer, source.listingUri);
      }
      return Stream.value(
        failedSnapshot(transfer, source, 'torrent engine cannot handle this source'),
      );
    } catch (error) {
      return Stream.value(failedSnapshot(transfer, transfer.source, '$error'));
    }
  }

  /// Expands a tracker listing into a torrent file, or falls back to a magnet.
  ///
  /// A blocked index degrades to the magnet it exposed rather than failing, so
  /// a challenge page does not cost the user the download.
  Future<Stream<Transfer>> _startFromIndex(Transfer transfer, Uri listingUri) async {
    final expanded = await _indexResolver.expand(listingUri);
    if (expanded case FailureResult(:final failure)) {
      return Stream.value(
        failedSnapshot(transfer, transfer.source, failure.message),
      );
    }

    final resolved = expanded.valueOrNull!;
    final torrentUri = resolved.torrentUri;
    if (torrentUri != null) {
      try {
        return startFromBytes(await _fetchTorrentFile(torrentUri), transfer);
      } catch (_) {
        // Fall through to the magnet when the torrent file will not download.
      }
    }

    if (resolved.magnets.isNotEmpty) {
      return startFromBytes(
        await _torrentFromMagnet(resolved.magnets.first),
        transfer,
      );
    }
    return Stream.value(
      failedSnapshot(transfer, transfer.source, 'the index exposed no torrent'),
    );
  }

  /// Builds a torrent file in memory from a magnet's metadata block.
  Future<Uint8List> _torrentFromMagnet(String magnet) async {
    final parsed = MagnetLink.parse(magnet);
    if (parsed case FailureResult(:final failure)) {
      throw StateError(failure.message);
    }
    final link = parsed.valueOrNull!;

    final downloader = MetadataDownloader(link.infoHashHex);
    try {
      final completer = Completer<Uint8List>();
      downloader.events.listen((event) async {
        if (event is! MetaDataDownloadComplete || completer.isCompleted) return;
        final metadata = Uint8List.fromList(event.data);
        final digest = sha1.convert(metadata).toString().toLowerCase();
        if (digest != link.infoHashHex) {
          completer.completeError(
            StateError('resolved metadata does not match the info hash'),
          );
          return;
        }
        completer.complete(
          encodeTorrentEnvelope(
            announce:
                link.trackers.isEmpty ? null : link.trackers.first.toString(),
            infoDictionary: metadata,
          ),
        );
      });

      await downloader.startDownload();
      return await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw StateError('no peer offered torrent metadata'),
      );
    } finally {
      await downloader.stop();
    }
  }

  /// Starts a transfer from an in-memory `.torrent`.
  ///
  /// Used directly by [TorrentFileOption] paths and by an index expansion that
  /// produced bencode rather than a file.
  Stream<Transfer> startFromBytes(Uint8List torrentBytes, Transfer transfer) {
    final option = transfer.source;
    final controller = StreamController<Transfer>();
    TorrentTask? task;
    CancelListenFunc? cancelEvents;

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
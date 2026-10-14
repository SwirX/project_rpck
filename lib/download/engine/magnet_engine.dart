import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task/dtorrent_task.dart';

import '../../core/result.dart';
import '../../domain/models/source_option.dart';
import '../magnet_link.dart';
import '../transfer.dart';
import 'bencoder.dart';
import 'download_engine.dart';
import 'torrent_engine.dart';

/// Resolves a `magnet:` link, then hands off to the torrent engine.
///
/// `dtorrent_parser` cannot parse magnets, so resolution uses BEP 9 metadata
/// exchange: `MetadataDownloader` pulls the bencoded `info` dictionary from any
/// peer that offers it, and the result is wrapped in a torrent envelope.
///
/// `MetadataDownloader.startDownload()` bootstraps DHT only and never contacts
/// the trackers named in the magnet. Peer discovery therefore relies on DHT
/// unless HTTP tracker peers are injected first, which is what [_scrapeTrackers]
/// does. A magnet carrying only UDP trackers falls back to DHT alone.
class MagnetEngine implements DownloadEngine {
  final Dio _client;
  final TorrentEngine _torrent;
  final Duration _metadataTimeout;

  MagnetEngine({
    Dio? client,
    TorrentEngine? torrent,
    Duration metadataTimeout = const Duration(minutes: 2),
  })  : _client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _metadataTimeout = metadataTimeout,
        _torrent = torrent ?? TorrentEngine();

  @override
  bool supports(SourceOption option) => option is MagnetOption;

  @override
  Future<Stream<Transfer>> start(Transfer transfer) async {
    final option = transfer.source as MagnetOption;
    final controller = StreamController<Transfer>();

    void emit(TransferStatus status, {String? error}) {
      if (controller.isClosed) return;
      controller.add(
        transfer.copyWith(status: status, errorMessage: error),
      );
    }

    emit(TransferStatus.resolving);

    final parsed = MagnetLink.parse(option.magnet);
    if (parsed case FailureResult(:final failure)) {
      emit(TransferStatus.failed, error: failure.message);
      await controller.close();
      return controller.stream;
    }
    final link = parsed.valueOrNull!;

    MetadataDownloader? downloader;
    void Function()? cancelMetadata;
    StreamSubscription<Transfer>? payloadEvents;
    Timer? deadline;
    var settled = false;

    void settle() {
      if (settled) return;
      settled = true;
      deadline?.cancel();
      unawaited(controller.close());
    }

    Future<void> cleanUp() async {
      deadline?.cancel();
      cancelMetadata?.call();
      await downloader?.stop();
    }

    try {
      for (final peer in await _scrapeTrackers(link.trackers)) {
        // Peers discovered ahead of startDownload are ignored by the library,
        // so they are queued and injected once it is running.
        _pendingPeers.add(peer);
      }

      downloader = MetadataDownloader(link.infoHashHex);
      final active = downloader;
      cancelMetadata = active.events.listen((event) async {
        if (event is! MetaDataDownloadComplete || settled) return;
        try {
          final envelope = _buildEnvelope(link, event.data);
          if (envelope == null) {
            emit(TransferStatus.failed,
                error: 'resolved metadata does not match the info hash');
            await cleanUp();
            settle();
            return;
          }
          await active.stop();
          payloadEvents =
              _torrent.startFromBytes(envelope, transfer).listen(
            (state) {
              if (settled) return;
              controller.add(state);
              if (state.isTerminal) settle();
            },
            onError: (Object error) {
              if (settled) return;
              emit(TransferStatus.failed, error: '$error');
              settle();
            },
          );
        } catch (error) {
          emit(TransferStatus.failed, error: 'metadata unusable: $error');
          await cleanUp();
          settle();
        }
      });

      await active.startDownload();
      for (final peer in _pendingPeers) {
        active.addNewPeerAddress(peer, PeerSource.tracker);
      }
      _pendingPeers.clear();

      // DHT is not guaranteed to find anyone; do not wait forever.
      deadline = Timer(_metadataTimeout, () {
        if (settled) return;
        emit(TransferStatus.failed, error: 'no peer offered torrent metadata');
        settle();
      });

      controller.onCancel = () async {
        settled = true;
        await cleanUp();
        await payloadEvents?.cancel();
      };

      return controller.stream;
    } catch (error) {
      emit(TransferStatus.failed, error: '$error');
      settle();
      return controller.stream;
    }
  }

  final List<CompactAddress> _pendingPeers = [];

  /// Wraps a resolved info dictionary in a torrent envelope.
  ///
  /// Returns null when the buffer does not hash to the magnet's info hash,
  /// which turns a corrupted BEP 9 payload into a clear error rather than a
  /// silent stall.
  Uint8List? _buildEnvelope(MagnetLink link, List<int> infoDictionary) {
    final dictionary = Uint8List.fromList(infoDictionary);
    final computed = sha1.convert(dictionary).toString().toLowerCase();
    if (computed != link.infoHashHex) return null;
    return encodeTorrentEnvelope(
      announce: link.trackers.isEmpty ? null : link.trackers.first.toString(),
      infoDictionary: dictionary,
    );
  }

  /// Scrapes HTTP(S) trackers for peers that may already hold the metadata.
  ///
  /// UDP and WSS trackers are not spoken here; their peers are reached through
  /// DHT instead.
  Future<List<CompactAddress>> _scrapeTrackers(List<Uri> trackers) async {
    final peers = <CompactAddress>[];
    for (final tracker in trackers.where(
      (uri) => uri.scheme == 'http' || uri.scheme == 'https',
    )) {
      try {
        final response = await _client.get<List<int>>(
          tracker.toString(),
          options: Options(responseType: ResponseType.bytes),
        );
        final status = response.statusCode ?? 0;
        if (status != 200 || response.data == null) continue;
        peers.addAll(CompactAddress.parseIPv4Addresses(response.data!));
      } catch (_) {
        // A tracker that will not answer costs discovery, not the transfer.
      }
    }
    return peers;
  }
}

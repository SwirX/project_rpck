import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/domain/models/source_option.dart';
import 'package:project_rpck/download/engine/download_engine.dart';
import 'package:project_rpck/download/engine/torrent_engine.dart';
import 'package:project_rpck/download/transfer.dart';
import 'package:project_rpck/download/transfer_registry.dart';

final _magnet = MagnetOption('magnet:?xt=urn:btih:aa');
final _torrentFile = TorrentFileOption(Uri.parse('https://x/y.torrent'));
final _direct = DirectOption(Uri.parse('https://example.com/setup.exe'));

/// Engine stand-in that reports a scripted sequence.
class _FakeEngine implements DownloadEngine {
  final SourceOption? accepted;
  final List<Transfer> script;
  final Object? failWith;

  _FakeEngine({this.accepted, this.script = const [], this.failWith});

  @override
  bool supports(SourceOption option) =>
      accepted != null && option.runtimeType == accepted.runtimeType;

  @override
  Future<Stream<Transfer>> start(Transfer transfer) async {
    if (failWith != null) throw failWith!;
    return Stream.fromIterable(script);
  }
}

Transfer transferFor(SourceOption option) => Transfer(
      id: 't1',
      title: 'Fixture Game',
      status: TransferStatus.queued,
      downloadedBytes: 0,
      totalBytes: 0,
      bytesPerSecond: 0,
      connectedPeers: 0,
      availablePeers: 0,
      savePath: '/tmp/fixture',
      source: option,
    );

void main() {
  group('Transfer', () {
    test('reports a null fraction when the size is unknown', () {
      expect(transferFor(_magnet).fraction, isNull);
    });

    test('computes a fraction once the size is known', () {
      expect(
        transferFor(_magnet)
            .copyWith(downloadedBytes: 50, totalBytes: 200)
            .fraction,
        0.25,
      );
    });

    test('treats completed as terminal', () {
      expect(
        transferFor(_magnet).copyWith(status: TransferStatus.completed).isTerminal,
        isTrue,
      );
    });

    test('treats failed as terminal', () {
      expect(
        transferFor(_magnet).copyWith(status: TransferStatus.failed).isTerminal,
        isTrue,
      );
    });

    test('does not treat queued as terminal', () {
      expect(transferFor(_magnet).isTerminal, isFalse);
    });

    test('treats resolving as active', () {
      expect(
        transferFor(_magnet).copyWith(status: TransferStatus.resolving).isActive,
        isTrue,
      );
    });

    test('treats downloading as active', () {
      expect(
        transferFor(_magnet)
            .copyWith(status: TransferStatus.downloading)
            .isActive,
        isTrue,
      );
    });

    test('carries its source through copyWith', () {
      expect(
        transferFor(_magnet).copyWith(status: TransferStatus.paused).source,
        _magnet,
      );
    });
  });

  group('TorrentEngine.supports', () {
    test('accepts a torrent file option', () {
      expect(TorrentEngine().supports(_torrentFile), isTrue);
    });

    test('rejects a magnet option', () {
      expect(TorrentEngine().supports(_magnet), isFalse);
    });

    test('rejects a direct option', () {
      expect(TorrentEngine().supports(_direct), isFalse);
    });
  });

  group('TorrentEngine.startFromBytes', () {
    test('fails cleanly on bytes that are not a torrent', () async {
      final state = await TorrentEngine()
          .startFromBytes(
            Uint8List.fromList(utf8.encode('not a torrent at all')),
            transferFor(_torrentFile),
          )
          .first;
      expect(state.status, TransferStatus.failed);
      expect(state.errorMessage, isNotNull);
    });

    test('fails cleanly on an empty buffer', () async {
      final state =
          await TorrentEngine().startFromBytes(Uint8List(0), transferFor(_torrentFile))
              .first;
      expect(state.status, TransferStatus.failed);
    });
  });

  group('TransferRegistry routing', () {
    test('routes a magnet to the engine that accepts it', () {
      final registry =
          TransferRegistry(engines: [_FakeEngine(accepted: _magnet)]);
      expect(registry.engineFor(_magnet), isNotNull);
    });

    test('returns null when no engine accepts an option', () {
      final registry =
          TransferRegistry(engines: [_FakeEngine(accepted: _magnet)]);
      expect(registry.engineFor(_direct), isNull);
    });

    test('prefers the first matching engine', () {
      final first = _FakeEngine(accepted: _magnet);
      final second = _FakeEngine(accepted: _magnet);
      final registry = TransferRegistry(engines: [first, second]);
      expect(identical(registry.engineFor(_magnet), first), isTrue);
    });

    test('marks a transfer failed when no engine accepts it', () async {
      final registry = TransferRegistry(engines: <DownloadEngine>[]);
      final result = await registry.start(transferFor(_magnet));
      expect(result.isSuccess, isFalse);
      expect(registry.byId('t1')!.status, TransferStatus.failed);
      expect(registry.byId('t1')!.errorMessage, contains('no engine'));
    });
  });

  group('TransferRegistry streams', () {
    test('publishes the scripted snapshot sequence', () async {
      final registry = TransferRegistry(engines: [
        _FakeEngine(
          accepted: _magnet,
          script: [
            transferFor(_magnet).copyWith(status: TransferStatus.resolving),
            transferFor(_magnet).copyWith(
              status: TransferStatus.downloading,
              downloadedBytes: 10,
              totalBytes: 100,
            ),
            transferFor(_magnet).copyWith(status: TransferStatus.completed),
          ],
        ),
      ]);

      final seen = <TransferStatus>[];
      final subscription =
          registry.snapshots.listen((all) => seen.add(all.last.status));

      await registry.start(transferFor(_magnet));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await subscription.cancel();

      expect(seen, contains(TransferStatus.resolving));
      expect(seen, contains(TransferStatus.downloading));
      expect(seen.last, TransferStatus.completed);
    });

    test('records a failure thrown while starting an engine', () async {
      final registry = TransferRegistry(engines: [
        _FakeEngine(accepted: _magnet, failWith: StateError('no route')),
      ]);
      await registry.start(transferFor(_magnet));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(registry.byId('t1')!.status, TransferStatus.failed);
      expect(registry.byId('t1')!.errorMessage, contains('no route'));
    });

    test('separates active from completed transfers', () {
      final registry = TransferRegistry(engines: []);
      registry.enqueue(
        transferFor(_magnet).copyWith(status: TransferStatus.downloading),
      );
      registry.enqueue(
        Transfer(
          id: 't2',
          title: 'Done',
          status: TransferStatus.completed,
          downloadedBytes: 10,
          totalBytes: 10,
          bytesPerSecond: 0,
          connectedPeers: 0,
          availablePeers: 0,
          savePath: '/tmp/done',
          source: _magnet,
        ),
      );

      expect(registry.active.length, 1);
      expect(registry.completed.length, 1);
      expect(registry.all.length, 2);
    });

    test('remove forgets a transfer', () {
      final registry = TransferRegistry(engines: []);
      registry.enqueue(transferFor(_magnet));
      expect(registry.all.length, 1);

      registry.remove('t1');

      expect(registry.all, isEmpty);
      expect(registry.byId('t1'), isNull);
    });

    test('clear empties the registry', () {
      final registry = TransferRegistry(engines: []);
      registry.enqueue(transferFor(_magnet));
      registry.clear();
      expect(registry.all, isEmpty);
    });
  });

  group('throttleStream', () {
    test('collapses a burst into fewer emissions', () async {
      final source = Stream<int>.fromIterable(List.generate(50, (i) => i));
      final emitted = <int>[];
      final subscription = throttleStream(
        source,
        interval: const Duration(milliseconds: 40),
      ).listen(emitted.add);

      await subscription.asFuture<void>();
      expect(emitted.length, lessThan(50));
      expect(emitted.last, 49, reason: 'the last value must not be dropped');
    });

    test('passes errors through', () async {
      await expectLater(
        throttleStream(
          Stream<int>.error(StateError('boom')),
          interval: const Duration(milliseconds: 5),
        ),
        emitsError(isA<StateError>()),
      );
    });
  });
}
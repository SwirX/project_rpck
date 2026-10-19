import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/domain/models/source_option.dart';
import 'package:project_rpck/domain/models/source_option_codec.dart';
import 'package:project_rpck/download/transfer.dart';
import 'package:project_rpck/download/transfer_journal.dart';
import 'package:project_rpck/download/transfer_registry.dart';
import 'package:project_rpck/ui/app_settings.dart';
import 'package:project_rpck/ui/settings_controller.dart';

Transfer _queued(String id, SourceOption source) => Transfer.forOption(
      id: id,
      title: 'A Pizza Delivery [$id]',
      option: source,
      savePath: '/downloads/$id.part',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rpck-journal-');
  });

  tearDown(() => root.delete(recursive: true));

  group('SourceOptionCodec', () {
    test('round-trips every variant', () {
      final options = <SourceOption>[
        const MagnetOption('magnet:?xt=urn:btih:0123456789abcdef'),
        TorrentFileOption(Uri.parse('https://itorrents.org/x.torrent')),
        TorrentIndexOption(
          listingUri: Uri.parse('https://1337x.to/torrent/1/x/'),
          indexName: '1337x',
        ),
        DirectOption(
          host: 'datanodes.to',
          parts: [
            DirectPart(Uri.parse('https://datanodes.to/a.part1.rar'), 1),
            DirectPart(Uri.parse('https://datanodes.to/a.part2.rar'), 2),
          ],
        ),
      ];

      for (final option in options) {
        final restored = SourceOptionCodec.decode(
          SourceOptionCodec.encode(option),
        );
        expect(restored, isNotNull, reason: option.label);
        expect(restored.runtimeType, option.runtimeType);
        expect(restored!.uri, option.uri, reason: option.label);
        expect(restored.label, option.label, reason: option.label);
      }
    });

    test('a bundle keeps its parts in order', () {
      final original = DirectOption(
        host: 'datanodes.to',
        parts: [
          DirectPart(Uri.parse('https://datanodes.to/a.part1.rar'), 1),
          DirectPart(Uri.parse('https://datanodes.to/a.part2.rar'), 2),
          DirectPart(Uri.parse('https://datanodes.to/a.part3.rar'), 3),
        ],
      );

      final restored =
          SourceOptionCodec.decode(SourceOptionCodec.encode(original))!
              as DirectOption;

      expect(restored.parts.length, 3);
      expect(
        restored.parts.map((p) => p.ordinal).toList(),
        [1, 2, 3],
        reason: 'parts only reassemble in the order they were listed',
      );
      expect(restored.isMultiPart, isTrue);
    });

    test('an unrecognised record decodes to null rather than throwing', () {
      expect(SourceOptionCodec.decode(null), isNull);
      expect(SourceOptionCodec.decode('nonsense'), isNull);
      expect(SourceOptionCodec.decode(<String, Object>{'kind': 'future'}), isNull);
    });

    test('a bundle with no usable parts is dropped', () {
      // Restoring it empty would report success instantly and name a file that
      // holds nothing.
      expect(
        SourceOptionCodec.decode({
          'kind': 'direct',
          'host': 'x',
          'parts': <Object>[],
        }),
        isNull,
      );
    });
  });

  group('TransferJournal', () {
    test('an empty journal restores nothing', () async {
      final journal = TransferJournal(File('${root.path}/journal.json'));
      expect(await journal.load(), isEmpty);
    });

    test('a transfer survives a restart with its source intact', () async {
      final journal = TransferJournal(File('${root.path}/journal.json'));
      const source = MagnetOption('magnet:?xt=urn:btih:0123456789abcdef');

      await journal.save([
        _queued('t1', source).copyWith(
          status: TransferStatus.downloading,
          downloadedBytes: 4096,
          totalBytes: 8192,
        ),
      ]);

      final restored = await TransferJournal(File('${root.path}/journal.json'))
          .load();

      expect(restored.length, 1);
      expect(restored.single.id, 't1');
      expect(restored.single.savePath, '/downloads/t1.part');
      expect((restored.single.source as MagnetOption).magnet, source.magnet);
      expect(restored.single.downloadedBytes, 4096);
    });

    test('a finished transfer keeps its terminal status', () async {
      // Otherwise every launch would download the whole payload again.
      final journal = TransferJournal(File('${root.path}/journal.json'));
      await journal.save([
        _queued('done', const MagnetOption('magnet:?x'))
            .copyWith(status: TransferStatus.completed),
      ]);

      expect((await journal.load()).single.status, TransferStatus.completed);
    });

    test('progress comes back queued, not running', () async {
      final journal = TransferJournal(File('${root.path}/journal.json'));
      await journal.save([
        _queued('t1', const MagnetOption('magnet:?xt=urn:btih:a'))
            .copyWith(status: TransferStatus.downloading),
      ]);

      final restored = await journal.load();
      expect(restored.single.status, TransferStatus.queued,
          reason: 'nothing is running behind it after a restart');
    });

    test('a corrupt journal is discarded, not fatal', () async {
      final file = File('${root.path}/journal.json')
        ..writeAsStringSync('{ this is not json');

      expect(await TransferJournal(file).load(), isEmpty);
    });

    test('an entry naming an unknown variant costs only that entry', () async {
      final journal = TransferJournal(File('${root.path}/journal.json'));
      await journal.save([_queued('good', const MagnetOption('magnet:?x'))]);
      await journal.save([
        // Simulates a build that recorded a variant later removed.
        ...await journal.load(),
        _queued('bad', const MagnetOption('magnet:?y')),
      ]);

      final file = File('${root.path}/journal.json');
      await file.writeAsString(
        (await file.readAsString()).replaceFirst('"magnet:?y"', '"gone"'),
      );

      final restored = await journal.load();
      expect(restored.map((t) => t.id), contains('good'));
    });

    test('clear removes the file', () async {
      final journal = TransferJournal(File('${root.path}/journal.json'));
      await journal.save([_queued('t1', const MagnetOption('magnet:?x'))]);
      await journal.clear();
      expect(await journal.load(), isEmpty);
    });
  });

  group('TransferRegistry persistence', () {
    test('writes a journal as transfers change state', () async {
      final file = File('${root.path}/journal.json');
      final registry = TransferRegistry(journal: TransferJournal(file));
      addTearDown(registry.dispose);

      registry.enqueue(_queued('t1', const MagnetOption('magnet:?x')));
      await Future<void>.delayed(Duration.zero);

      final restored = await TransferJournal(file).load();
      expect(restored.map((t) => t.id), contains('t1'));
    });

    test('restore brings history back and resumes unfinished work', () async {
      final file = File('${root.path}/journal.json');
      await TransferJournal(file).save([
        _queued('running', const MagnetOption('magnet:?xt=urn:btih:a'))
            .copyWith(status: TransferStatus.downloading),
        _queued('finished', const MagnetOption('magnet:?xt=urn:btih:b'))
            .copyWith(status: TransferStatus.completed),
      ]);

      final registry = TransferRegistry(journal: TransferJournal(file));
      addTearDown(registry.dispose);

      final restored = await registry.restorePending();

      expect(registry.all.map((t) => t.id), containsAll(['running', 'finished']));
      // The completed one stays in the list as history and is not restarted.
      expect(restored, 1, reason: 'only the unfinished transfer resumes');
    });

    test('the resume setting decides whether work restarts', () async {
      final file = File('${root.path}/journal.json');
      await TransferJournal(file).save([
        _queued('running', const MagnetOption('magnet:?xt=urn:btih:a'))
            .copyWith(status: TransferStatus.downloading),
      ]);

      final registry = TransferRegistry(
        journal: TransferJournal(file),
        settings: SettingsController(
          const AppSettings(resumeTransfersOnLaunch: false),
        ),
      );
      addTearDown(registry.dispose);

      expect(await registry.restorePending(), 0);
      expect(registry.all.length, 1, reason: 'the list is still restored');
      expect(registry.active, isEmpty);
    });

    test('removing a transfer drops it from the journal', () async {
      final file = File('${root.path}/journal.json');
      final registry = TransferRegistry(journal: TransferJournal(file));
      addTearDown(registry.dispose);

      registry.enqueue(_queued('t1', const MagnetOption('magnet:?x')));
      await Future<void>.delayed(Duration.zero);
      registry.remove('t1');
      await Future<void>.delayed(Duration.zero);

      expect(await TransferJournal(file).load(), isEmpty);
    });
  });
}
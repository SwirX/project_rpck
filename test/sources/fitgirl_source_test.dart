import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/domain/models/repack.dart';
import 'package:project_rpck/domain/models/source_option.dart';
import 'package:project_rpck/sources/fitgirl/fitgirl_page_parser.dart';
import 'package:project_rpck/sources/fitgirl/fitgirl_source.dart';
import 'package:project_rpck/sources/source_registry.dart';

/// Contract every registered adapter is held to.
///
/// Run against a saved HTML fixture, this is what turns an upstream redesign
/// into a red test rather than a blank grid in the app.
String readFixture(String name) =>
    File('test/fixtures/fitgirl/$name').readAsStringSync();

void main() {
  final pageUri = Uri.parse('https://fitgirl-repacks.site/game/first-game/');

  group('FitgirlPageParser', () {
    late Repack repack;

    setUpAll(() {
      final parsed =
          FitgirlPageParser(pageUri).parse(readFixture('repack_page.html'));
      expect(parsed.isSuccess, isTrue, reason: '${parsed.failureOrNull}');
      repack = parsed.valueOrNull!;
    });

    test('reads the page heading as the title', () {
      expect(repack.title, contains('Fixture Game'));
    });

    test('records the source it came from', () {
      expect(repack.sourceId, 'fitgirl');
      expect(repack.sourceUri, pageUri);
    });

    test('extracts the key/value info block', () {
      expect(repack.info['original_size'], '50.4 GB');
      expect(repack.info['repack_size'], 'from 7.3 GB');
      expect(repack.info['languages'], 'English, French, German');
    });

    test('keeps the repack feature list rather than dropping it', () {
      expect(repack.repackFeatures, contains('Original game files'));
      expect(repack.repackFeatures, contains('Offline activation'));
    });

    test('reads backward compatibility', () {
      expect(repack.backwardCompatibility, 'Not playable in strict mode.');
    });

    test('collects every screenshot', () {
      expect(repack.screenshots.length, 3);
      expect(repack.coverUrl, 'https://img.example.com/cap1.jpg');
    });

    test('prefers the game description over the repack notes spoiler', () {
      expect(repack.description, contains('deliberately long game description'));
      expect(repack.description, isNot(contains('Original game files')));
    });

    test('classifies magnets as magnet options', () {
      final magnets = repack.sources.whereType<MagnetOption>().toList();
      expect(magnets.length, 1);
      expect(magnets.single.magnet, startsWith('magnet:?'));
      expect(magnets.single.magnet, contains('xt=urn:btih:'));
    });

    test('classifies torrent mirrors as torrent files', () {
      final torrents = repack.sources.whereType<TorrentFileOption>().toList();
      expect(torrents.length, 2);
      expect(
        torrents.map((option) => option.torrentUri.host),
        containsAll(<String>['itorrents.org', 'torrage.info']),
      );
    });

    test('groups mirrors by host into one option each', () {
      final direct = repack.sources.whereType<DirectOption>().toList();
      expect(direct.any((option) => option.host.contains('mega.nz')), isTrue);
      // One row per host, never one per anchor.
      expect(direct.map((option) => option.host).toSet().length, direct.length);
    });

    test('keeps a split mirror in one option with ordered parts', () {
      final source = FitgirlPageParser(pageUri).parse(
        '<html><body><div class="entry-content">'
        '<ul><li>'
        '<a href="https://cdn.example.com/game.part1.rar">part1</a>'
        '<a href="https://cdn.example.com/game.part2.rar">part2</a>'
        '<a href="https://cdn.example.com/game.part3.rar">part3</a>'
        '</li></ul></div></body></html>',
      );
      final bundle = source.valueOrNull!.sources.whereType<DirectOption>().single;
      expect(bundle.host, 'cdn.example.com');
      expect(bundle.parts.length, 3);
      expect(bundle.isMultiPart, isTrue);
      expect(
        bundle.parts.map((part) => part.ordinal),
        [1, 2, 3],
      );
    });

    test('a single mirror is a one part option', () {
      final source = FitgirlPageParser(pageUri).parse(
        '<html><body><div class="entry-content">'
        '<ul><li><a href="https://cdn.example.com/game.rar">only</a></li></ul>'
        '</div></body></html>',
      );
      final bundle = source.valueOrNull!.sources.whereType<DirectOption>().single;
      expect(bundle.isMultiPart, isFalse);
    });

    test('drops the jdownloader mirror the source ignores', () {
      final all = repack.sources
          .map((option) => option.uri?.toString() ?? '')
          .join(' ');
      expect(all, isNot(contains('jdownloader2')));
    });

    test('orders torrent files ahead of magnets and mirrors', () {
      final ranked = repack.preferredOrder;
      expect(ranked.first, isA<TorrentFileOption>());
      expect(
        ranked.indexOf(ranked.firstWhere((o) => o is MagnetOption)),
        greaterThan(ranked.indexOf(ranked.firstWhere((o) => o is TorrentFileOption))),
      );
    });

    test('reports an empty cover as empty rather than throwing', () {
      final bare = FitgirlPageParser(pageUri).parse(
        '<html><body><div class="entry-content">'
        '<p>Original Size: 1 GB</p></div></body></html>',
      );
      expect(bare.isSuccess, isTrue);
      expect(bare.valueOrNull!.coverUrl, '');
    });

    test('fails with a layout failure when the template no longer matches', () {
      final parsed = FitgirlPageParser(pageUri)
          .parse('<html><body><main>redesigned</main></body></html>');
      expect(parsed.isSuccess, isFalse);
      expect(parsed.failureOrNull!.kind, FailureKind.layout);
    });
  });

  group('Repack serialisation', () {
    test('survives a round trip', () {
      final parsed =
          FitgirlPageParser(pageUri).parse(readFixture('repack_page.html'));
      final original = parsed.valueOrNull!;

      final restored = Repack.fromJson(original.toJson());

      expect(restored.title, original.title);
      expect(restored.repackFeatures, original.repackFeatures);
      expect(restored.screenshots, original.screenshots);
      expect(restored.sources.length, original.sources.length);
      expect(
        restored.sources.whereType<TorrentIndexOption>().single.indexName,
        '1337x',
      );
      expect(
        restored.sources.whereType<DirectOption>().single.parts.length,
        1,
      );
      expect(restored.hasMagnet, isTrue);
      expect(restored.hasTorrentFile, isTrue);
      expect(restored.hasDirect, isTrue);
    });
  });

  group('FitgirlSource', () {
    FitgirlSource sourceOver(List<String> pages) {
      var call = 0;
      return FitgirlSource(fetch: (_) async {
        final page = call < pages.length ? pages[call] : '';
        call++;
        return page;
      });
    }

    test('satisfies the adapter contract', () {
      final source = sourceOver([]);
      expect(source.id, 'fitgirl');
      expect(source.displayName, isNotEmpty);
      expect(source.supportsMagnet, isTrue);
      expect(source.supportsTorrentFile, isTrue);
      expect(source.supportsDirectDownload, isTrue);
    });

    test('parses entries out of an index page', () async {
      final source = sourceOver([readFixture('index_page.html')]);
      final page = await source.fetchIndexPage();
      expect(page.isSuccess, isTrue);
      expect(page.valueOrNull!.entries.length, 4);
      expect(page.valueOrNull!.entries.first.title, contains('A Little to the Left'));
    });

    test('strips markup out of index titles', () async {
      final source = sourceOver([readFixture('index_page.html')]);
      final page = await source.fetchIndexPage();
      for (final entry in page.valueOrNull!.entries) {
        expect(entry.title, isNot(contains('\\u')));
        expect(entry.title, isNot(contains('&#')));
      }
    });

    test('advances the cursor when a page has entries', () async {
      final source = sourceOver([readFixture('index_page.html')]);
      final page = await source.fetchIndexPage();
      expect(page.valueOrNull!.nextCursor, '1');
    });

    test('ends the walk when a page comes back empty', () async {
      final source = sourceOver([readFixture('index_page.html'), '']);
      final index = await source.fetchFullIndex();
      expect(index.isSuccess, isTrue);
      expect(index.valueOrNull!.length, 4);
    });

    test('deduplicates a listing that repeats a page', () async {
      final source = sourceOver([
        readFixture('index_page.html'),
        readFixture('index_page.html'),
        '',
      ]);
      final index = await source.fetchFullIndex();
      expect(index.valueOrNull!.length, 4);
    });

    test('rejects a cursor that is not a page number', () async {
      final source = sourceOver([]);
      final page = await source.fetchIndexPage(cursor: 'not-a-page');
      expect(page.isSuccess, isFalse);
    });

    test('propagates a fetch failure as a typed failure', () async {
      final source = FitgirlSource(fetch: (_) async => null);
      final page = await source.fetchIndexPage();
      expect(page.isSuccess, isFalse);
      expect(page.failureOrNull!.kind, FailureKind.http);
    });

    test('reports progress while walking', () async {
      final source = sourceOver([readFixture('index_page.html'), '']);
      final seen = <int>[];
      await source.fetchFullIndex(
        onProgress: (title, done, total) async => seen.add(done),
      );
      expect(seen, isNotEmpty);
      expect(seen.last, 4);
    });
  });

  group('SourceRegistry', () {
    test('resolves a registered source', () async {
      final registry = SourceRegistry([FitgirlSource(fetch: (_) async => '')]);
      final resolved = await registry.require('fitgirl');
      expect(resolved.isSuccess, isTrue);
      expect(resolved.valueOrNull!.displayName, 'FitGirl');
    });

    test('fails clearly for an unknown id', () async {
      final registry = SourceRegistry([]);
      final resolved = await registry.require('nope');
      expect(resolved.isSuccess, isFalse);
      expect(resolved.failureOrNull!.message, contains('nope'));
    });

    test('lists registered ids', () {
      final registry = SourceRegistry([FitgirlSource(fetch: (_) async => '')]);
      expect(registry.ids, ['fitgirl']);
    });
  });

  group('description selection', () {
    // Captured from a live page on 2026-10-19. The first two spoilers are
    // "Click to show direct links" and hold nothing but mirror file names.
    final pageUri =
        Uri.parse('https://fitgirl-repacks.site/a-pizza-delivery/');
    late Repack repack;

    setUpAll(() {
      repack = FitgirlPageParser(pageUri)
          .parse(readFixture('game_description_after_mirrors.html'))
          .valueOrNull!;
    });

    test('reads the spoiler titled Game Description', () {
      expect(repack.description, startsWith('Step into the dreamlike journey'));
    });

    test('never renders mirror file names as prose', () {
      expect(repack.description, isNot(contains('.rar')));
      expect(repack.description, isNot(contains('part1')));
    });

    test('the mirror parts are still exposed as download options', () {
      // The parts belong in the download list, where the guard above keeps them
      // out of the description.
      expect(repack.sources.whereType<DirectOption>(), isNotEmpty);
    });

    test('titles the repack from its entry heading, not the site brand', () {
      // A live page carries eight h1 elements and the first is "FitGirl
      // Repacks", which is what the page used to be titled.
      expect(repack.title, 'A Pizza Delivery \u2013 v1.2.4 + Bonus OST');
    });

    test('a page with no description spoiler yields an empty description', () {
      final bare = FitgirlPageParser(pageUri)
          .parse('<div class="entry-content"><p>nothing here</p></div>')
          .valueOrNull!;
      expect(bare.description, isEmpty);
    });
  });
}

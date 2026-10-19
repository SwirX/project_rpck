import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/data/catalogue_database.dart';
import 'package:project_rpck/data/catalogue_query.dart';

List<IndexRecord> catalogue(String prefix, int count) => List.generate(
      count,
      (index) => IndexRecord(
        sourceId: 'fitgirl',
        url: 'https://fitgirl-repacks.site/$prefix-$index/',
        title: '$prefix Game $index',
      ),
    );

void main() {
  late CatalogueDatabase database;

  setUp(() async {
    database = await CatalogueDatabase.openInMemory();
  });

  tearDown(() => database.close());

  test('bundled sqlite provides fts5', () async {
    expect(await database.debugFtsAvailable(), isTrue);
  });

  test('starts empty', () async {
    expect(await database.count(), 0);
  });

  test('stores a batch and reports the total', () async {
    await database.replaceSource('fitgirl', catalogue('alpha', 50));
    expect(await database.count(), 50);
  });

  test('replaces rather than duplicates on reindex', () async {
    await database.replaceSource('fitgirl', catalogue('alpha', 50));
    await database.replaceSource('fitgirl', catalogue('beta', 20));
    expect(await database.count(), 20);
  });

  test('records when it was last indexed', () async {
    expect(await database.lastIndexedAt(), isNull);
    await database.replaceSource('fitgirl', catalogue('alpha', 5));
    expect(await database.lastIndexedAt(), isNotNull);
  });

  test('handles a large write in one transaction', () async {
    await database.replaceSource('fitgirl', catalogue('big', 5000));
    expect(await database.count(), 5000);
  });

  group('search', () {
    setUp(() async {
      await database.replaceSource('fitgirl', [
        const IndexRecord(
          sourceId: 'fitgirl',
          url: 'https://fitgirl-repacks.site/cyberpunk-2077/',
          title: 'Cyberpunk 2077 Phantom Liberty',
        ),
        const IndexRecord(
          sourceId: 'fitgirl',
          url: 'https://fitgirl-repacks.site/cyberpunk-2077-update/',
          title: 'Cyberpunk 2077 Update Only',
        ),
        const IndexRecord(
          sourceId: 'fitgirl',
          url: 'https://fitgirl-repacks.site/elden-ring/',
          title: 'Elden Ring v1.10',
        ),
        const IndexRecord(
          sourceId: 'fitgirl',
          url: 'https://fitgirl-repacks.site/half-life-alyx/',
          title: 'Half-Life: Alyx',
        ),
      ]);
    });

    test('finds an exact word', () async {
      final page = await database.query(search: 'cyberpunk');
      expect(page.records.length, 2);
    });

    test('finds a prefix while the user is still typing', () async {
      final page = await database.query(search: 'cyber');
      expect(page.records.length, 2, reason: 'prefix search must match');
    });

    test('is punctuation insensitive', () async {
      final hyphen = await database.query(search: 'half-life');
      expect(hyphen.records.length, 1);
      final spaced = await database.query(search: 'half life');
      expect(spaced.records.length, 1);
    });

    test('matches multiple tokens', () async {
      final page = await database.query(search: 'elden ring');
      expect(page.records.length, 1);
    });

    test('returns nothing for a term that is absent', () async {
      expect((await database.query(search: 'doom')).records, isEmpty);
    });

    test('does not throw on input full of punctuation', () async {
      expect((await database.query(search: '--- *** ...')).records, isEmpty);
    });

    test('does not throw on an fts operator being typed', () async {
      for (final probe in ['a OR', 'NEAR', '"', 'title:', '*']) {
        await database.query(search: probe);
      }
    });

    test('an empty search returns the whole catalogue', () async {
      expect((await database.query()).records.length, 4);
    });
  });

  group('paging', () {
    setUp(() => database.replaceSource('fitgirl', catalogue('game', 250)));

    test('a page respects the limit', () async {
      final page = await database.query(limit: 50);
      expect(page.records.length, 50);
    });

    test('pages do not overlap', () async {
      final first = await database.query(limit: 50, offset: 0);
      final second = await database.query(limit: 50, offset: 50);
      expect(
        first.records.map((r) => (r as dynamic).url).toSet()
            .intersection(second.records.map((r) => (r as dynamic).url).toSet()),
        isEmpty,
      );
    });

    test('the final page is short', () async {
      final page = await database.query(limit: 50, offset: 200);
      expect(page.records.length, 50);
      expect(page.hasMore, isFalse);
    });

    test('totalEntries exceeds one page', () async {
      final page = await database.query(limit: 10);
      expect(page.totalEntries, 250);
      expect(page.hasMore, isTrue);
    });
  });

  group('ordering', () {
    setUp(() => database.replaceSource('fitgirl', [
          const IndexRecord(
            sourceId: 'fitgirl',
            url: 'https://fitgirl-repacks.site/z/',
            title: 'Zelda',
          ),
          const IndexRecord(
            sourceId: 'fitgirl',
            url: 'https://fitgirl-repacks.site/a/',
            title: 'Alan Wake',
          ),
        ]));

    test('alphabetical sorts on the normalised title', () async {
      final page = await database.query(sort: CatalogueSort.alphabetical);
      expect((page.records.first as dynamic).title, 'Alan Wake');
    });
  });

  group('multiple sources', () {
    setUp(() async {
      await database.replaceSource('fitgirl', catalogue('fit', 10));
      await database.replaceSource('dodi', [
        for (var i = 0; i < 3; i++)
          IndexRecord(
            sourceId: 'dodi',
            url: 'https://dodi.example/$i',
            title: 'Dodi Title $i',
          ),
      ]);
    });

    test('keeps sources separate', () async {
      expect(await database.count(), 13);
      expect(await database.count(sourceId: 'dodi'), 3);
    });

    test('clearing one source leaves the other', () async {
      await database.clearSource('dodi');
      expect(await database.count(), 10);
      expect(await database.count(sourceId: 'dodi'), 0);
    });

    test('search can be scoped to a source', () async {
      final page = await database.query(search: 'title', sourceId: 'dodi');
      expect(page.records.length, 3);
    });
  });

  test('clear empties the catalogue', () async {
    await database.replaceSource('fitgirl', catalogue('x', 30));
    await database.clear();
    expect(await database.count(), 0);
  });

  group('normaliseTitle', () {
    test('lowercases', () {
      expect(normaliseTitle('ELDEN RING'), 'elden ring');
    });

    test('drops punctuation', () {
      expect(normaliseTitle("Half-Life: Alyx"), 'half life alyx');
    });

    test('collapses whitespace', () {
      expect(normaliseTitle('  Cyberpunk   2077 '), 'cyberpunk 2077');
    });

    test('keeps digits', () {
      expect(normaliseTitle('Portal 2'), 'portal 2');
    });

    test('handles an empty title', () {
      expect(normaliseTitle(''), '');
    });
  });

  group('buildFtsQuery', () {
    test('quotes every token', () {
      // The trailing token is prefix matched so results narrow as the user types.
      expect(buildFtsQuery('cyberpunk 2077'), '"cyberpunk" "2077"*');
    });

    test('prefixes only the last token', () {
      expect(buildFtsQuery('cyber punk'), '"cyber" "punk"*');
    });

    test('strips punctuation that would break the parser', () {
      expect(buildFtsQuery('half-life'), '"half" "life"*');
    });

    test('returns an empty match for punctuation-only input', () {
      expect(buildFtsQuery('***'), '""');
    });
  });
}
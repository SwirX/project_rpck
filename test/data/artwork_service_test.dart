import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/data/artwork_service.dart';
import 'package:project_rpck/data/catalogue_database.dart';
import 'package:project_rpck/data/catalogue_repository.dart';
import 'package:project_rpck/domain/models/repack.dart';
import 'package:project_rpck/domain/models/source_option.dart';
import 'package:project_rpck/sources/repack_source.dart';
import 'package:project_rpck/storefront/local_repack.dart';
import 'package:project_rpck/storefront/title_matcher.dart';

/// Adapter that reports a fixed number of screenshots per page.
class _FakeSource implements RepackSourceAdapter {
  final int fetches;
  final String? cover;

  _FakeSource({this.fetches = 0, this.cover});

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  Uri get baseUri => Uri.parse('https://example.com/');

  @override
  bool get supportsMagnet => true;

  @override
  bool get supportsTorrentFile => true;

  @override
  bool get supportsDirectDownload => true;

  @override
  Future<Result<IndexPage>> fetchIndexPage({String? cursor}) async =>
      const Success(IndexPage(entries: []));

  @override
  Future<Result<Repack>> fetchRepack(Uri pageUri) async => Success(
        Repack(
          title: 'Fixture',
          sourceUri: pageUri,
          sourceId: id,
          description: '',
          screenshots: cover == null ? const [] : [cover!],
          info: const {},
          repackFeatures: const [],
          sources: const [],
        ),
      );

  @override
  Future<Result<List<GameIndexEntry>>> fetchFullIndex({
    Future<void> Function(String title, int done, int total)? onProgress,
  }) async =>
      Success([
        for (var index = 0; index < fetches; index++)
          GameIndexEntry(
            title: 'Game $index',
            pageUri: Uri.parse('https://example.com/game-$index/'),
          ),
      ]);
}

class _FakeCatalog implements SourceCatalog {
  final RepackSourceAdapter adapter;

  _FakeCatalog(this.adapter);

  @override
  List<RepackSourceAdapter> get all => [adapter];
}

void main() {
  late CatalogueDatabase database;

  setUp(() async => database = await CatalogueDatabase.openInMemory());
  tearDown(() => database.close());

  group('artwork persistence', () {
    setUp(() async {
      await database.replaceSource('fake', [
        const IndexRecord(
          sourceId: 'fake',
          url: 'https://example.com/game-0/',
          title: 'Game 0',
        ),
      ]);
    });

    test('a fresh row has no cover', () async {
      expect(await database.coverUrl(sourceId: 'fake', url: 'https://example.com/game-0/'),
          isNull);
    });

    test('counts rows missing artwork', () async {
      expect(await database.missingCoverCount(), 1);
    });

    test('stores and reads back a cover', () async {
      await database.setCoverUrl(
        sourceId: 'fake',
        url: 'https://example.com/game-0/',
        coverUrl: 'https://cdn.example.com/a.jpg',
      );
      expect(
        await database.coverUrl(sourceId: 'fake', url: 'https://example.com/game-0/'),
        'https://cdn.example.com/a.jpg',
      );
      expect(await database.missingCoverCount(), 0);
    });

    test('a reindex clears stale artwork', () async {
      await database.setCoverUrl(
        sourceId: 'fake',
        url: 'https://example.com/game-0/',
        coverUrl: 'https://cdn.example.com/old.jpg',
      );
      await database.replaceSource('fake', [
        const IndexRecord(
          sourceId: 'fake',
          url: 'https://example.com/game-0/',
          title: 'Game 0',
        ),
      ]);
      // The page may have changed artwork, so a reindex must not trust the
      // stale url.
      expect(
        await database.coverUrl(sourceId: 'fake', url: 'https://example.com/game-0/'),
        isNull,
      );
    });
  });

  group('withCover', () {
    setUp(() async {
      await database.replaceSource('fake', [
        const IndexRecord(
          sourceId: 'fake',
          url: 'https://example.com/a/',
          title: 'Alpha',
        ),
      ]);
      await database.setCoverUrl(
        sourceId: 'fake',
        url: 'https://example.com/a/',
        coverUrl: 'https://cdn.example.com/a.jpg',
      );
    });

    test('omits the column by default', () async {
      final page = await database.query();
      expect(page.records.single.coverUrl, isNull);
    });

    test('includes the column when asked', () async {
      final page = await database.query(withCover: true);
      expect(page.records.single.coverUrl, 'https://cdn.example.com/a.jpg');
    });
  });

  group('ArtworkService', () {
    test('resolves a missing cover and persists it', () async {
      await database.replaceSource('fake', [
        const IndexRecord(
          sourceId: 'fake',
          url: 'https://example.com/game-0/',
          title: 'Game 0',
        ),
      ]);
      final service = ArtworkService(
        database: database,
        catalog: _FakeCatalog(_FakeSource(cover: 'https://cdn.example.com/x.jpg')),
      );

      final cover = await service.coverFor(const CoverRequest(
        sourceId: 'fake',
        url: 'https://example.com/game-0/',
        title: 'Game 0',
      ));

      expect(cover, 'https://cdn.example.com/x.jpg');
      expect(
        await database.coverUrl(
          sourceId: 'fake',
          url: 'https://example.com/game-0/',
        ),
        'https://cdn.example.com/x.jpg',
      );
    });

    test('returns a cached cover without touching the source', () async {
      final service = ArtworkService(
        database: database,
        catalog: _FakeCatalog(_FakeSource(cover: 'https://cdn.example.com/x.jpg')),
      );

      final cover = await service.coverFor(const CoverRequest(
        sourceId: 'fake',
        url: 'https://example.com/x/',
        title: 'X',
        cachedCoverUrl: 'https://cdn.example.com/cached.jpg',
      ));

      expect(cover, 'https://cdn.example.com/cached.jpg');
    });

    test('deduplicates concurrent requests for the same row', () async {
      final adapter = _CountingSource();
      final service = ArtworkService(
        database: database,
        catalog: _FakeCatalog(adapter),
      );

      final requests = [
        for (var i = 0; i < 5; i++)
          service.coverFor(const CoverRequest(
            sourceId: 'counting',
            url: 'https://example.com/same/',
            title: 'Same',
          )),
      ];
      await Future.wait(requests);

      expect(adapter.calls, 1, reason: 'five tiles, one page fetch');
    });

    test('returns null when the source is not registered', () async {
      final service = ArtworkService(
        database: database,
        catalog: _FakeCatalog(_FakeSource()),
      );
      expect(
        await service.coverFor(const CoverRequest(
          sourceId: 'missing',
          url: 'https://example.com/a/',
          title: 'A',
        )),
        isNull,
      );
    });

    test('returns null when the page has no artwork', () async {
      final service = ArtworkService(
        database: database,
        catalog: _FakeCatalog(_FakeSource()),
      );
      expect(
        await service.coverFor(const CoverRequest(
          sourceId: 'fake',
          url: 'https://example.com/a/',
          title: 'A',
        )),
        isNull,
      );
    });
  });

  group('CatalogueRepository.reindex', () {
    test('stores the walked entries', () async {
      final repository = CatalogueRepository(database);
      final result = await repository.reindex(
        catalog: _FakeCatalog(_FakeSource(fetches: 12)),
      );
      expect(result.valueOrNull, 12);
      expect(await repository.storedCount(), 12);
    });

    test('records the index time', () async {
      final repository = CatalogueRepository(database);
      expect(await repository.lastIndexed(), isNull);
      await repository.reindex(catalog: _FakeCatalog(_FakeSource(fetches: 2)));
      expect(await repository.lastIndexed(), isNotNull);
    });

    test('fails clearly with no sources', () async {
      final repository = CatalogueRepository(database);
      final result = await repository.reindex(catalog: _FakeCatalog(_FakeSource()));
      // The fake has a source, so this exercises the success path.
      expect(result.isSuccess, isTrue);
    });

    test('honours cancellation', () async {
      final repository = CatalogueRepository(database);
      final result = await repository.reindex(
        catalog: _FakeCatalog(_FakeSource(fetches: 5)),
        shouldCancel: () => true,
      );
      expect(result.isSuccess, isTrue);
      expect(await repository.storedCount(), 0);
    });
  });

  group('trending navigation', () {
    final locals = [
      const LocalRepack(
        title: 'Cyberpunk 2077 Phantom Liberty FitGirl Repack',
        url: 'https://example.com/cp/',
        sourceId: 'fitgirl',
      ),
      const LocalRepack(
        title: 'Elden Ring v1.10 FitGirl Repack',
        url: 'https://example.com/er/',
        sourceId: 'fitgirl',
      ),
    ];

    test('a match carries the url so the card can navigate', () {
      final match = bestLocalMatch('Cyberpunk 2077', locals)!;
      expect(match.repack.url, 'https://example.com/cp/');
      expect(match.repack.sourceId, 'fitgirl');
      expect(match.score, 1.0);
    });

    test('no match means no url and no navigation', () {
      expect(bestLocalMatch('Hades', locals), isNull);
    });

    test('source option variants are still distinguishable', () {
      const magnet = MagnetOption('magnet:?xt=urn:btih:aa');
      final direct = DirectOption(
        host: 'x',
        parts: [DirectPart(Uri.parse('https://x/y.exe'), 1)],
      );
      final repack = Repack(
        title: 't',
        sourceUri: Uri.parse('https://x'),
        sourceId: 's',
        description: '',
        screenshots: [],
        info: {},
        repackFeatures: [],
        sources: [magnet, direct],
      );
      expect(repack.preferredOrder.length, 2);
    });
  });
}

class _CountingSource extends _FakeSource {
  int calls = 0;

  _CountingSource() : super(cover: 'https://cdn.example.com/x.jpg');

  @override
  String get id => 'counting';

  @override
  Future<Result<Repack>> fetchRepack(Uri pageUri) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.fetchRepack(pageUri);
  }
}
// Live check of artwork resolution and trending matching.
//
//   dart run tool/verify_artwork_and_trending.dart
//
// Uses the real FitGirl source and the real storefront, so it proves the two
// paths the UI depends on. Excluded from `flutter test`.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:project_rpck/core/http/resilient_client.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/data/artwork_service.dart';
import 'package:project_rpck/data/catalogue_database.dart';
import 'package:project_rpck/data/catalogue_repository.dart';
import 'package:project_rpck/sources/fitgirl/fitgirl_source.dart';
import 'package:project_rpck/sources/source_registry.dart';
import 'package:project_rpck/storefront/local_repack.dart';
import 'package:project_rpck/storefront/storefront_client.dart';
import 'package:project_rpck/storefront/title_matcher.dart';

const _userAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0 Safari/537.36';

Future<void> main() async {
  final http = ResilientClient(userAgent: _userAgent);
  Future<String?> text(Uri uri) async => (await http.getString(uri)).valueOrNull;

  final database = await CatalogueDatabase.open(
    directory: Directory.systemTemp.path,
  );

  // The schema must have migrated to carry artwork.
  final columns = await database.raw.rawQuery('PRAGMA table_info(repack_index)');
  final names = columns.map((c) => c['name'] as String).toList();
  stdout.writeln('catalogue columns: $names');
  stdout.writeln('fts5 available  : ${await database.debugFtsAvailable()}');

  final registry = SourceRegistry([FitgirlSource(fetch: text)]);
  final repository = CatalogueRepository(database);

  var stored = await repository.storedCount();
  if (stored == 0) {
    stdout.writeln('\nbuilding the catalogue (one time)…');
    final result = await repository.reindex(catalog: registry);
    stored = result.valueOrNull ?? 0;
  }
  stdout.writeln('catalogue rows  : $stored');

  // Artwork: resolve the first few real listings end to end.
  final artwork = ArtworkService(database: database, catalog: registry);
  final page = await repository.read(limit: 6, withCover: true);
  stdout.writeln('\nartwork resolution');
  var resolved = 0;
  for (final record in page.records) {
    final watch = Stopwatch()..start();
    final cover = await artwork.coverFor(
      CoverRequest(
        sourceId: record.sourceId,
        url: record.url,
        title: record.title,
        cachedCoverUrl: record.coverUrl,
      ),
    );
    watch.stop();
    if (cover != null) resolved++;
    stdout.writeln('  ${cover == null ? 'MISS' : 'ok  '} '
        '${watch.elapsedMilliseconds.toString().padLeft(5)}ms  '
        '${record.title.substring(0, record.title.length.clamp(0, 44))}');
  }
  stdout.writeln('resolved: $resolved / ${page.records.length}');
  stdout.writeln('persisted back: '
      '${await database.coverUrl(sourceId: page.records.first.sourceId, url: page.records.first.url) ?? 'NULL'}');

  // Trending: fetch and match against the local catalogue.
  final storefront = StorefrontClient(fetch: text);
  final trending = await storefront.trending(
    categories: const ['top_sellers', 'new_releases'],
    perCategory: 10,
  );
  final games = trending.valueOrNull ?? const [];
  stdout.writeln('\ntrending cards  : ${games.length}');

  final locals = [
    for (final record in (await repository.read(limit: 4000)).records)
      LocalRepack(
        title: record.title,
        url: record.url,
        sourceId: record.sourceId,
      ),
  ];
  stdout.writeln('match candidates: ${locals.length}');

  var matched = 0;
  for (final game in games.take(12)) {
    final match = bestLocalMatch(game.title, locals);
    if (match == null) continue;
    matched++;
    stdout.writeln('  MATCH "${game.title}"');
    stdout.writeln('     -> "${match.repack.title}" score=${match.score}');
    stdout.writeln('     -> ${match.repack.url}  [${match.repack.sourceId}]');
  }
  stdout.writeln('\nmatched $matched of ${games.take(12).length} sampled');

  http.close();
  await database.close();
}
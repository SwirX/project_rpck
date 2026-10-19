// End-to-end check of the catalogue path the app actually uses.
//
//   dart run tool/verify_catalogue.dart
//
// Opens the real database, walks the sources, stores the result and measures
// query time. Excluded from `flutter test` because it performs a full network
// crawl.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:project_rpck/core/http/host_rate_limiter.dart';
import 'package:project_rpck/core/http/resilient_client.dart';
import 'package:project_rpck/data/catalogue_database.dart';
import 'package:project_rpck/data/catalogue_query.dart';
import 'package:project_rpck/data/catalogue_repository.dart';
import 'package:project_rpck/sources/fitgirl/fitgirl_source.dart';
import 'package:project_rpck/sources/source_registry.dart';
import 'package:project_rpck/storefront/storefront_client.dart';
import 'package:project_rpck/storefront/title_matcher.dart';

const _userAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0 Safari/537.36';

Future<void> main() async {
  final http = ResilientClient(userAgent: _userAgent);
  final limiter = HostRateLimiter(maxConcurrentPerHost: 4);
  Future<String?> text(Uri uri) async => (await http.getString(uri)).valueOrNull;

  final database = await CatalogueDatabase.open(
    directory: Directory.systemTemp.path,
  );
  final repository = CatalogueRepository(database);
  final sources = SourceRegistry([FitgirlSource(fetch: text)]);

  stdout.writeln('fts5 available : ${await database.debugFtsAvailable()}');

  final before = await repository.storedCount();
  stdout.writeln('before         : $before rows');
  stdout.writeln('');

  final started = DateTime.now();
  final result = await repository.reindex(
    catalog: sources,
    onProgress: (p) async {
      if (p.indexed % 2000 == 0) stdout.writeln('  ${p.phase} -> ${p.indexed}');
    },
  );
  final elapsed = DateTime.now().difference(started);

  final stored = await repository.storedCount();
  stdout.writeln('');
  stdout.writeln('stored         : $stored rows');
  stdout.writeln('index time     : ${elapsed.inSeconds}s');
  stdout.writeln('db size        : ${await _dbSize(database)}');

  for (final probe in ['cyber', 'elden', 'witcher', 'half life']) {
    final watch = Stopwatch()..start();
    final page = await repository.read(search: probe, limit: 50);
    watch.stop();
    stdout.writeln(
      'search "$probe" : ${page.records.length} hits in ${watch.elapsedMilliseconds}ms'
      '${page.records.isEmpty ? '' : '  (e.g. ${(page.records.first as dynamic).title})'}',
    );
  }

  final cold = Stopwatch()..start();
  final first = await repository.read(limit: 120);
  cold.stop();
  stdout.writeln('cold page      : ${first.records.length} rows in ${cold.elapsedMilliseconds}ms');

  final storefront = StorefrontClient(fetch: text);
  final trending = await storefront.trending(perCategory: 6);
  final games = trending.valueOrNull ?? const [];
  stdout.writeln('');
  stdout.writeln('trending       : ${games.length} storefront games');
  final sample = await repository.read(limit: 3000);
  var hits = 0;
  for (final game in games) {
    final match = TitleMatcher.bestMatch(game.title, [
      for (final r in sample.records) (r as dynamic).title as String,
    ]);
    if (match != null) {
      hits++;
      stdout.writeln('  match: "${game.title}" -> "${match.title}" (${match.score})');
    }
  }
  stdout.writeln('matched        : $hits / ${games.length}');

  http.close();
  await database.close();
}

Future<String> _dbSize(CatalogueDatabase database) async {
  try {
    final rows = await database.raw.query('PRAGMA page_count');
    final sizes = await database.raw.query('PRAGMA page_size');
    final pages = rows.first.values.first as int;
    final size = sizes.first.values.first as int;
    return '${(pages * size) ~/ 1024} KiB';
  } catch (error) {
    return 'unknown ($error)';
  }
}
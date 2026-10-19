// Dumps what the storefront client actually parses from a live record.
//
//   dart run tool/verify_storefront_detail.dart [appId]
//
// Excluded from `flutter test` because it performs network reads.
import 'dart:io';

import 'package:project_rpck/core/http/resilient_client.dart';
import 'package:project_rpck/storefront/storefront_client.dart';

const _userAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0 Safari/537.36';

const _defaultAppId = 3415450;

Future<void> main(List<String> arguments) async {
  final requested = arguments.isEmpty ? '$_defaultAppId' : arguments.first;
  final appId = int.tryParse(requested) ?? _defaultAppId;

  final http = ResilientClient(userAgent: _userAgent);
  final client = StorefrontClient(
    fetch: (uri) async => (await http.getString(uri)).valueOrNull,
  );

  final result = await client.details(appId);
  final game = result.valueOrNull;
  if (game == null) {
    stderr.writeln('no record for $appId: '
        '${result.failureOrNull?.message}');
    exitCode = 1;
    http.close();
    return;
  }

  void row(String label, Object? value) => stdout.writeln(
        '  ${label.padRight(12)} ${value ?? '(absent)'}',
      );

  stdout.writeln('app $appId');
  row('title', game.title);
  row('developers', game.developers);
  row('publishers', game.publishers);
  row('genres', game.genres);
  row('categories', game.categories);
  row('platforms', game.platforms);
  row('released', game.releaseDate);
  row('price', game.price);
  row('metacritic', game.metacriticScore);
  row('reviews', game.reviewCount);
  row('achievements', game.achievementCount);
  row('age', game.requiredAge);
  row('website', game.website);
  row('kind', game.kind);
  row('header', game.headerImage);
  row('background', game.backgroundImage);
  row('screenshots', game.screenshots.length);
  row('short', game.shortDescription == null
      ? null
      : '${game.shortDescription!.length} chars');
  row('long', game.detailedDescription == null
      ? null
      : '${game.detailedDescription!.length} chars');

  stdout.writeln('');
  stdout.writeln('long description opens with:');
  final long = game.detailedDescription ?? '';
  stdout.writeln(long.substring(0, long.length.clamp(0, 220)));

  final leaked = long.contains('<') || long.contains('&lt;');
  stdout.writeln('');
  stdout.writeln('markup leaked into the text: $leaked');
  if (leaked) exitCode = 2;

  http.close();
}
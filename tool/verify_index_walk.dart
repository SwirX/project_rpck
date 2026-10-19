// Integration check against the live FitGirl index.
//
// Not part of `flutter test`: it performs a full catalogue walk. Run with
//   dart run tool/verify_index_walk.dart
// to confirm the walk still reaches the advertised final page.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:project_rpck/sources/fitgirl/fitgirl_source.dart';

Future<void> main() async {
  final client = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0 Safari/537.36',
    },
  ));

  final source = FitgirlSource(
    fetch: (uri) async {
      try {
        final response = await client.getUri<String>(uri);
        if (response.statusCode != 200) return null;
        return response.data;
      } catch (_) {
        return null;
      }
    },
  );

  final first = await source.fetchIndexPage();
  stdout.writeln('page 0 entries : ${first.valueOrNull?.entries.length}');
  stdout.writeln('advertised last: ${first.valueOrNull?.lastPage}');

  final started = DateTime.now();
  final result = await source.fetchFullIndex(
    onProgress: (title, done, total) async {
      if (done % 1000 == 0) stdout.writeln('  $title -> $done entries');
    },
  );
  final elapsed = DateTime.now().difference(started);

  final entries = result.valueOrNull ?? const [];
  stdout.writeln('');
  stdout.writeln('entries indexed: ${entries.length}');
  stdout.writeln('unique urls    : ${entries.map((e) => e.cacheKey).toSet().length}');
  stdout.writeln('elapsed        : ${elapsed.inSeconds}s');
  stdout.writeln('sample         : ${entries.take(3).map((e) => e.title).join(' | ')}');

  if (entries.length < 5000) {
    stderr.writeln('FAIL: expected the full catalogue, got ${entries.length}');
    exitCode = 1;
  } else {
    stdout.writeln('OK');
  }
  client.close(force: true);
}
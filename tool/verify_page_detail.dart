// Fetches a live repack page and reports what the parser actually produced.
//
//   dart run tool/verify_page_detail.dart [url]
//
// Excluded from `flutter test` because it performs network reads.
import 'dart:io';

import 'package:project_rpck/core/http/resilient_client.dart';
import 'package:project_rpck/sources/fitgirl/fitgirl_page_parser.dart';

const _userAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0 Safari/537.36';

const _defaultUrl = 'https://fitgirl-repacks.site/a-pizza-delivery/';

Future<void> main(List<String> arguments) async {
  final url = arguments.isEmpty ? _defaultUrl : arguments.first;
  final http = ResilientClient(userAgent: _userAgent);

  final uri = Uri.parse(url);
  final body = (await http.getString(uri)).valueOrNull;
  if (body == null) {
    stderr.writeln('could not read $url');
    exitCode = 1;
    return;
  }

  final parsed = FitgirlPageParser(uri).parse(body).valueOrNull;
  if (parsed == null) {
    stderr.writeln('parse failed: see the parse failure above');
    exitCode = 1;
    http.close();
    return;
  }

  final description = parsed.description;

  stdout.writeln('url            : $url');
  stdout.writeln('title          : ${parsed.title}');
  stdout.writeln('description len: ${description.length}');
  stdout.writeln('screenshots    : ${parsed.screenshots.length}');
  stdout.writeln('info keys      : ${parsed.info.keys.join(', ')}');
  stdout.writeln('features       : ${parsed.repackFeatures.length}');
  stdout.writeln('sources        : ${parsed.sources.length}');
  for (final option in parsed.sources) {
    stdout.writeln('   ${option.runtimeType.toString().padRight(20)} '
        '${option.label}');
  }

  stdout.writeln('');
  stdout.writeln('-- description opens --');
  stdout.writeln(description.substring(0, description.length.clamp(0, 400)));

  // The regression this guards: the first two spoilers on a live page are
  // "Click to show direct links" and hold only mirror file names.
  final leaked = RegExp(r'\.rar|\.zip|\.7z|part\d', caseSensitive: false)
      .allMatches(description.split('\n').first)
      .isNotEmpty;
  stdout.writeln('');
  stdout.writeln('first paragraph contains file names: $leaked');
  if (leaked) exitCode = 2;

  http.close();
}
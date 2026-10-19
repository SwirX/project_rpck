import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/result.dart';

/// A page fetched on behalf of a bot-protected index.
class FetchedPage {
  final String body;
  final int statusCode;
  final Uri uri;

  const FetchedPage({required this.body, required this.statusCode, required this.uri});
}

/// How a bot-protected index can be reached.
///
/// The index is behind a challenge in practice: 1337x and every mirror checked
/// on 2026-10-19 answered 403 to a plain request. Rather than abandon the source,
/// access is attempted through an ordered chain, cheapest first.
///
/// Open rather than sealed on purpose: a user who installs a different browser,
/// or a proxy they already run, should be able to add a strategy without the
/// app shipping their tooling.
abstract interface class IndexAccessStrategy {
  const IndexAccessStrategy();

  String get name;

  /// Whether this strategy can run on the current host.
  bool get isAvailable;

  Future<Result<FetchedPage>> fetch(Uri uri);
}

/// A plain request wearing a browser's headers.
///
/// Cheap and worth trying first: a challenge is sometimes only a missing
/// Referer or a bot User-Agent, and no extra software is needed. Not framed as
/// evasion of an access control, only as sending the headers a normal browser
/// sends so the response is the page rather than a challenge.
class HeaderSpoofingStrategy implements IndexAccessStrategy {
  final Dio _client;
  final String userAgent;
  final String host;

  HeaderSpoofingStrategy({
    required this.userAgent,
    required this.host,
    Dio? client,
  }) : _client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              maxRedirects: 8,
              validateStatus: (_) => true,
            ));

  static const _chromeUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  @override
  String get name => 'browser headers';

  @override
  bool get isAvailable => true;

  Map<String, String> buildHeaders(Uri uri) => <String, String>{
        'User-Agent': userAgent.isEmpty ? _chromeUserAgent : userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': 'https://$host/',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'same-origin',
        'Sec-Fetch-User': '?1',
      };

  @override
  Future<Result<FetchedPage>> fetch(Uri uri) async {
    try {
      final response = await _client.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          headers: buildHeaders(uri),
        ),
      );
      final status = response.statusCode ?? 0;
      final body = response.data ?? '';
      if (status == 200 && body.isNotEmpty) {
        return Success(FetchedPage(body: body, statusCode: status, uri: uri));
      }
      return FailureResult(
        Failure(FailureKind.http, 'the index answered HTTP $status'),
      );
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.network, 'the index was unreachable', cause: error),
      );
    }
  }
}

/// An external headless browser the user installs separately.
///
/// Deliberately not bundled: shipping a browser binary would multiply the
/// download size and add a native dependency for a source that usually works
/// through the cheaper strategies. The app looks for one the user has
/// installed and uses it when present.
class StealthBrowserStrategy implements IndexAccessStrategy {
  final String? executablePath;
  final Duration timeout;

  const StealthBrowserStrategy({this.executablePath, this.timeout = const Duration(seconds: 45)});

  /// Common install locations, checked in order.
  static const candidateExecutables = <String>[
    'chromium',
    'chromium-browser',
    'google-chrome',
    'google-chrome-stable',
  ];

  /// Locates an installed browser, preferring an explicit path.
  static Future<String?> discover({String? configuredPath}) async {
    if (configuredPath != null && await File(configuredPath).exists()) {
      return configuredPath;
    }
    for (final name in candidateExecutables) {
      final found = await _which(name);
      if (found != null) return found;
    }
    return null;
  }

  static Future<String?> _which(String executable) async {
    try {
      final result = await Process.run(
        'which',
        [executable],
        runInShell: true,
      );
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  @override
  String get name => 'headless browser';

  @override
  bool get isAvailable => executablePath != null;

  /// Renders [uri] and returns the resulting document.
  ///
  /// Uses headless Chromium's DOM dump rather than a debugging protocol, so no
  /// extra package and no listening port are required.
  @override
  Future<Result<FetchedPage>> fetch(Uri uri) async {
    final binary = executablePath;
    if (binary == null) {
      return const FailureResult(
        Failure(FailureKind.unknown, 'no browser is installed'),
      );
    }

    try {
      final result = await Process.run(
        binary,
        [
          '--headless=new',
          '--disable-gpu',
          '--no-sandbox',
          '--dump-dom',
          '--virtual-time-budget=8000',
          '--user-agent=${HeaderSpoofingStrategy._chromeUserAgent}',
          uri.toString(),
        ],
        runInShell: true,
      ).timeout(timeout);

      if (result.exitCode != 0) {
        return FailureResult(
          Failure(FailureKind.unknown, 'the browser exited with ${result.exitCode}'),
        );
      }
      final body = (result.stdout as String).trim();
      if (body.isEmpty) {
        return const FailureResult(
          Failure(FailureKind.parse, 'the browser returned no document'),
        );
      }
      return Success(FetchedPage(body: body, statusCode: 200, uri: uri));
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.unknown, 'the browser could not be run',
            cause: error),
      );
    }
  }
}

/// Hands the page to the user's own browser.
///
/// The last resort. It does not read the page, it asks a human to, by opening
/// the listing so they can download the torrent themselves.
class BrowserHandoffStrategy implements IndexAccessStrategy {
  final bool canOpen;

  BrowserHandoffStrategy({this.canOpen = true});

  @override
  String get name => 'open in your browser';

  @override
  bool get isAvailable => canOpen;

  @override
  Future<Result<FetchedPage>> fetch(Uri uri) async {
    return FailureResult(
      Failure(
        FailureKind.cancelled,
        'open this page yourself to get the torrent: $uri',
        cause: uri,
      ),
    );
  }
}
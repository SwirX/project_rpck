import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/download/engine/index_access_strategy.dart';
import 'package:project_rpck/download/engine/torrent_index_resolver.dart';

/// Strategy that records whether it ran and returns a scripted outcome.
class _ScriptedStrategy implements IndexAccessStrategy {
  @override
  final String name;
  final Result<FetchedPage> outcome;
  final bool available;
  bool ran = false;

  _ScriptedStrategy(
    this.name, {
    required this.outcome,
    this.available = true,
  });

  @override
  bool get isAvailable => available;

  @override
  Future<Result<FetchedPage>> fetch(Uri uri) async {
    ran = true;
    return outcome;
  }
}

Result<FetchedPage> _refused() => const FailureResult(
      Failure(FailureKind.http, 'blocked'),
    );

Result<FetchedPage> _granted(String body) => Success(
      FetchedPage(body: body, statusCode: 200, uri: Uri.parse('https://x/')),
    );

void main() {
  final listing = Uri.parse('https://www.1337x.to/torrent/1/Some-Game/');

  group('access chain order', () {
    test('uses the first strategy that succeeds', () async {
      final first = _ScriptedStrategy('headers', outcome: _granted('<html></html>'));
      final second = _ScriptedStrategy('browser', outcome: _granted('<html></html>'));

      final resolver = TorrentIndexResolver.withStrategies([first, second]);
      await resolver.expand(listing);

      expect(first.ran, isTrue);
      expect(second.ran, isFalse, reason: 'the chain stops at the first success');
    });

    test('falls through to the next strategy on failure', () async {
      final first = _ScriptedStrategy('headers', outcome: _refused());
      final second = _ScriptedStrategy('browser', outcome: _granted(
            '<html><body><a id="openPopup" href="magnet:?xt=urn:btih:'
            '0123456789abcdef0123456789abcdef01234567&dn=Game">m</a></body></html>',
          ));

      final resolver = TorrentIndexResolver.withStrategies([first, second]);
      final result = await resolver.expand(listing);

      expect(first.ran, isTrue);
      expect(second.ran, isTrue);
      expect(result.isSuccess, isTrue);
      expect(resolver.lastUsedStrategy?.name, 'browser');
    });

    test('skips a strategy that reports itself unavailable', () async {
      final unavailable =
          _ScriptedStrategy('browser', outcome: _granted('<html></html>'), available: false);
      final headers = _ScriptedStrategy('headers', outcome: _granted('<html></html>'));

      final resolver = TorrentIndexResolver.withStrategies([unavailable, headers]);
      await resolver.expand(listing);

      expect(unavailable.ran, isFalse);
      expect(headers.ran, isTrue);
    });

    test('the browser handoff stops the walk and explains itself', () async {
      final refused = _ScriptedStrategy('headers', outcome: _refused());
      final unavailableBrowser = _ScriptedStrategy(
        'browser',
        outcome: _granted('<html></html>'),
        available: false,
      );

      final resolver = TorrentIndexResolver.withStrategies([
        refused,
        unavailableBrowser,
        BrowserHandoffStrategy(),
      ]);
      final result = await resolver.expand(listing);

      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.cancelled);
      expect(result.failureOrNull!.message, contains('your browser'));
      expect(result.failureOrNull!.message, contains(listing.toString()));
    });

    test('reports every attempt when nothing works', () async {
      final resolver = TorrentIndexResolver.withStrategies([
        _ScriptedStrategy('headers', outcome: _refused()),
        _ScriptedStrategy('browser', outcome: _refused()),
      ]);

      final result = await resolver.expand(listing);

      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.message, contains('any method'));
    });

    test('an unknown index host is refused without any request', () async {
      final headers = _ScriptedStrategy('headers', outcome: _granted('<html></html>'));
      final resolver = TorrentIndexResolver.withStrategies([headers]);

      final result = await resolver.expand(
        Uri.parse('https://example.org/torrent/1/x/'),
      );

      expect(result.isSuccess, isFalse);
      expect(headers.ran, isFalse);
    });
  });

  group('listing expansion', () {
    test('reads the primary magnet', () async {
      final resolver = TorrentIndexResolver.withStrategies([
        _ScriptedStrategy('headers', outcome: _granted(
              '<html><body><a id="openPopup" href="magnet:?xt=urn:btih:'
              '0123456789abcdef0123456789abcdef01234567&dn=Game">magnet</a>'
              '</body></html>',
            )),
      ]);

      final expanded = (await resolver.expand(listing)).valueOrNull!;
      expect(expanded.magnets.length, 1);
      expect(expanded.torrentUri, isNull);
    });

    test('reads a torrent link from the tracker dropdown', () async {
      final resolver = TorrentIndexResolver.withStrategies([
        _ScriptedStrategy('headers', outcome: _granted(
              '<html><body><ul aria-labelledby="dropdownMenu1"><li>'
              '<a href="https://itorrents.org/download/1.html">torrent</a>'
              '</li></ul></body></html>',
            )),
      ]);

      final expanded = (await resolver.expand(listing)).valueOrNull!;
      expect(expanded.torrentUri.toString(), contains('itorrents.org'));
    });

    test('collects magnets from the dropdown too', () async {
      final resolver = TorrentIndexResolver.withStrategies([
        _ScriptedStrategy('headers', outcome: _granted(
              '<html><body><ul aria-labelledby="dropdownMenu2"><li>'
              '<a href="magnet:?xt=urn:btih:'
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">a</a>'
              '<a href="magnet:?xt=urn:btih:'
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">b</a>'
              '</li></ul></body></html>',
            )),
      ]);

      final expanded = (await resolver.expand(listing)).valueOrNull!;
      expect(expanded.magnets.length, 2);
    });

    test('a page with nothing usable fails rather than returning empty', () async {
      final resolver = TorrentIndexResolver.withStrategies([
        _ScriptedStrategy('headers', outcome: _granted('<html><body>nothing</body></html>')),
      ]);

      final result = await resolver.expand(listing);
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.parse);
    });

    test('a non html body fails to parse', () async {
      final resolver = TorrentIndexResolver.withStrategies([
        _ScriptedStrategy('headers', outcome: _granted('not html at all <<<')),
      ]);
      expect((await resolver.expand(listing)).isSuccess, isFalse);
    });
  });

  group('HeaderSpoofingStrategy', () {
    test('sends the headers a browser sends, including a referer', () {
      final strategy = HeaderSpoofingStrategy(
        userAgent: '',
        host: 'www.1337x.to',
      );

      final headers = strategy.buildHeaders(listing);

      expect(headers['Referer'], 'https://www.1337x.to/');
      expect(headers['User-Agent'], contains('Chrome'));
      expect(headers['Accept-Language'], isNotNull);
      expect(headers['Sec-Fetch-Mode'], 'navigate');
    });

    test('is always available', () {
      expect(
        HeaderSpoofingStrategy(userAgent: '', host: 'x').isAvailable,
        isTrue,
      );
    });
  });

  group('StealthBrowserStrategy', () {
    test('is unavailable without an installed browser', () {
      expect(const StealthBrowserStrategy().isAvailable, isFalse);
    });

    test('is available once a path is given', () {
      expect(
        const StealthBrowserStrategy(executablePath: '/usr/bin/chromium')
            .isAvailable,
        isTrue,
      );
    });

    test('reports a missing binary rather than throwing', () async {
      final result = await StealthBrowserStrategy().fetch(listing);
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.message, contains('no browser is installed'));
    });
  });

  group('BrowserHandoffStrategy', () {
    test('always asks the user to open the page', () async {
      final result = await BrowserHandoffStrategy().fetch(listing);
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.cancelled);
      expect(result.failureOrNull!.message, contains(listing.toString()));
    });
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/sources/fitgirl/fitgirl_source.dart';

/// Builds an index page body with [count] entries and a paginator ending at
/// [lastPage], matching the shape observed on the live site.
String indexBody({
  required int count,
  required int lastPage,
  String prefix = 'game',
  int startIndex = 0,
}) {
  final items = <String>[];
  for (var offset = 0; offset < count; offset++) {
    final slug = '$prefix-${startIndex + offset}';
    items.add('<li><a href="https://fitgirl-repacks.site/$slug/">$slug</a></li>');
  }

  final visible = lastPage < 5 ? lastPage : 5;
  final links = <String>[];
  for (var page = 1; page <= visible; page++) {
    links.add("<li><a href='/all-my-repacks-a-z/?lcp_page0=$page#lcp_instance_0'"
        " title='$page'>$page</a></li>");
  }
  links.add("<span class='lcp_elipsis'>...</span>");
  if (lastPage > 5) {
    links.add("<li><a href='/all-my-repacks-a-z/?lcp_page0=$lastPage#lcp_instance_0'"
        " title='$lastPage'>$lastPage</a></li>");
  }

  return '<html><body><div class="entry-content">'
      '<ul class="lcp_catlist" id="lcp_instance_0">${items.join()}</ul>'
      "<ul class='lcp_paginator'>${links.join()}</ul>"
      '</div></body></html>';
}

/// Source that serves a scripted body per requested page number.
FitgirlSource scripted(Map<int, String> pages, {List<int>? log}) {
  return FitgirlSource(
    fetch: (uri) async {
      final page = int.tryParse(uri.queryParameters['lcp_page0'] ?? '') ?? 0;
      log?.add(page);
      return pages[page];
    },
  );
}

void main() {
  group('paginator parsing', () {
    test('reads the advertised final page', () async {
      final source = scripted({0: indexBody(count: 4, lastPage: 147)});
      final page = await source.fetchIndexPage();
      expect(page.valueOrNull!.lastPage, 147);
    });

    test('reports no final page when the paginator is absent', () async {
      final source = scripted({
        0: '<html><body><ul id="lcp_instance_0"><li><a href="/a/">A</a></li></ul></body></html>',
      });
      final page = await source.fetchIndexPage();
      expect(page.valueOrNull!.lastPage, isNull);
    });

    test('reports no final page when the listing root is gone', () async {
      final source = scripted({0: '<html><body><p>nothing</p></body></html>'});
      final page = await source.fetchIndexPage();
      expect(page.valueOrNull!.entries, isEmpty);
      expect(page.valueOrNull!.nextCursor, isNull);
    });
  });

  group('entry parsing', () {
    test('falls back to the list class when the wrapper id is renumbered',
        () async {
      final source = scripted({
        0: '<html><body><ul class="lcp_catlist">'
            '<li><a href="https://fitgirl-repacks.site/x/">X</a></li></ul>'
            '</body></html>',
      });
      final page = await source.fetchIndexPage();
      expect(page.valueOrNull!.entries.length, 1);
    });

    test('resolves a relative href against the listing', () async {
      final source = scripted({
        0: '<html><body><ul id="lcp_instance_0">'
            '<li><a href="/game/relative/">R</a></li></ul></body></html>',
      });
      final page = await source.fetchIndexPage();
      expect(
        page.valueOrNull!.entries.single.pageUri,
        Uri.parse('https://fitgirl-repacks.site/game/relative/'),
      );
    });
  });

  group('fetchFullIndex', () {
    test('walks to the advertised final page', () async {
      final source = scripted({
        for (var page = 0; page <= 5; page++)
          page: indexBody(
            count: 50,
            lastPage: 5,
            prefix: 'g',
            startIndex: page * 50,
          ),
      });

      final result = await source.fetchFullIndex();
      final entries = result.valueOrNull!;

      // Six pages of fifty, none overlapping.
      expect(entries.length, 300);
      expect(entries.toSet().length, 300);
    });

    test('reaches the end of a 147 page listing', () async {
      // The live listing is 147 pages; the prototype assumed 100.
      final source = scripted({
        for (var page = 0; page <= 147; page++)
          page: indexBody(
            count: 50,
            lastPage: 147,
            prefix: 'g',
            startIndex: page * 50,
          ),
      });

      final entries = (await source.fetchFullIndex()).valueOrNull!;

      expect(entries.length, 148 * 50);
      expect(entries.toSet().length, 148 * 50);
    });

    test('does not stop when a page repeats the previous one', () async {
      // This is the live fault: page 2 is served page 0's body. An earlier
      // implementation treated a page that added nothing new as the end of the
      // listing, which stopped the walk at a few hundred entries.
      final page0 = indexBody(count: 50, lastPage: 4, prefix: 'a', startIndex: 0);
      final source = scripted({
        0: page0,
        1: indexBody(count: 50, lastPage: 4, prefix: 'b', startIndex: 500),
        2: page0,
        3: indexBody(count: 50, lastPage: 4, prefix: 'c', startIndex: 1500),
        4: indexBody(count: 50, lastPage: 4, prefix: 'd', startIndex: 2000),
      });

      final entries = (await source.fetchFullIndex()).valueOrNull!;

      expect(entries.length, 200, reason: 'the repeated page must not end the walk');
    });

    test('retries a repeated page and recovers its entries', () async {
      // A repeat that later serves fresh content is picked up on the retry.
      final fresh = indexBody(count: 50, lastPage: 2, prefix: 'z', startIndex: 900);
      var served = 0;
      final source = FitgirlSource(
        fetch: (uri) async {
          final page = int.tryParse(uri.queryParameters['lcp_page0'] ?? '') ?? 0;
          if (page != 1) return indexBody(count: 50, lastPage: 2, prefix: 'a', startIndex: 0);
          served++;
          return served == 1
              ? indexBody(count: 50, lastPage: 2, prefix: 'a', startIndex: 0)
              : fresh;
        },
      );

      final entries = (await source.fetchFullIndex()).valueOrNull!;

      expect(served, 2, reason: 'the repeat must be retried once');
      expect(entries.any((entry) => entry.title.startsWith('z')), isTrue);
    });

    test('tolerates an unordered page from the site', () async {
      // Page 1 is served as an unordered set of unrelated entries upstream.
      final source = scripted({
        0: indexBody(count: 50, lastPage: 3, prefix: 'a', startIndex: 0),
        1: indexBody(count: 50, lastPage: 3, prefix: 'junk', startIndex: 9000),
        2: indexBody(count: 50, lastPage: 3, prefix: 'c', startIndex: 100),
        3: indexBody(count: 7, lastPage: 3, prefix: 'z', startIndex: 200),
      });

      final entries = (await source.fetchFullIndex()).valueOrNull!;

      expect(entries.length, 157);
      expect(entries.any((entry) => entry.title.startsWith('junk')), isTrue);
      expect(entries.any((entry) => entry.title.startsWith('z')), isTrue);
    });

    test('stops after two consecutive empty pages', () async {
      final requested = <int>[];
      final source = scripted(
        {0: indexBody(count: 10, lastPage: 0), 1: '', 2: '', 3: ''},
        log: requested,
      );
      // lastPage 0 means the site advertises nothing, so only emptiness ends it.
      final entries = (await source.fetchFullIndex()).valueOrNull!;
      expect(entries.length, 10);
      expect(requested.last, 2, reason: 'two empty pages should end the walk');
    });

    test('stops at the final page rather than walking to the cap', () async {
      final requested = <int>[];
      final source = scripted(
        {
          for (var page = 0; page <= 2; page++)
            page: indexBody(count: 5, lastPage: 2, prefix: 'g', startIndex: page * 5),
        },
        log: requested,
      );

      await source.fetchFullIndex();
      expect(requested, [0, 1, 2]);
    });

    test('reports progress that reaches the final count', () async {
      final source = scripted({
        0: indexBody(count: 50, lastPage: 1, prefix: 'a', startIndex: 0),
        1: indexBody(count: 50, lastPage: 1, prefix: 'b', startIndex: 50),
      });

      final seen = <int>[];
      await source.fetchFullIndex(
        onProgress: (title, done, total) async => seen.add(done),
      );

      expect(seen.last, 100);
      expect(seen, contains(50));
    });

    test('propagates a fetch failure as a typed failure', () async {
      final source = FitgirlSource(fetch: (_) async => null);
      final result = await source.fetchFullIndex();
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.http);
    });

    test('an empty listing is not an error', () async {
      // An empty body is an empty listing; a null body is a failed fetch.
      final source = scripted({0: '', 1: ''});
      final result = await source.fetchFullIndex();
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isEmpty);
    });
  });

  group('title cleaning', () {
    test('keeps version numbers readable', () async {
      final source = scripted({
        0: '<html><body><ul id="lcp_instance_0"><li>'
            '<a href="https://fitgirl-repacks.site/x/">Game &#8211; v3.5.10b + 2 DLCs</a>'
            '</li></ul></body></html>',
      });
      final entries = (await source.fetchIndexPage()).valueOrNull!.entries;
      // Periods used to be stripped, turning v3.5.10b into v3510b.
      expect(entries.single.title, contains('v3.5.10b'));
    });

    test('expands numeric entities into spacing', () async {
      final source = scripted({
        0: '<html><body><ul id="lcp_instance_0"><li>'
            '<a href="https://fitgirl-repacks.site/y/">A&#8211;B</a>'
            '</li></ul></body></html>',
      });
      final entries = (await source.fetchIndexPage()).valueOrNull!.entries;
      expect(entries.single.title, 'A B');
    });
  });
}

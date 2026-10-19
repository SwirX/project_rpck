import 'dart:developer' as developer;

import 'package:html/parser.dart' as html_parser;

import '../../core/result.dart';
import '../../domain/models/repack.dart';
import '../repack_source.dart';
import 'fitgirl_locator.dart';
import 'fitgirl_page_parser.dart';

/// FitGirl Repacks implementation of the repack source contract.
///
/// Paging state lives in the cursor so [fetchIndexPage] stays stateless between
/// calls and the caller can resume a partially walked listing.
///
/// The listing is served by ListJS and is not well behaved over plain HTTP.
/// Measured on 2026-10-19 against `all-my-repacks-a-z/`: the paginator
/// advertises 147 pages of 50 entries, page 1 returns an unordered page of
/// unrelated titles, page 2 returns page 0's body verbatim, and page 147 is the
/// last with 7 entries. A cache-busting query string returns the same duplicate
/// bytes, so it is the site and not a local cache.
///
/// Duplicates and short responses are therefore normal rather than a signal
/// that the walk is finished, and [fetchFullIndex] is written around that.
class FitgirlSource implements RepackSourceAdapter {
  /// Stops a runaway walk if a site stops reporting a final page.
  static const maxPages = 500;

  final Future<String?> Function(Uri uri) _fetch;

  FitgirlSource({required Future<String?> Function(Uri uri) fetch})
      : _fetch = fetch;

  @override
  String get id => 'fitgirl';

  @override
  String get displayName => 'FitGirl';

  @override
  Uri get baseUri => Uri.parse(FitgirlLocator.indexListing);

  @override
  bool get supportsMagnet => true;

  @override
  bool get supportsTorrentFile => true;

  @override
  bool get supportsDirectDownload => true;

  @override
  Future<Result<IndexPage>> fetchIndexPage({String? cursor}) async {
    final page = cursor == null ? 0 : int.tryParse(cursor);
    if (page == null) {
      return const FailureResult(
        Failure(FailureKind.unknown, 'index cursor is not a page number'),
      );
    }
    final target = baseUri.replace(
      queryParameters: {...baseUri.queryParameters, 'lcp_page0': '$page'},
    );

    final body = await _fetch(target);
    if (body == null) {
      return FailureResult(Failure(FailureKind.http, 'index page $page failed'));
    }

    final entries = _parseEntries(body);
    return Success(
      IndexPage(
        entries: entries,
        nextCursor: entries.isEmpty ? null : '${page + 1}',
        lastPage: _parseLastPage(body),
      ),
    );
  }

  List<GameIndexEntry> _parseEntries(String body) {
    final document = html_parser.parse(body);
    final root = document.querySelector(FitgirlLocator.indexListRoot) ??
        document.querySelector(FitgirlLocator.indexListClass);
    if (root == null) return const [];

    final entries = <GameIndexEntry>[];
    for (final anchor in root.querySelectorAll('a')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final uri = Uri.tryParse(href);
      if (uri == null) continue;
      entries.add(
        GameIndexEntry(
          title: _cleanTitle(anchor.text),
          // Index hrefs are absolute today; resolving against the listing keeps
          // a relative href from producing an unusable page uri.
          pageUri: uri.hasScheme ? uri : baseUri.resolveUri(uri),
        ),
      );
    }
    return entries;
  }

  /// Reads the final page number from the paginator.
  ///
  /// Every link carries a numeric `title` and the largest is the end of the
  /// listing. The prototype parsed this out of a generic `[class*='paginator']`
  /// text node by splitting on `...` and `N`, and fell back to 100 when the
  /// split failed. The listing is 147 pages, so that guess capped the
  /// catalogue at roughly two thirds of its size.
  static int? _parseLastPage(String body) {
    final document = html_parser.parse(body);
    final paginator = document.querySelector(FitgirlLocator.paginator);
    if (paginator == null) return null;

    var highest = 0;
    for (final anchor in paginator.querySelectorAll(FitgirlLocator.paginatorLink)) {
      final title = anchor.attributes['title'];
      final page = title == null ? null : int.tryParse(title.trim());
      if (page != null && page > highest) highest = page;
    }
    return highest == 0 ? null : highest;
  }

  /// Strips the markup the index stores inside anchor text.
  ///
  /// Upstream embeds escaped unicode and stray quotes in the title, which the
  /// prototype removed with three overlapping regular expressions.
  static String _cleanTitle(String raw) {
    // Periods and commas survive: titles carry version numbers such as
    // "v1.2.3" and stripping them collapsed them into "v123". Neither is
    // rejected by the filename sanitiser, which removes what it must.
    //
    // Disallowed characters become a space rather than nothing, so a dash
    // inside a word does not weld the surrounding words together.
    final stripped = raw
        .replaceAll(RegExp(r'\\u[0-9a-fA-F]{4}'), '')
        .replaceAll(RegExp(r"[^A-Za-z0-9'\-., ]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.isEmpty ? 'Untitled repack' : stripped;
  }

  @override
  Future<Result<Repack>> fetchRepack(Uri pageUri) async {
    final body = await _fetch(pageUri);
    if (body == null) {
      return FailureResult(Failure(FailureKind.http, 'page $pageUri failed'));
    }
    return FitgirlPageParser(pageUri).parse(body);
  }

  @override
  Future<Result<List<GameIndexEntry>>> fetchFullIndex({
    Future<void> Function(String title, int done, int total)? onProgress,
  }) async {
    final collected = <GameIndexEntry>[];
    final seen = <String>{};
    var lastPage = 0;
    var consecutiveEmptyPages = 0;
    var skippedPages = 0;
    var repeatedPages = 0;

    for (var page = 0; page < maxPages; page++) {
      final index = await _fetchPageWithRetry(page);

      if (index == null) {
        // One unreachable page must not discard a walk that may already hold
        // thousands of entries. Skip it, unless nothing at all was collected,
        // in which case the listing really is unavailable.
        if (collected.isEmpty) {
          return const FailureResult(
            Failure(FailureKind.http, 'the first index page could not be fetched'),
          );
        }
        skippedPages++;
        continue;
      }

      final advertised = index.lastPage;
      if (advertised != null && advertised > lastPage) lastPage = advertised;

      if (index.entries.isEmpty) {
        // Two empty pages in a row ends the listing. One does not: the site
        // intermittently serves a short or blank response.
        consecutiveEmptyPages++;
        if (consecutiveEmptyPages >= 2) break;
      } else {
        consecutiveEmptyPages = 0;
      }

      final added = _absorb(index.entries, collected, seen);

      // A page that contributes nothing new is a repeat, not the end of the
      // listing. FitGirl serves page 0's body for page 2, so walking on without
      // a retry silently loses that page's fifty entries. Ask once more.
      if (added == 0 && index.entries.isNotEmpty) {
        repeatedPages++;
        final retried = await _fetchPageWithRetry(page);
        final entries = retried?.entries;
        if (entries != null) _absorb(entries, collected, seen);
      }

      await onProgress?.call('page ${page + 1}', collected.length, lastPage);

      if (lastPage > 0 && page >= lastPage) break;
    }

    if (skippedPages > 0 || repeatedPages > 0) {
      developer.log(
        'FitGirl index: ${collected.length} entries, '
        '$skippedPages unreachable, $repeatedPages repeated page(s)',
        name: 'fitgirl.index',
      );
    }
    return Success(collected);
  }

  /// Fetches one page, retrying a transient failure once.
  Future<IndexPage?> _fetchPageWithRetry(int page) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await fetchIndexPage(cursor: '$page');
      final index = result.fold((value) => value, (_) => null);
      if (index != null) return index;
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    return null;
  }

  /// Adds entries not already seen and returns how many were genuinely new.
  static int _absorb(
    List<GameIndexEntry> entries,
    List<GameIndexEntry> collected,
    Set<String> seen,
  ) {
    var added = 0;
    for (final entry in entries) {
      if (seen.add(entry.cacheKey)) {
        collected.add(entry);
        added++;
      }
    }
    return added;
  }
}
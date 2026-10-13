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
class FitgirlSource implements RepackSourceAdapter {
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
    if (entries.isEmpty) {
      return const Success(IndexPage(entries: [], nextCursor: null));
    }
    return Success(IndexPage(entries: entries, nextCursor: '${page + 1}'));
  }

  List<GameIndexEntry> _parseEntries(String body) {
    final document = html_parser.parse(body);
    final root = document.querySelector(FitgirlLocator.indexListRoot);
    if (root == null) return const [];

    final entries = <GameIndexEntry>[];
    for (final anchor in root.querySelectorAll('a')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final uri = Uri.tryParse(href);
      if (uri == null) continue;
      entries.add(
        GameIndexEntry(title: _cleanTitle(anchor.text), pageUri: uri),
      );
    }
    return entries;
  }

  /// Strips the markup the index stores inside anchor text.
  ///
  /// Upstream embeds escaped unicode and stray quotes in the title, which the
  /// prototype removed with three overlapping regular expressions.
  static String _cleanTitle(String raw) {
    final stripped = raw
        .replaceAll(RegExp(r'\\u[0-9a-fA-F]{4}'), '')
        .replaceAll(RegExp(r'''[^A-Za-z0-9'\- ]'''), '')
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
    String? cursor;
    var page = 0;

    while (true) {
      final pageResult = await fetchIndexPage(cursor: cursor);
      final index = pageResult.fold(
        (value) => value,
        (failure) => null,
      );
      if (index == null) {
        return FailureResult(
          pageResult.failureOrNull ??
              const Failure(FailureKind.unknown, 'index walk failed'),
        );
      }
      if (index.entries.isEmpty) break;

      var added = 0;
      for (final entry in index.entries) {
        if (seen.add(entry.cacheKey)) {
          collected.add(entry);
          added++;
        }
      }
      page++;
      await onProgress?.call('page $page', collected.length, collected.length);

      // A page that contributed nothing new is the listing repeating itself.
      if (added == 0 || index.nextCursor == null) break;
      cursor = index.nextCursor;
    }

    return Success(collected);
  }
}
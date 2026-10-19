
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/result.dart';
import 'index_access_strategy.dart';

/// A torrent file or magnet recovered from an index listing page.
class ExpandedTorrent {
  final Uri? torrentUri;
  final List<String> magnets;

  const ExpandedTorrent({this.torrentUri, this.magnets = const []});

  bool get isUsable => torrentUri != null || magnets.isNotEmpty;
}

/// Selectors for a torrent index listing page.
///
/// Isolated so a redesign of one index is a one file change, and so the tests
/// can point at a saved fixture.
abstract final class TorrentIndexLocator {
  /// The primary magnet anchor on a 1337x listing.
  static const magnetAnchor = 'a#openPopup';

  /// The per-tracker dropdown on a 1337x listing.
  static const trackerItems = "[aria-labelledby^='dropdownMenu'] li a";

  /// Mirrors that serve a `.torrent` when followed.
  static const torrentMirrorHosts = <String>{'itorrents.org', 'torrage.info'};

  /// Hosts known to serve a `.torrent` directly from the dropdown.
  static const directTorrentMarkers = <String>['.torrent'];
}

/// Expands a torrent index listing into something the engine can use.
///
/// FitGirl links a tracker's listing page, not the `.torrent` file, so the page
/// has to be read before anything can be handed to the torrent engine. Only
/// 1337x is implemented; an unknown host is reported rather than guessed at.
///
/// The index is behind a bot challenge in practice: 1337x and its mirrors
/// returned 403 to every automated request checked on 2026-10-19. A blocked
/// index therefore surfaces as a typed failure so the user can pick the magnet
/// or a mirror instead, rather than the app silently doing nothing.
class TorrentIndexResolver {
  final Future<List<IndexAccessStrategy>> Function(Uri host) _chainFactory;

  List<IndexAccessStrategy>? _chain;

  /// Which strategy produced the page, for diagnostics.
  IndexAccessStrategy? lastUsedStrategy;

  TorrentIndexResolver({required Future<List<IndexAccessStrategy>> Function(Uri) chainFactory})
      : _chainFactory = chainFactory;

  /// Builds the chain synchronously, for tests and for callers that already
  /// know which methods are available.
  TorrentIndexResolver.withStrategies(List<IndexAccessStrategy> strategies)
      : _chainFactory = ((_) => Future<List<IndexAccessStrategy>>.value(strategies));

  Future<Result<ExpandedTorrent>> expand(Uri listingUri) async {
    final host = listingUri.host;
    if (!host.contains('1337x')) {
      return FailureResult(
        Failure(
          FailureKind.unknown,
          'no expansion is implemented for the index at $host',
        ),
      );
    }
    _chain ??= await _chainFactory(listingUri);
    return _expand1337x(listingUri);
  }

  /// Walks the access chain until one strategy returns the page.
  Future<Result<ExpandedTorrent>> _expand1337x(Uri listingUri) async {
    final attempts = <String>[];

    for (final strategy in _chain ?? const <IndexAccessStrategy>[]) {
      if (!strategy.isAvailable) continue;

      if (strategy is BrowserHandoffStrategy) {
        // The last resort cannot read the page, so it is reported to the user
        // rather than attempted as a fetch.
        attempts.add(strategy.name);
        return FailureResult(
          Failure(
            FailureKind.cancelled,
            'Every automated route to ${listingUri.host} was refused. '
            'Open the listing in your browser to download it: $listingUri',
            cause: attempts,
          ),
        );
      }

      final page = await strategy.fetch(listingUri);
      if (page case Success<FetchedPage>(:final value)) {
        lastUsedStrategy = strategy;
        return _parseDocument(value);
      }
      attempts.add('${strategy.name}: ${page.failureOrNull?.message}');
    }

    return FailureResult(
      Failure(
        FailureKind.http,
        'the tracker index could not be reached by any method',
        cause: attempts,
      ),
    );
  }

  Future<Result<ExpandedTorrent>> _parseDocument(FetchedPage page) async {
    final document = guardSync(() => html_parser.parse(page.body));
    final parsed = document.fold((value) => value, (_) => null);
    if (parsed == null) {
      return const FailureResult(
        Failure(FailureKind.parse, 'the tracker index was not valid HTML'),
      );
    }

    final expanded = _collect(parsed);
    if (!expanded.isUsable) {
      return const FailureResult(
        Failure(FailureKind.parse, 'the listing exposed no torrent or magnet'),
      );
    }
    return Success(expanded);
  }

  /// Reads the magnet and the per-tracker torrent links off a listing.
  static ExpandedTorrent _collect(Document document) {
    final magnets = <String>[];
    final torrentUris = <Uri>[];

    final primary = document.querySelector(TorrentIndexLocator.magnetAnchor);
    final primaryMagnet = primary?.attributes['href'];
    if (primaryMagnet != null && primaryMagnet.startsWith('magnet:')) {
      magnets.add(primaryMagnet);
    }

    for (final anchor
        in document.querySelectorAll(TorrentIndexLocator.trackerItems)) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;
      if (href.startsWith('magnet:')) {
        magnets.add(href);
        continue;
      }
      final uri = Uri.tryParse(href);
      if (uri == null) continue;
      if (TorrentIndexLocator.torrentMirrorHosts.contains(uri.host) ||
          href.endsWith('.torrent')) {
        torrentUris.add(uri);
      }
    }

    // A torrent file is preferred over a magnet: it carries its own trackers.
    return ExpandedTorrent(
      torrentUri: torrentUris.isEmpty ? null : torrentUris.first,
      magnets: magnets,
    );
  }
}
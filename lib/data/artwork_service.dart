import 'dart:async';

import '../sources/repack_source.dart';
import 'catalogue_database.dart';
import 'catalogue_repository.dart';

/// A catalogue row paired with whatever artwork is known for it.
class CoverRequest {
  final String sourceId;
  final String url;
  final String title;
  final String? cachedCoverUrl;

  const CoverRequest({
    required this.sourceId,
    required this.url,
    required this.title,
    this.cachedCoverUrl,
  });
}

/// Supplies cover art for catalogue tiles, on demand.
///
/// The grid used to fetch a full repack page per visible tile, which is why
/// scrolling cost a network request each. The reverse mistake is to fetch
/// 7000 pages during indexing, which would take hours. This resolves the middle
/// ground: the first time a tile is shown the repack page is fetched once, the
/// resulting url is written to the catalogue, and every later launch reads it
/// from SQLite without touching the network.
///
/// Requests are deduplicated in memory and capped per host, so a fast scroll
/// cannot open a hundred connections.
class ArtworkService {
  final CatalogueDatabase _database;
  final SourceCatalog _catalog;
  final int _maxConcurrent;

  final Map<String, Future<String?>> _inFlight = {};

  ArtworkService({
    required CatalogueDatabase database,
    required SourceCatalog catalog,
    int maxConcurrent = 4,
  })  : _database = database,
        _catalog = catalog,
        _maxConcurrent = maxConcurrent;

  int _active = 0;
  final List<Completer<void>> _waiting = [];

  /// Holds a slot until the returned action finishes.
  ///
  /// Fetching a repack page is expensive, so a fast scroll must not turn into a
  /// hundred simultaneous requests to one host.
  Future<T> _withSlot<T>(Future<T> Function() action) async {
    while (_active >= _maxConcurrent) {
      final gate = Completer<void>();
      _waiting.add(gate);
      await gate.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_waiting.isNotEmpty && _active < _maxConcurrent) {
        _waiting.removeAt(0).complete();
      }
    }
  }

  /// Returns the cover url for [request], resolving it if it is not cached.
  ///
  /// Returns null when the repack page has no artwork or could not be read; the
  /// caller renders a placeholder and does not retry in a tight loop.
  Future<String?> coverFor(CoverRequest request) async {
    final cached = request.cachedCoverUrl;
    if (cached != null && cached.isNotEmpty) return cached;

    final key = '${request.sourceId}|${request.url}';
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final pending = _resolve(request);
    _inFlight[key] = pending;
    try {
      return await pending;
    } finally {
      // A failed resolution must not be memoised, or one transient fault would
      // blank that tile for the rest of the session.
      _inFlight.remove(key);
    }
  }

  Future<String?> _resolve(CoverRequest request) async {
    return _withSlot(() async {
      final adapter = _catalog.adapterFor(request.sourceId);
      if (adapter == null) return null;

      try {
        final parsed = await adapter.fetchRepack(Uri.parse(request.url));
        final cover = parsed.valueOrNull?.coverUrl;
        await _database.setCoverUrl(
          sourceId: request.sourceId,
          url: request.url,
          coverUrl: cover == '' ? null : cover,
        );
        return cover == '' ? null : cover;
      } catch (_) {
        return null;
      }
    });
  }

  /// Pre-fetches artwork for a batch of rows, respecting the concurrency cap.
  ///
  /// Used by the artwork warmer so that scrolling the grid does not become the
  /// thing that drives network traffic.
  Future<void> warm(List<CoverRequest> requests) async {
    for (final request in requests) {
      if (_active >= _maxConcurrent) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      unawaited(coverFor(request));
    }
  }
}

/// Lets [ArtworkService] resolve an adapter by id without depending on the
/// concrete registry type.
extension SourceCatalogLookup on SourceCatalog {
  RepackSourceAdapter? adapterFor(String id) {
    for (final adapter in all) {
      if (adapter.id == id) return adapter;
    }
    return null;
  }
}
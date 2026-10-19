import 'dart:async';

import '../core/result.dart';
import '../domain/models/repack.dart';
import '../sources/repack_source.dart';
import 'catalogue_database.dart';
import 'catalogue_query.dart';

/// Progress of a running index pass.
class IndexProgress {
  final String phase;
  final int indexed;
  final int? totalPages;

  const IndexProgress(this.phase, this.indexed, {this.totalPages});
}

/// The slice of the source registry the repository needs.
///
/// Declared here rather than depending on [SourceRegistry] so the repository
/// can be exercised with a fake and no HTTP.
abstract interface class SourceCatalog {
  List<RepackSourceAdapter> get all;
}

/// Owns the on-disk catalogue and the index pass that fills it.
///
/// The prototype re-walked every index page on every launch, which is why a
/// cold start took minutes and appeared to load nothing. The catalogue is read
/// from SQLite and only re-walked on request.
class CatalogueRepository {
  final CatalogueDatabase _database;

  CatalogueRepository(this._database);

  CatalogueDatabase get database => _database;

  Future<int> storedCount({String? sourceId}) =>
      _database.count(sourceId: sourceId);

  Future<DateTime?> lastIndexed() => _database.lastIndexedAt();

  Future<CataloguePage> read({
    String? search,
    String? sourceId,
    CatalogueSort sort = CatalogueSort.alphabetical,
    int limit = 120,
    int offset = 0,
    bool withCover = false,
  }) =>
      _database.query(
        search: search,
        sourceId: sourceId,
        sort: sort,
        limit: limit,
        offset: offset,
        withCover: withCover,
      );

  Future<void> clear() => _database.clear();

  /// Walks every registered source and replaces what is stored.
  ///
  /// The walk is long, so progress is reported rather than blocking: the UI
  /// keeps reading the previous catalogue until the new one is committed.
  Future<Result<int>> reindex({
    required SourceCatalog catalog,
    Future<void> Function(IndexProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final adapters = catalog.all;
    if (adapters.isEmpty) {
      return const FailureResult(
        Failure(FailureKind.unknown, 'no repack source is registered'),
      );
    }

    var written = 0;
    for (final adapter in adapters) {
      if (shouldCancel?.call() ?? false) break;

      await onProgress?.call(IndexProgress('indexing ${adapter.id}', 0));

      final walk = await adapter.fetchFullIndex(
        onProgress: (title, done, total) async {
          await onProgress?.call(IndexProgress(title, done));
        },
      );

      if (shouldCancel?.call() ?? false) break;

      final entries =
          walk.fold((value) => value, (_) => const <GameIndexEntry>[]);

      final records = <IndexRecord>[
        for (final entry in entries)
          IndexRecord(
            sourceId: adapter.id,
            url: entry.pageUri.toString(),
            title: entry.title,
          ),
      ];

      await onProgress?.call(
        IndexProgress('storing ${records.length} entries', records.length),
      );
      written += await _database.replaceSource(adapter.id, records);
    }

    await onProgress?.call(IndexProgress('index complete', written));
    return Success(written);
  }
}
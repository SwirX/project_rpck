import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'catalogue_schema.dart';
import 'catalogue_query.dart';

/// One catalogue row as stored.
class IndexRecord {
  final String sourceId;
  final String url;
  final String title;

  /// Artwork url once it has been resolved; null until then.
  final String? coverUrl;

  const IndexRecord({
    required this.sourceId,
    required this.url,
    required this.title,
    this.coverUrl,
  });

  /// Lowercased, punctuation-free form used by the search index.
  String get normalisedTitle => normaliseTitle(title);

  factory IndexRecord.fromMap(Map<String, Object?> row) => IndexRecord(
        sourceId: row['source_id']! as String,
        url: row['url']! as String,
        title: row['title']! as String,
        coverUrl: row['cover_url'] as String?,
      );
}

/// Reduces a title to searchable tokens.
///
/// Punctuation is dropped rather than replaced so "Half-Life: Alyx" and
/// "Half Life Alyx" normalise to the same tokens.
String normaliseTitle(String raw) {
  final lowered = raw.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lowered.runes) {
    final isWord = (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        rune == 0x20;
    buffer.writeCharCode(isWord ? rune : 0x20);
  }
  return buffer
      .toString()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .join(' ');
}

/// Local catalogue storage.
///
/// Holds the repack index on disk so launching the app reads rows instead of
/// re-walking every index page of every source, which is what made a cold start
/// take minutes and appear to load nothing.
class CatalogueDatabase {
  final Database _database;

  CatalogueDatabase._(this._database);

  static const _fileName = 'catalogue.db';

  /// Driver used on a host with no injected factory, which is every desktop
  /// platform. Android passes the plugin's factory in from the caller so this
  /// file never imports a Flutter plugin, and stays runnable under a plain VM.
  static DatabaseFactory _defaultFactory() {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  /// Opens the catalogue inside [directory].
  ///
  /// The directory is supplied by the caller rather than resolved here, so this
  /// layer carries no plugin dependency and can run under a plain Dart VM.
  static Future<CatalogueDatabase> open({
    required String directory,
    DatabaseFactory? factory,
  }) async {
    await Directory(directory).create(recursive: true);
    return _openAt(p.join(directory, _fileName), factory);
  }

  /// Absolute path of the catalogue file inside [directory].
  static String pathIn(String directory) => p.join(directory, _fileName);

  static Future<CatalogueDatabase> openInMemory() =>
      _openAt(inMemoryDatabasePath, null);

  static Future<CatalogueDatabase> _openAt(
    String path,
    DatabaseFactory? factory,
  ) async {
    final database = await (factory ?? _defaultFactory()).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: CatalogueSchema.schemaVersion,
        onConfigure: (db) async {
          // Write-ahead logging lets a reader run while an index rebuild writes.
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=NORMAL');
        },
        onCreate: (db, _) async {
          for (final statement in CatalogueSchema.statements) {
            await db.execute(statement);
          }
        },
        onUpgrade: CatalogueSchema.upgrade,
      ),
    );
    return CatalogueDatabase._(database);
  }

  Database get raw => _database;

  Future<void> close() => _database.close();

  /// True when the bundled SQLite was compiled with FTS5.
  Future<bool> debugFtsAvailable() async {
    try {
      await _database.rawQuery('SELECT * FROM repack_index_fts LIMIT 0');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> count({String? sourceId}) async {
    final rows = await _database.rawQuery(
      sourceId == null
          ? 'SELECT COUNT(*) AS n FROM repack_index'
          : 'SELECT COUNT(*) AS n FROM repack_index WHERE source_id = ?',
      sourceId == null ? null : [sourceId],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<DateTime?> lastIndexedAt({String? sourceId}) async {
    final rows = await _database.rawQuery(
      sourceId == null
          ? 'SELECT MAX(indexed_at) AS t FROM repack_index'
          : 'SELECT MAX(indexed_at) AS t FROM repack_index WHERE source_id = ?',
      sourceId == null ? null : [sourceId],
    );
    final stamp = rows.first['t'] as int?;
    return stamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(stamp);
  }

  Future<void> clear() async {
    await _database.transaction((txn) async {
      await txn.delete('repack_index');
      await txn.delete('repack_index_fts');
    });
  }

  /// Deletes every row belonging to one source.
  Future<void> clearSource(String sourceId) async {
    await _database.transaction((txn) async {
      await txn.delete('repack_index', where: 'source_id = ?', whereArgs: [sourceId]);
      await txn.delete('repack_index_fts');
    });
  }

  /// Replaces one source's rows inside a single transaction.
  ///
  /// The whole batch is written at once so the reader never observes a
  /// half-populated index, and the search index is rebuilt afterwards rather
  /// than maintained row by row, which is markedly faster for a full sync.
  Future<int> replaceSource(
    String sourceId,
    List<IndexRecord> records, {
    int batchSize = 500,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _database.transaction((txn) async {
      await txn.delete('repack_index', where: 'source_id = ?', whereArgs: [sourceId]);
      for (var offset = 0; offset < records.length; offset += batchSize) {
        final end =
            offset + batchSize < records.length ? offset + batchSize : records.length;
        final batch = txn.batch();
        for (final record in records.sublist(offset, end)) {
          batch.insert('repack_index', {
            'source_id': record.sourceId,
            'url': record.url,
            'title': record.title,
            'title_norm': record.normalisedTitle,
            'indexed_at': now,
          });
        }
        await batch.commit(noResult: true);
      }
    });

    await _rebuildSearchIndex();
    return records.length;
  }

  /// Stores a cover image url for one listing.
  Future<void> setCoverUrl({
    required String sourceId,
    required String url,
    required String? coverUrl,
  }) async {
    await _database.update(
      'repack_index',
      {'cover_url': coverUrl},
      where: 'source_id = ? AND url = ?',
      whereArgs: [sourceId, url],
    );
  }

  /// Cached cover url for one listing, or null when it has never been fetched.
  Future<String?> coverUrl({
    required String sourceId,
    required String url,
  }) async {
    final rows = await _database.query(
      'repack_index',
      columns: ['cover_url'],
      where: 'source_id = ? AND url = ?',
      whereArgs: [sourceId, url],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['cover_url'] as String?;
  }

  /// How many listings have no cached artwork yet.
  Future<int> missingCoverCount() async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS n FROM repack_index WHERE cover_url IS NULL',
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<void> _rebuildSearchIndex() async {
    try {
      await _database.execute(
        "INSERT INTO repack_index_fts(repack_index_fts) VALUES('rebuild')",
      );
    } catch (error) {
      // FTS5 absent means search falls back to LIKE; the catalogue still works.
      stderr.writeln('Search index rebuild skipped: $error');
    }
  }

  /// Reads one page of the catalogue, optionally filtered by a search.
  Future<CataloguePage> query({
    String? search,
    String? sourceId,
    CatalogueSort sort = CatalogueSort.alphabetical,
    int limit = 120,
    int offset = 0,
    bool withCover = false,
  }) async {
    final trimmed = search?.trim() ?? '';
    final rows = trimmed.isEmpty
        ? await _plainQuery(sourceId, sort, limit, offset, withCover)
        : await _searchQuery(trimmed, sourceId, sort, limit, offset, withCover);

    final total = await count(sourceId: sourceId);
    return CataloguePage(
      records: rows.map(IndexRecord.fromMap).toList(growable: false),
      offset: offset,
      totalEntries: total,
      matchedExactSearch: rows.isNotEmpty,
    );
  }

  Future<List<Map<String, Object?>>> _plainQuery(
    String? sourceId,
    CatalogueSort sort,
    int limit,
    int offset,
    bool withCover,
  ) {
    final orderBy = switch (sort) {
      CatalogueSort.alphabetical => 'r.title_norm ASC',
      CatalogueSort.recentlyIndexed => 'r.indexed_at DESC, r.title_norm ASC',
    };
    return _database.rawQuery(
      'SELECT r.source_id, r.url, r.title'
      '${withCover ? ', r.cover_url' : ''} FROM repack_index r'
      '${sourceId == null ? '' : ' WHERE r.source_id = ?'}'
      ' ORDER BY $orderBy LIMIT ? OFFSET ?',
      <Object?>[if (sourceId != null) sourceId, limit, offset],
    );
  }

  Future<List<Map<String, Object?>>> _searchQuery(
    String search,
    String? sourceId,
    CatalogueSort sort,
    int limit,
    int offset,
    bool withCover,
  ) {
    final orderBy = switch (sort) {
      CatalogueSort.alphabetical => 'r.title_norm ASC',
      CatalogueSort.recentlyIndexed => 'r.indexed_at DESC, r.title_norm ASC',
    };
    return _database.rawQuery(
      'SELECT r.source_id, r.url, r.title'
      '${withCover ? ', r.cover_url' : ''}'
      ' FROM repack_index_fts f JOIN repack_index r ON r.id = f.rowid'
      ' WHERE repack_index_fts MATCH ?'
      '${sourceId == null ? '' : ' AND r.source_id = ?'}'
      ' ORDER BY $orderBy LIMIT ? OFFSET ?',
      <Object?>[buildFtsQuery(search), if (sourceId != null) sourceId, limit, offset],
    );
  }
}
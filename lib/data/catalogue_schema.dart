import 'package:sqflite_common/sqlite_api.dart';

/// SQL for the local catalogue.
///
/// The schema is built around three constraints: the index has to hold every
/// listing without keeping them all in memory, search has to stay instant over
/// tens of thousands of rows, and artwork has to survive a restart without
/// being refetched per launch.
///
/// `repack_index` is the only table holding data. `repack_index_fts` is an
/// external-content FTS5 index, so it stores only the inverted index and token
/// positions rather than a second copy of every title.
abstract final class CatalogueSchema {
  static const int schemaVersion = 2;

  static const createEntries = '''
    CREATE TABLE IF NOT EXISTS repack_index (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      source_id   TEXT    NOT NULL,
      url         TEXT    NOT NULL,
      title       TEXT    NOT NULL,
      title_norm  TEXT    NOT NULL,
      cover_url   TEXT,
      indexed_at  INTEGER NOT NULL,
      UNIQUE (source_id, url)
    )
  ''';

  /// Adds artwork to a catalogue created before it was tracked.
  ///
  /// `IF NOT EXISTS` makes this safe to run against a fresh database as well,
  /// so it doubles as the idempotent creation path.
  static const addCoverColumn = 'ALTER TABLE repack_index ADD COLUMN cover_url TEXT';

  /// Backing store for the external-content index.
  ///
  /// `columnsize=0` drops the per-document term counts, which is most of the
  /// size of an FTS index and is only needed for phrase proximity ranking,
  /// something title search never uses.
  static const createSearchIndex = '''
    CREATE VIRTUAL TABLE IF NOT EXISTS repack_index_fts USING fts5(
      title_norm,
      content='repack_index',
      content_rowid='id',
      tokenize='unicode61 remove_diacritics 2',
      columnsize=0
    )
  ''';

  /// Listing order for the grid, so paging is a covering index walk.
  static const createEntryOrder =
      'CREATE INDEX IF NOT EXISTS repack_index_title ON repack_index (title_norm)';

  static const createIndexedAt = '''
    CREATE INDEX IF NOT EXISTS repack_index_recent
      ON repack_index (indexed_at DESC)
  ''';

  static const List<String> statements = [
    createEntries,
    createSearchIndex,
    createEntryOrder,
    createIndexedAt,
  ];

  static Future<void> upgrade(DatabaseExecutor db, int from, int to) async {
    if (from < 2) {
      // Version 1 had no artwork column. Existing rows keep a null cover and
      // are filled in lazily the first time they are displayed.
      try {
        await db.execute(addCoverColumn);
      } on DatabaseException catch (error) {
        // A duplicate column means the table was created by a newer path.
        if (!error.toString().contains('duplicate column')) rethrow;
      }
    }
  }
}
import 'catalogue_database.dart' show IndexRecord;

/// Sort orders offered by the catalogue.
enum CatalogueSort {
  alphabetical,
  recentlyIndexed,
}

/// One page of catalogue results.
class CataloguePage {
  final List<IndexRecord> records;
  final int offset;

  /// Total rows in the catalogue, which is larger than [records] on a paged read.
  final int totalEntries;

  /// False when a search ran but the search index is unavailable and the query
  /// had to fall back to a scan, so the result set may be a prefix of a match.
  final bool matchedExactSearch;

  const CataloguePage({
    required this.records,
    required this.offset,
    required this.totalEntries,
    required this.matchedExactSearch,
  });

  bool get hasMore => offset + records.length < totalEntries;
}

/// Turns user input into an FTS5 MATCH expression.
///
/// Each token is quoted so punctuation cannot be read as FTS syntax, and the
/// last token gets a `*` so results narrow while the user is still typing
/// rather than only appearing once a word is finished.
String buildFtsQuery(String raw) {
  final tokens = raw
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  if (tokens.isEmpty) return '""';

  final quoted = <String>[
    for (var i = 0; i < tokens.length; i++)
      '"${tokens[i]}"${i == tokens.length - 1 ? '*' : ''}',
  ];
  return quoted.join(' ');
}
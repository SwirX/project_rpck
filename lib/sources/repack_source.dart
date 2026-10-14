import '../core/result.dart';
import '../domain/models/repack.dart';

/// One page of a site's repack index.
class IndexPage {
  final List<GameIndexEntry> entries;

  /// Token for the next page, or null when the listing is exhausted.
  final String? nextCursor;

  const IndexPage({required this.entries, this.nextCursor});
}

/// Contract every repack site implements.
///
/// The prototype hardcoded `Fitgirl` into four separate call sites, so adding a
/// second site meant editing the home page, the setup flow, the weekly update
/// and the detail page. With this interface a site is one folder under
/// `lib/sources/` and one line in the registry.
abstract interface class RepackSourceAdapter {
  /// Stable identifier used in cache keys and persisted transfer records.
  String get id;

  String get displayName;

  Uri get baseUri;

  bool get supportsMagnet;
  bool get supportsTorrentFile;
  bool get supportsDirectDownload;

  /// Fetches one page of the index.
  ///
  /// [cursor] is opaque to the caller and null for the first page.
  Future<Result<IndexPage>> fetchIndexPage({String? cursor});

  /// Fetches and normalises one repack page.
  Future<Result<Repack>> fetchRepack(Uri pageUri);

  /// Full listing, walking [fetchIndexPage] until exhausted.
  ///
  /// Concurrency is bounded per host by the injected limiter; a full sync is
  /// the point at which the prototype's `Pool(100)` would earn a block.
  Future<Result<List<GameIndexEntry>>> fetchFullIndex({
    required Future<void> Function(String title, int done, int total)? onProgress,
  });
}
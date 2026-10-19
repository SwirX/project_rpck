/// A repack held in the local catalogue, as offered to the storefront matcher.
///
/// Carries the url and source alongside the title so a matched card can be
/// navigated straight into the repack detail, rather than having the title
/// looked up again at click time.
class LocalRepack {
  final String title;
  final String url;
  final String sourceId;
  final String? coverUrl;

  const LocalRepack({
    required this.title,
    required this.url,
    required this.sourceId,
    this.coverUrl,
  });
}
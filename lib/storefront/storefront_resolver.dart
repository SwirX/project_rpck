import 'local_repack.dart';
import 'storefront_client.dart';
import 'title_matcher.dart';

/// Storefront data resolved for one local repack.
class StorefrontMatch {
  final StorefrontGame game;

  /// How closely the storefront title matched the repack title, 0..1.
  final double score;

  const StorefrontMatch({required this.game, required this.score});
}

/// Resolves a local repack to its storefront record.
///
/// The search index is not fetched on its own: the trending categories already
/// name the titles people are looking at, so a repack is matched against those
/// first and only hydrated through `appdetails` when the match is confident.
class StorefrontResolver {
  final StorefrontClient _client;
  final Map<String, StorefrontMatch> _cache;

  StorefrontResolver(this._client, {Map<String, StorefrontMatch>? cache})
      : _cache = cache ?? <String, StorefrontMatch>{};

  static const _hydrateAt = 0.9;

  /// Returns the storefront record for [repack], or null when nothing matched.
  Future<StorefrontMatch?> resolve(LocalRepack repack) async {
    final cached = _cache[repack.url];
    if (cached != null) return cached;

    final trending = await _client.trending(
      categories: const ['top_sellers', 'new_releases', 'specials'],
      perCategory: 30,
    );
    final games = trending.valueOrNull;
    if (games == null || games.isEmpty) return null;

    final match = bestLocalMatch(repack.title, [
      for (final game in games)
        LocalRepack(title: game.title, url: '${game.externalId}', sourceId: 'storefront'),
    ]);
    if (match == null) return null;

    final appId = int.tryParse(match.repack.url);
    if (appId == null) return null;

    // The title match decides whether to spend a hydration request.
    if (match.score < _hydrateAt) return null;

    final details = await _client.details(appId);
    final game = details.valueOrNull;
    if (game == null) return null;

    final resolved = StorefrontMatch(game: game, score: match.score);
    _cache[repack.url] = resolved;
    return resolved;
  }
}
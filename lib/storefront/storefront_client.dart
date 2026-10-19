import 'dart:convert';

import '../core/result.dart';

/// A storefront listing used for discovery on the catalogue home.
class StorefrontGame {
  final int? externalId;
  final String title;
  final String? shortDescription;
  final String? headerImage;
  final List<String> screenshots;
  final List<String> genres;
  final String? releaseDate;
  final int reviewCount;

  const StorefrontGame({
    required this.title,
    this.externalId,
    this.shortDescription,
    this.headerImage,
    this.screenshots = const [],
    this.genres = const [],
    this.releaseDate,
    this.reviewCount = 0,
  });

  factory StorefrontGame.fromJson(Map<String, dynamic> json) {
    return StorefrontGame(
      externalId: (json['steam_appid'] as num?)?.toInt(),
      title: (json['name'] as String?) ?? 'Unknown',
      shortDescription: json['short_description'] as String?,
      headerImage: json['header_image'] as String?,
      screenshots: [
        for (final shot in (json['screenshots'] as List? ?? const []))
          if (shot is Map && shot['path_full'] is String) shot['path_full'] as String,
      ],
      genres: [
        for (final genre in (json['genres'] as List? ?? const []))
          if (genre is Map && genre['description'] is String)
            genre['description'] as String,
      ],
      releaseDate: (json['release_date'] as Map?)?['date'] as String?,
      reviewCount:
          ((json['recommendations'] as Map?)?['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Keyless storefront discovery.
///
/// Steam's `featuredcategories` endpoint exposes real sales ranking without a
/// key or an OAuth flow, which is the only keyless trending signal available.
/// Each app id is then hydrated through `appdetails` for screenshots and
/// description.
///
/// Rate behaviour is undocumented, so the caller is expected to pass through
/// [HostRateLimiter] and cache the result rather than re-fetching per render.
class StorefrontClient {
  final Future<String?> Function(Uri uri) _fetch;

  StorefrontClient({required Future<String?> Function(Uri uri) fetch})
      : _fetch = fetch;

  static final _categories = Uri.parse(
    'https://store.steampowered.com/api/featuredcategories?cc=us&l=en',
  );

  static final _appDetails = Uri.parse(
    'https://store.steampowered.com/api/appdetails?cc=us&l=en',
  );

  /// Titles from the requested storefront categories, best seller first.
  Future<Result<List<StorefrontGame>>> trending({
    List<String> categories = const ['top_sellers'],
    int perCategory = 12,
  }) async {
    final body = await _fetch(_categories);
    if (body == null) {
      return const FailureResult(
        Failure(FailureKind.network, 'storefront categories unavailable'),
      );
    }

    final decoded = _decode(body);
    if (decoded == null) {
      return const FailureResult(
        Failure(FailureKind.parse, 'storefront response was not an object'),
      );
    }

    final games = <StorefrontGame>[];
    for (final category in categories) {
      final node = decoded[category];
      if (node is! Map) continue;
      final items = node['items'];
      if (items is! List) continue;
      for (final item in items.take(perCategory)) {
        if (item is! Map) continue;
        final id = (item['id'] as num?)?.toInt();
        final name = item['name'] as String?;
        if (id == null || name == null) continue;
        games.add(
          StorefrontGame(
            externalId: id,
            title: name,
            headerImage: item['header_image'] as String?,
          ),
        );
      }
    }
    return Success(games);
  }

  /// Fetches the full record for one app, including screenshots.
  Future<Result<StorefrontGame>> details(int appId) async {
    final uri = _appDetails.replace(
      queryParameters: {..._appDetails.queryParameters, 'appids': '$appId'},
    );
    final body = await _fetch(uri);
    if (body == null) {
      return FailureResult(
        Failure(FailureKind.network, 'details for $appId unavailable'),
      );
    }

    final decoded = _decode(body);
    // `success` is false for an unknown id and the data key is then absent.
    final node = decoded?['$appId'];
    final data = node is Map ? node['data'] : null;
    if (data is! Map<String, dynamic>) {
      return FailureResult(
        Failure(FailureKind.http, 'storefront has no record for $appId'),
      );
    }
    return Success(StorefrontGame.fromJson(data));
  }

  static Map<String, dynamic>? _decode(String body) {
    final trimmed = body.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
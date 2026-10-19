import 'dart:convert';

import '../core/result.dart';

/// One downloadable asset attached to a GitHub release.
class GitHubAsset {
  final String name;
  final Uri downloadUrl;
  final int sizeBytes;
  final String? digest;

  const GitHubAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.digest,
  });

  /// True when this asset is the build for the running platform.
  bool matchesPlatform({required bool isWindows}) {
    final name = this.name.toLowerCase();
    return isWindows ? name.endsWith('.zip') : name.endsWith('.tar.gz');
  }

  factory GitHubAsset.fromJson(Map<String, dynamic> json) {
    final url = json['browser_download_url'] as String?;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) {
      throw const FormatException('asset has no usable download url');
    }
    return GitHubAsset(
      name: json['name'] as String? ?? 'asset',
      downloadUrl: uri,
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      // GitHub serves this as "sha256:<hex>" when the digest is known.
      digest: (json['digest'] as String?)?.replaceFirst('sha256:', ''),
    );
  }
}

/// A published GitHub release.
class GitHubRelease {
  final String tag;
  final String name;
  final String notes;
  final bool isPrerelease;
  final List<GitHubAsset> assets;

  const GitHubRelease({
    required this.tag,
    required this.name,
    required this.notes,
    required this.isPrerelease,
    required this.assets,
  });

  /// Version without the leading `v`.
  String get version => tag.startsWith('v') ? tag.substring(1) : tag;

  GitHubAsset? assetFor({required bool isWindows}) {
    for (final asset in assets) {
      if (asset.matchesPlatform(isWindows: isWindows)) return asset;
    }
    return null;
  }

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String?;
    if (tag == null) {
      throw const FormatException('release has no tag');
    }
    return GitHubRelease(
      tag: tag,
      name: json['name'] as String? ?? tag,
      notes: json['body'] as String? ?? '',
      isPrerelease: json['prerelease'] as bool? ?? false,
      assets: (json['assets'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GitHubAsset.fromJson)
          .toList(growable: false),
    );
  }
}

/// Reads published releases from a GitHub repository.
///
/// Uses the public releases API, so no token is needed and no rate-limit
/// header has to be handled for an unauthenticated desktop client reading a
/// handful of times a day.
class GitHubReleaseClient {
  final Future<String?> Function(Uri uri) _fetch;

  GitHubReleaseClient({required Future<String?> Function(Uri uri) fetch})
      : _fetch = fetch;

  static Uri endpointFor(String owner, String repository) => Uri.parse(
        'https://api.github.com/repos/$owner/$repository/releases',
      );

  /// Latest non-draft, non-prerelease release carrying a matching asset.
  Future<Result<GitHubRelease>> latest({
    required String owner,
    required String repository,
    required bool isWindows,
  }) async {
    final body = await _fetch(endpointFor(owner, repository));
    if (body == null) {
      return const FailureResult(
        Failure(FailureKind.network, 'release list unavailable'),
      );
    }

    final decoded = _decodeList(body);
    if (decoded == null) {
      return const FailureResult(
        Failure(FailureKind.parse, 'release list was not readable'),
      );
    }

    for (final entry in decoded) {
      if (entry['draft'] == true || entry['prerelease'] == true) continue;
      final release = GitHubRelease.fromJson(entry);
      if (release.assetFor(isWindows: isWindows) != null) return Success(release);
    }

    return const FailureResult(
      Failure(FailureKind.http, 'no published release carries a matching build'),
    );
  }

  static List<Map<String, dynamic>>? _decodeList(String body) {
    final trimmed = body.trim();
    if (!trimmed.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is List ? decoded.whereType<Map<String, dynamic>>().toList() : null;
    } on FormatException {
      return null;
    }
  }
}
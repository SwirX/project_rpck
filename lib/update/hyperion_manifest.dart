import 'dart:convert';

import '../core/result.dart';

/// One downloadable artifact attached to a Hyperion release.
class ReleaseArtifact {
  final String label;
  final Uri url;
  final int? sizeBytes;

  /// Uppercase hex as published. Comparisons normalise case at the point of
  /// use rather than trusting the producer to be consistent.
  final String? checksumSha256;

  const ReleaseArtifact({
    required this.label,
    required this.url,
    this.sizeBytes,
    this.checksumSha256,
  });

  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['url'] as String?;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri == null) {
      throw const FormatException('release artifact has no usable url');
    }
    return ReleaseArtifact(
      label: json['label'] as String? ?? 'download',
      url: uri,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      checksumSha256: json['checksum_sha256'] as String?,
    );
  }
}

/// A single published version for one platform.
class Release {
  final String platform;
  final String version;
  final DateTime? releaseDate;
  final List<String> changelog;
  final List<ReleaseArtifact> downloads;

  const Release({
    required this.platform,
    required this.version,
    required this.changelog,
    required this.downloads,
    this.releaseDate,
  });

  factory Release.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String?;
    if (version == null) {
      throw const FormatException('release has no version');
    }
    return Release(
      platform: json['platform'] as String? ?? 'unknown',
      version: version,
      releaseDate: DateTime.tryParse(json['release_date'] as String? ?? ''),
      changelog: (json['changelog'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      downloads: (json['downloads'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReleaseArtifact.fromJson)
          .toList(growable: false),
    );
  }

  /// First artifact carrying a checksum, which is the only one worth verifying.
  ReleaseArtifact? get verifiableArtifact {
    for (final artifact in downloads) {
      if (artifact.checksumSha256 != null) return artifact;
    }
    return null;
  }
}

/// Hyperion app record. Only the fields the updater needs are modelled.
class HyperionApp {
  final String id;
  final String name;
  final String? shortDescription;
  final Map<String, String> latestVersions;
  final List<Release> releases;

  const HyperionApp({
    required this.id,
    required this.name,
    required this.latestVersions,
    required this.releases,
    this.shortDescription,
  });

  /// Newest release for [platform], or null when none is published.
  ///
  /// Hyperion keys `latest_versions` by platform and omits platforms it has no
  /// release for. An absent key means "no update", never "unknown version".
  Release? latestReleaseFor(String platform) {
    for (final release in releases) {
      if (release.platform == platform) return release;
    }
    return null;
  }

  bool hasPlatform(String platform) => latestVersions.containsKey(platform);

  static Result<HyperionApp> parse(String body) {
    try {
      final decoded = _decodeLoose(body);
      final appNode = decoded['app'];
      if (appNode is! Map<String, dynamic>) {
        return const FailureResult(
          Failure(FailureKind.parse, 'manifest has no "app" object'),
        );
      }
      return Success(
        HyperionApp(
          id: appNode['id'] as String? ?? 'unknown',
          name: appNode['name'] as String? ?? 'Unknown',
          shortDescription: appNode['short_description'] as String?,
          latestVersions: (appNode['latest_versions'] as Map? ?? const {})
              .map((key, value) => MapEntry(key.toString(), value.toString())),
          releases: (appNode['releases'] as List? ?? const {})
              .whereType<Map<String, dynamic>>()
              .map(Release.fromJson)
              .toList(growable: false),
        ),
      );
    } on FormatException catch (error) {
      return FailureResult(
        Failure(FailureKind.parse, 'manifest is not readable', cause: error),
      );
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.parse, 'manifest could not be decoded',
            cause: error),
      );
    }
  }
}

/// Decodes a body that may not be JSON at all.
///
/// A captive portal or an error page returns HTML. That has to read as "no
/// manifest" rather than escaping as an exception from inside the splash.
Map<String, dynamic> _decodeLoose(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) return const {};
  final decoded = jsonDecode(trimmed);
  return decoded is Map<String, dynamic> ? decoded : const {};
}
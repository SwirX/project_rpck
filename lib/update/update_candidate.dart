import '../core/version.dart';

/// Where an update was found.
enum UpdateChannel {
  /// The Hyperion store record.
  hyperion,

  /// A published GitHub release.
  github,
}

/// An update offered to the user, normalised across both channels.
///
/// The two channels are shaped differently: Hyperion keys releases by platform
/// and attaches a checksum, while GitHub attaches platform-named assets. Both
/// are reduced to this so the UI and the installer do not care which one won.
class AvailableUpdate {
  final UpdateChannel channel;
  final String version;
  final String notes;
  final Uri downloadUrl;

  /// Uppercase or lowercase hex as published; normalised at verification time.
  final String? checksumSha256;

  final int? sizeBytes;

  const AvailableUpdate({
    required this.channel,
    required this.version,
    required this.notes,
    required this.downloadUrl,
    this.checksumSha256,
    this.sizeBytes,
  });

  factory AvailableUpdate.fromGitHub(
    GitHubReleaseLike release,
    Uri assetUrl, {
    String? checksum,
    int? size,
  }) {
    return AvailableUpdate(
      channel: UpdateChannel.github,
      version: release.version,
      notes: release.notes,
      downloadUrl: assetUrl,
      checksumSha256: checksum,
      sizeBytes: size,
    );
  }
}

/// The minimal shape an update candidate must have.
///
/// Declared here so the channel resolvers do not depend on either concrete
/// client, which keeps the decision logic testable.
abstract interface class GitHubReleaseLike {
  String get version;
  String get notes;
}

/// Decides whether a candidate is worth offering.
///
/// Shared by both channels so a GitHub release is held to the same bar as a
/// Hyperion one: an update with no checksum is not offered, because an
/// unverifiable installer is worse than staying on the current build.
class UpdateDecision {
  static const minimumConfidence = 0.85;

  /// True when [candidate] is strictly newer than [currentVersion].
  static bool isNewer({
    required String currentVersion,
    required String candidateVersion,
  }) =>
      isNewerVersion(current: currentVersion, candidate: candidateVersion);

  /// Filters [candidates] down to the newest offerable update.
  ///
  /// Prefers Hyperion when both channels carry the same version, because it
  /// carries a publisher checksum where a GitHub asset may not.
  static AvailableUpdate? select({
    required List<AvailableUpdate> candidates,
    required String currentVersion,
  }) {
    final offerable = candidates
        .where((candidate) => candidate.downloadUrl.host.isNotEmpty)
        .where((candidate) => (candidate.checksumSha256 ?? '').isNotEmpty)
        .where((candidate) => isNewer(
          currentVersion: currentVersion,
          candidateVersion: candidate.version,
        ))
        .toList(growable: false);

    if (offerable.isEmpty) return null;

    // The newest wins, and on a tie Hyperion does, because it carries a
    // publisher checksum where a GitHub asset may not. Sorting ascending and
    // taking the last element therefore has to rank Hyperion above GitHub.
    offerable.sort((left, right) {
      final byVersion = left.version.compareTo(right.version);
      if (byVersion != 0) return byVersion;
      if (left.channel == UpdateChannel.hyperion) return 1;
      if (right.channel == UpdateChannel.hyperion) return -1;
      return 0;
    });
    return offerable.last;
  }
}

/// Parses a release list into offers for one platform.
extension GitHubOffers on List<AvailableUpdate> {
  AvailableUpdate? newestFor({required String currentVersion}) =>
      UpdateDecision.select(candidates: this, currentVersion: currentVersion);
}
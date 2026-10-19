import 'dart:io';

import '../core/result.dart';
import '../core/version.dart';
import 'hyperion_manifest.dart';

/// What the updater concluded, and why.
sealed class UpdateVerdict {
  const UpdateVerdict();
}

/// The running build is already the newest published one, or no release exists
/// for this platform.
final class UpToDate extends UpdateVerdict {
  final String? latestVersion;

  const UpToDate([this.latestVersion]);
}

/// The manifest could not be read. Never fatal.
final class ManifestUnavailable extends UpdateVerdict {
  final Failure failure;

  const ManifestUnavailable(this.failure);
}

/// A newer build exists and can be installed.
final class UpdateAvailable extends UpdateVerdict {
  final Release release;
  final ReleaseArtifact artifact;

  const UpdateAvailable(this.release, this.artifact);
}

/// Decides whether an update exists for the running platform.
class UpdateChecker {
  /// Hyperion publishes per-platform keys. Linux has no key today, so a Linux
  /// build reports UpToDate rather than guessing at the Windows artifact.
  static String platformKey() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Resolves [manifest] against [currentVersion].
  ///
  /// A release is only offered when it is strictly newer, carries a checksum,
  /// and carries at least one downloadable artifact. Anything else is reported
  /// as up to date, because offering an unverifiable installer is worse than
  /// staying put.
  static UpdateVerdict evaluate({
    required HyperionApp manifest,
    required String currentVersion,
    String? platform,
  }) {
    final key = platform ?? platformKey();
    final release = manifest.latestReleaseFor(key);
    if (release == null) return const UpToDate(null);

    if (!isNewerVersion(current: currentVersion, candidate: release.version)) {
      return UpToDate(release.version);
    }

    // Nothing to fetch means nothing to offer, regardless of how new it is.
    if (!release.isDownloadable) return UpToDate(release.version);

    final artifact = release.verifiableArtifact;
    if (artifact == null) return UpToDate(release.version);

    return UpdateAvailable(release, artifact);
  }

  /// True only where the app can replace itself with a downloaded executable.
  static bool canSelfReplace() => Platform.isWindows;
}
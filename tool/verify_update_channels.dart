// Checks the updater against the live Hyperion record and the live GitHub
// release, exactly as the app reads them.
//
//   dart run tool/verify_update_channels.dart
//
// Excluded from `flutter test` because it performs network reads.
import 'dart:io';

import 'package:project_rpck/core/http/resilient_client.dart';
import 'package:project_rpck/update/github_release_client.dart';
import 'package:project_rpck/update/hyperion_manifest.dart';
import 'package:project_rpck/update/update_candidate.dart';
import 'package:project_rpck/update/update_checker.dart';

const _userAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0 Safari/537.36';

Future<void> main() async {
  final http = ResilientClient(userAgent: _userAgent);
  Future<String?> text(Uri uri) async => (await http.getString(uri)).valueOrNull;

  stdout.writeln('== Hyperion ==');
  const hyperionUri =
      'https://hyperion.alibks.dev/api/v1/apps/prjct_rpck';
  final body = await text(Uri.parse(hyperionUri));
  if (body == null) {
    stderr.writeln('could not read the Hyperion record');
    exitCode = 1;
    return;
  }

  final app = HyperionApp.parse(body).valueOrNull!;
  stdout.writeln('  id              : ${app.id}');
  stdout.writeln('  latest_versions : ${app.latestVersions}');
  stdout.writeln('  releases        : ${app.releases.length}');

  for (final release in app.releases.take(4)) {
    stdout.writeln(
      '    ${release.version.padRight(8)} ${release.platform.padRight(8)} '
      'artifacts=${release.downloads.length}',
    );
  }

  // The record must resolve to something downloadable, even though the store
  // currently lists an artifactless duplicate first.
  final windows = app.latestReleaseFor('windows');
  stdout.writeln('  latest windows  : ${windows?.version} '
      'downloadable=${windows?.isDownloadable}');

  for (final current in <String>['1.2.0', '1.1.2', '1.0.0']) {
    final verdict = UpdateChecker.evaluate(
      manifest: app,
      currentVersion: current,
      platform: 'windows',
    );
    stdout.writeln('  from $current -> ${verdict.runtimeType}');
  }

  final linux = UpdateChecker.evaluate(
    manifest: app,
    currentVersion: '1.2.0',
    platform: 'linux',
  );
  stdout.writeln('  linux from 1.2.0 -> ${linux.runtimeType} '
      '(Hyperion has no linux key, so no update is correct)');

  stdout.writeln('');
  stdout.writeln('== GitHub releases ==');
  final github = GitHubReleaseClient(fetch: text);
  for (final isWindows in [true, false]) {
    final result = await github.latest(
      owner: 'SwirX',
      repository: 'project_rpck',
      isWindows: isWindows,
    );
    final release = result.valueOrNull;
    stdout.writeln(
      '  ${isWindows ? "windows" : "linux  "} : '
      '${release == null ? result.failureOrNull?.message : "v${release.version}"}',
    );
    if (release != null) {
      final asset = release.assetFor(isWindows: isWindows);
      stdout.writeln('      asset   : ${asset?.name}');
      stdout.writeln('      digest  : ${asset?.digest}');
    }
  }

  stdout.writeln('');
  stdout.writeln('== both channels, end to end ==');

  final candidates = <AvailableUpdate>[];

  final hyperionVerdict = UpdateChecker.evaluate(
    manifest: app,
    currentVersion: '1.1.2',
    platform: 'windows',
  );
  if (hyperionVerdict case UpdateAvailable(:final release, :final artifact)) {
    candidates.add(
      AvailableUpdate(
        channel: UpdateChannel.hyperion,
        version: release.version,
        notes: release.changelog.join('; '),
        downloadUrl: artifact.url,
        checksumSha256: artifact.checksumSha256,
        sizeBytes: artifact.sizeBytes,
      ),
    );
  }

  final githubRelease = (await github.latest(
    owner: 'SwirX',
    repository: 'project_rpck',
    isWindows: true,
  ))
      .valueOrNull;
  if (githubRelease != null) {
    final asset = githubRelease.assetFor(isWindows: true)!;
    candidates.add(
      AvailableUpdate(
        channel: UpdateChannel.github,
        version: githubRelease.version,
        notes: githubRelease.notes,
        downloadUrl: asset.downloadUrl,
        checksumSha256: asset.digest,
        sizeBytes: asset.sizeBytes,
      ),
    );
  }

  for (final current in <String>['1.1.2', '1.2.0']) {
    final picked = UpdateDecision.select(
      candidates: candidates,
      currentVersion: current,
    );
    if (picked == null) {
      stdout.writeln('  from $current -> no update offered');
      continue;
    }
    stdout.writeln(
      '  from $current -> ${picked.channel.name} v${picked.version}',
    );
    stdout.writeln('      url      : ${picked.downloadUrl}');
    stdout.writeln('      checksum : ${picked.checksumSha256 ?? 'none'}');
  }

  http.close();
}
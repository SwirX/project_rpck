import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/update/github_release_client.dart';
import 'package:project_rpck/update/update_candidate.dart';

/// Client that replays a canned API body.
GitHubReleaseClient clientFor(String body) =>
    GitHubReleaseClient(fetch: (_) async => body);

String releaseJson({
  required String tag,
  bool prerelease = false,
  bool draft = false,
  bool withLinux = true,
  bool withWindows = true,
}) {
  final assets = <Map<String, dynamic>>[
    if (withLinux)
      {
        'name': 'prjct_rpck-$tag-linux-x64.tar.gz',
        'browser_download_url': 'https://github.com/o/r/releases/download/$tag/a.tar.gz',
        'size': 12345678,
        'digest': 'sha256:AAAABBBBCCCCDDDD',
      },
    if (withWindows)
      {
        'name': 'prjct_rpck-$tag-windows-x64.zip',
        'browser_download_url': 'https://github.com/o/r/releases/download/$tag/a.zip',
        'size': 8765432,
        'digest': 'sha256:1111222233334444',
      },
  ];
  return jsonEncode([
    {
      'tag_name': tag,
      'name': 'PRJCT RPCK $tag',
      'body': 'notes for $tag',
      'prerelease': prerelease,
      'draft': draft,
      'assets': assets,
    },
  ]);
}

void main() {
  group('GitHubRelease parsing', () {
    test('reads the version without the leading v', () async {
      final release = (await clientFor(releaseJson(tag: 'v1.3.0'))
              .latest(owner: 'o', repository: 'r', isWindows: true))
          .valueOrNull!;
      expect(release.version, '1.3.0');
      expect(release.notes, contains('1.3.0'));
    });

    test('picks the windows asset on windows', () async {
      final release = (await clientFor(releaseJson(tag: 'v1.3.0'))
              .latest(owner: 'o', repository: 'r', isWindows: true))
          .valueOrNull!;
      expect(release.assetFor(isWindows: true)!.name, endsWith('.zip'));
    });

    test('picks the tarball on linux', () async {
      final release = (await clientFor(releaseJson(tag: 'v1.3.0'))
              .latest(owner: 'o', repository: 'r', isWindows: false))
          .valueOrNull!;
      expect(release.assetFor(isWindows: false)!.name, endsWith('.tar.gz'));
    });

    test('strips the digest prefix', () async {
      final release = (await clientFor(releaseJson(tag: 'v1.3.0'))
              .latest(owner: 'o', repository: 'r', isWindows: true))
          .valueOrNull!;
      expect(
        release.assetFor(isWindows: true)!.digest,
        '1111222233334444',
        reason: 'the digest belongs to the asset the platform picks',
      );
    });

    test('skips a prerelease', () async {
      final result = await clientFor(releaseJson(tag: 'v9.0.0', prerelease: true))
          .latest(owner: 'o', repository: 'r', isWindows: true);
      expect(result.isSuccess, isFalse);
    });

    test('skips a draft', () async {
      final result = await clientFor(releaseJson(tag: 'v9.0.0', draft: true))
          .latest(owner: 'o', repository: 'r', isWindows: true);
      expect(result.isSuccess, isFalse);
    });

    test('skips a release with no matching asset', () async {
      final result = await clientFor(
        releaseJson(tag: 'v9.0.0', withLinux: false, withWindows: false),
      ).latest(owner: 'o', repository: 'r', isWindows: true);
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.message, contains('matching build'));
    });

    test('surfaces a failed request as a typed failure', () async {
      final result = await GitHubReleaseClient(fetch: (_) async => null)
          .latest(owner: 'o', repository: 'r', isWindows: true);
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.network);
    });

    test('rejects a body that is not a release list', () async {
      final result = await clientFor('{"message":"Not Found"}')
          .latest(owner: 'o', repository: 'r', isWindows: true);
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.parse);
    });
  });

  group('UpdateDecision.select', () {
    AvailableUpdate offer({
      required UpdateChannel channel,
      required String version,
      String checksum = 'ABCD',
    }) =>
        AvailableUpdate(
          channel: channel,
          version: version,
          notes: '',
          downloadUrl: Uri.parse('https://example.com/$version.bin'),
          checksumSha256: checksum,
        );

    test('offers a newer version', () {
      final picked = UpdateDecision.select(
        candidates: [offer(channel: UpdateChannel.github, version: '2.0.0')],
        currentVersion: '1.2.0',
      );
      expect(picked, isNotNull);
      expect(picked!.version, '2.0.0');
    });

    test('refuses the current version', () {
      expect(
        UpdateDecision.select(
          candidates: [offer(channel: UpdateChannel.github, version: '1.2.0')],
          currentVersion: '1.2.0',
        ),
        isNull,
      );
    });

    test('refuses a downgrade', () {
      expect(
        UpdateDecision.select(
          candidates: [offer(channel: UpdateChannel.github, version: '1.0.0')],
          currentVersion: '1.2.0',
        ),
        isNull,
      );
    });

    test('refuses an update with no checksum', () {
      expect(
        UpdateDecision.select(
          candidates: [
            offer(channel: UpdateChannel.github, version: '2.0.0', checksum: ''),
          ],
          currentVersion: '1.2.0',
        ),
        isNull,
      );
    });

    test('picks the newest across channels', () {
      final picked = UpdateDecision.select(
        candidates: [
          offer(channel: UpdateChannel.github, version: '1.9.0'),
          offer(channel: UpdateChannel.hyperion, version: '2.1.0'),
        ],
        currentVersion: '1.2.0',
      );
      expect(picked!.version, '2.1.0');
    });

    test('prefers hyperion when both carry the same version', () {
      final picked = UpdateDecision.select(
        candidates: [
          offer(channel: UpdateChannel.github, version: '2.0.0'),
          offer(channel: UpdateChannel.hyperion, version: '2.0.0'),
        ],
        currentVersion: '1.2.0',
      );
      expect(picked!.channel, UpdateChannel.hyperion);
    });

    test('an empty candidate list offers nothing', () {
      expect(
        UpdateDecision.select(candidates: const [], currentVersion: '1.0.0'),
        isNull,
      );
    });
  });
}

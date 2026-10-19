import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/update/hyperion_manifest.dart';
import 'package:project_rpck/update/release_installer.dart';
import 'package:project_rpck/update/update_checker.dart';

/// Captured from GET https://hyperion.alibks.dev/api/v1/apps/prjct_rpck.
///
/// The fixture is the real payload, so a change to the store's response shape
/// surfaces here rather than in the splash screen.
String readManifestFixture() =>
    File('test/fixtures/hyperion/app.json').readAsStringSync();

void main() {
  group('HyperionApp.parse against the live payload', () {
    late HyperionApp app;

    setUpAll(() {
      final parsed = HyperionApp.parse(readManifestFixture());
      expect(parsed.isSuccess, isTrue, reason: '${parsed.failureOrNull}');
      app = parsed.valueOrNull!;
    });

    test('reads the app identity', () {
      expect(app.id, 'prjct_rpck');
      expect(app.name, 'PRJCT RPCK');
    });

    test('reads latest_versions as a platform map', () {
      expect(app.latestVersions, containsPair('windows', '1.1.2'));
    });

    test('reads every release', () {
      expect(app.releases.length, 4);
    });

    test('returns the newest release for a platform', () {
      expect(app.latestReleaseFor('windows')!.version, '1.1.2');
    });

    test('returns null for a platform with no published release', () {
      expect(app.latestReleaseFor('linux'), isNull);
      expect(app.latestReleaseFor('android'), isNull);
    });

    test('hasPlatform distinguishes absent from present', () {
      expect(app.hasPlatform('windows'), isTrue);
      expect(app.hasPlatform('linux'), isFalse);
    });

    test('reads the changelog', () {
      final newest = app.latestReleaseFor('windows')!;
      expect(newest.changelog, isNotEmpty);
      expect(newest.changelog.first, isNotEmpty);
    });

    test('reads the release date', () {
      expect(app.latestReleaseFor('windows')!.releaseDate, isNotNull);
    });

    test('picks the artifact that carries a checksum', () {
      final artifact =
          app.latestReleaseFor('windows')!.verifiableArtifact;
      expect(artifact, isNotNull);
      expect(artifact!.checksumSha256, matches(RegExp(r'^[0-9A-Fa-f]{64}$')));
    });
  });

  group('HyperionApp.parse against hostile bodies', () {
    test('rejects an empty body as a parse failure', () {
      final result = HyperionApp.parse('');
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.parse);
    });

    test('rejects an html captive portal page without throwing', () {
      final result = HyperionApp.parse('<!DOCTYPE html><html><body>hi</body></html>');
      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull!.kind, FailureKind.parse);
    });

    test('rejects json that is not an object', () {
      expect(HyperionApp.parse('[1,2,3]').isSuccess, isFalse);
    });

    test('rejects an object with no app key', () {
      expect(HyperionApp.parse('{"other":1}').isSuccess, isFalse);
    });

    test('tolerates a release with no downloads', () {
      final result = HyperionApp.parse(
        '{"app":{"id":"x","name":"X","latest_versions":{"windows":"2.0.0"},'
        '"releases":[{"platform":"windows","version":"2.0.0","downloads":[]}]}}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.latestReleaseFor('windows')!.downloads, isEmpty);
      expect(
        result.valueOrNull!.latestReleaseFor('windows')!.verifiableArtifact,
        isNull,
      );
    });

    test('tolerates a release with a null release_date', () {
      final result = HyperionApp.parse(
        '{"app":{"id":"x","name":"X","latest_versions":{},'
        '"releases":[{"platform":"windows","version":"2.0.0","release_date":null,'
        '"downloads":[]}]}}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.latestReleaseFor('windows')!.releaseDate, isNull);
    });
  });

  group('UpdateChecker.evaluate', () {
    HyperionApp manifestWith({
      required String version,
      required String platform,
      bool withChecksum = true,
    }) {
      final artifact = withChecksum
          ? '"checksum_sha256":"ABCDEF"'
          : '"size_bytes":null';
      return HyperionApp.parse(
        '{"app":{"id":"x","name":"X","latest_versions":{"$platform":"$version"},'
        '"releases":[{"platform":"$platform","version":"$version",'
        '"downloads":[{"label":"installer","url":"https://example.com/a.exe",'
        '$artifact}]}]}}',
      ).valueOrNull!;
    }

    test('offers an update when the candidate is newer', () {
      final verdict = UpdateChecker.evaluate(
        manifest: manifestWith(version: '2.0.0', platform: 'windows'),
        currentVersion: '1.1.2',
        platform: 'windows',
      );
      expect(verdict, isA<UpdateAvailable>());
      expect((verdict as UpdateAvailable).release.version, '2.0.0');
    });

    test('reports up to date when the versions match', () {
      final verdict = UpdateChecker.evaluate(
        manifest: manifestWith(version: '1.1.2', platform: 'windows'),
        currentVersion: '1.1.2',
        platform: 'windows',
      );
      expect(verdict, isA<UpToDate>());
    });

    test('reports up to date when the running build is ahead', () {
      final verdict = UpdateChecker.evaluate(
        manifest: manifestWith(version: '1.0.0', platform: 'windows'),
        currentVersion: '1.1.2',
        platform: 'windows',
      );
      expect(verdict, isA<UpToDate>());
    });

    test('reports up to date for a platform with no published release', () {
      // This is the Linux case: Hyperion publishes only a windows key, and the
      // updater must not fall back to the Windows artifact.
      final verdict = UpdateChecker.evaluate(
        manifest: manifestWith(version: '9.9.9', platform: 'windows'),
        currentVersion: '1.1.2',
        platform: 'linux',
      );
      expect(verdict, isA<UpToDate>());
      expect((verdict as UpToDate).latestVersion, isNull);
    });

    test('refuses an update whose artifact carries no checksum', () {
      final verdict = UpdateChecker.evaluate(
        manifest: manifestWith(
          version: '2.0.0',
          platform: 'windows',
          withChecksum: false,
        ),
        currentVersion: '1.1.2',
        platform: 'windows',
      );
      expect(verdict, isA<UpToDate>());
    });

    test('evaluates the live payload as up to date for the shipped version', () {
      final app = HyperionApp.parse(readManifestFixture()).valueOrNull!;
      final verdict = UpdateChecker.evaluate(
        manifest: app,
        currentVersion: '1.1.2',
        platform: 'windows',
      );
      expect(verdict, isA<UpToDate>());
    });

    test('evaluates the live payload as an update for an older build', () {
      final app = HyperionApp.parse(readManifestFixture()).valueOrNull!;
      final verdict = UpdateChecker.evaluate(
        manifest: app,
        currentVersion: '1.0.0',
        platform: 'windows',
      );
      expect(verdict, isA<UpdateAvailable>());
    });
  });

  group('ReleaseInstaller.verify', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('prjct_rpck_verify');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('accepts a matching digest regardless of case', () async {
      final file = File('${root.path}/a.bin');
      await file.writeAsString('prjct');
      final computed = (await sha256.bind(file.openRead()).first).toString();

      // Hyperion publishes the digest uppercase; the computed one is lowercase.
      expect(await ReleaseInstaller.verify(file, computed.toUpperCase()), isTrue);
      expect(await ReleaseInstaller.verify(file, computed), isTrue);
    });

    test('rejects a mismatched digest', () async {
      final file = File('${root.path}/b.bin');
      await file.writeAsString('tampered');
      expect(
        await ReleaseInstaller.verify(file, '00' * 32),
        isFalse,
      );
    });

    test('rejects a missing file rather than throwing', () async {
      expect(
        await ReleaseInstaller.verify(File('${root.path}/nope'), '00' * 32),
        isFalse,
      );
    });
  });


/// Regression coverage for a store record that published a version with no
/// artifact, observed when mirroring a release into Hyperion.

  group('latestReleaseFor skips a release with no artifact', () {
    HyperionApp manifest() => HyperionApp.parse(
          '{"app":{"id":"x","name":"X","latest_versions":{"windows":"1.2.0"},'
          '"releases":['
          '{"platform":"windows","version":"1.2.0","downloads":[]},'
          '{"platform":"windows","version":"1.2.0","downloads":'
          '[{"label":"zip","url":"https://github.com/o/r/a.zip",'
          '"checksum_sha256":"ABC"}]}'
          ']}}',
        ).valueOrNull!;

    test('returns the entry that actually has a download', () {
      final release = manifest().latestReleaseFor('windows')!;
      expect(release.downloads.length, 1);
      expect(release.isDownloadable, isTrue);
    });

    test('a release with no artifact is never offered as an update', () {
      final verdict = UpdateChecker.evaluate(
        manifest: manifest(),
        currentVersion: '1.1.2',
        platform: 'windows',
      );
      expect(verdict, isA<UpdateAvailable>());
    });

    test('a lone artifactless release reports up to date', () {
      final emptyOnly = HyperionApp.parse(
        '{"app":{"id":"x","name":"X","latest_versions":{"windows":"1.2.0"},'
        '"releases":[{"platform":"windows","version":"1.2.0","downloads":[]}]}}',
      ).valueOrNull!;

      final verdict = UpdateChecker.evaluate(
        manifest: emptyOnly,
        currentVersion: '1.1.2',
        platform: 'windows',
      );
      expect(verdict, isA<UpToDate>());
    });
  });
}

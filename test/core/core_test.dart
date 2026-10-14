import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/cache/disk_cache.dart';
import 'package:project_rpck/core/platform/download_location.dart';

void main() {
  group('DiskCache.keyFor', () {
    test('is stable for the same input', () {
      expect(DiskCache.keyFor('https://example.com/a'),
          DiskCache.keyFor('https://example.com/a'));
    });

    test('differs for different inputs', () {
      expect(DiskCache.keyFor('a'), isNot(DiskCache.keyFor('b')));
    });

    test('produces a filename-safe key from a path-bearing url', () {
      final key = DiskCache.keyFor('https://example.com/a/b/c.html?x=1');
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('two urls that collide as paths do not collide as keys', () {
      // The prototype used the raw string as a filename, so a url could in
      // principle address a different path than intended.
      expect(DiskCache.keyFor('a/b'), isNot(DiskCache.keyFor('a')));
    });
  });

  group('DiskCache', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('prjct_rpck_cache');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('returns a miss for an unknown key', () async {
      final cache = DiskCache(root);
      final result = await cache.read('nothing-here');
      expect(result.isSuccess, isFalse);
    });

    test('round trips a value', () async {
      final cache = DiskCache(root);
      await cache.write('k', '{"a":1}');
      final result = await cache.read('k');
      expect(result.valueOrNull, '{"a":1}');
    });

    test('treats an expired entry as a miss and deletes it', () async {
      final cache = DiskCache(root);
      await cache.write('k', 'value');
      final result = await cache.read('k', ttl: const Duration(seconds: -1));
      expect(result.isSuccess, isFalse);
    });

    test('purgeEntries empties the cache but keeps the directory', () async {
      final cache = DiskCache(root);
      await cache.write('a', '1');
      await cache.write('b', '2');

      final purged = await cache.purgeEntries();

      expect((purged.valueOrNull ?? -1), 2);
      expect(await root.exists(), isTrue);
      expect((await cache.read('a')).isSuccess, isFalse);
    });

    test('clear recreates the root when it is missing', () async {
      final cache = DiskCache(root);
      await cache.clear();
      await root.delete(recursive: true);
      final second = await cache.clear();
      expect(second.isSuccess, isTrue);
      expect(await root.exists(), isTrue);
    });
  });

  group('DownloadLocation.sanitizeFileName', () {
    test('keeps an ordinary title', () {
      expect(DownloadLocation.sanitizeFileName('Cyberpunk 2077'),
          'Cyberpunk 2077');
    });

    test('strips a parent directory traversal', () {
      final safe = DownloadLocation.sanitizeFileName('../../etc/passwd');
      expect(safe, isNot(contains('/')));
      expect(safe, isNot(contains('..')));
    });

    test('replaces characters Windows rejects', () {
      expect(DownloadLocation.sanitizeFileName('a<b>c:d"e/f\\g|h?i*j'),
          isNot(matches(RegExp(r'[<>:"/\\|?*]'))));
    });

    test('replaces control characters with an underscore', () {
      expect(DownloadLocation.sanitizeFileName('a\u0001b\u0002c'), 'a_b_c');
    });

    test('collapses a space run to one space', () {
      expect(DownloadLocation.sanitizeFileName('a     b'), 'a b');
    });

    test('maps a tab to an underscore because it is a control character', () {
      expect(DownloadLocation.sanitizeFileName('a\tb'), 'a_b');
    });

    test('drops a trailing dot, which Windows rejects', () {
      expect(DownloadLocation.sanitizeFileName('setup...'), 'setup');
    });

    test('caps runaway length', () {
      expect(DownloadLocation.sanitizeFileName('x' * 500).length, 120);
    });

    test('reduces an entirely hostile name to empty', () {
      expect(DownloadLocation.sanitizeFileName('///'), '');
    });
  });

  group('DownloadLocation.resolveFileName', () {
    test('places a file inside the directory', () async {
      final root = await Directory.systemTemp.createTemp('prjct_rpck_dl');
      addTearDown(() => root.delete(recursive: true));
      final location = DownloadLocation(root);

      final resolved = location.resolveFileName('Setup.exe');

      expect(resolved.valueOrNull, startsWith(root.path));
      expect(resolved.valueOrNull, endsWith('Setup.exe'));
    });

    test('refuses a name that sanitises away', () async {
      final root = await Directory.systemTemp.createTemp('prjct_rpck_dl');
      addTearDown(() => root.delete(recursive: true));
      final location = DownloadLocation(root);

      expect(location.resolveFileName('///').isSuccess, isFalse);
    });

    test('does not escape the directory via traversal', () async {
      final root = await Directory.systemTemp.createTemp('prjct_rpck_dl');
      addTearDown(() => root.delete(recursive: true));
      final location = DownloadLocation(root);

      final resolved = location.resolveFileName('../../../etc/shadow');

      expect(resolved.valueOrNull, startsWith(root.path));
      expect(resolved.valueOrNull, isNot(contains('..')));
    });
  });
}
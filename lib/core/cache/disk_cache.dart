import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../result.dart';

/// Content-addressed disk cache.
///
/// The prototype keyed cache files by the raw string passed in and used
/// `existsSync`/`readAsStringSync` on the UI isolate. Keys are now hashed, so a
/// URL containing a path separator cannot escape the cache directory, and every
/// access is asynchronous.
class DiskCache {
  final Directory root;
  final Duration defaultTtl;

  DiskCache(this.root, {this.defaultTtl = const Duration(days: 14)});

  /// Builds a cache rooted in the OS-managed cache directory.
  static Future<DiskCache> inCacheDirectory({
    Duration defaultTtl = const Duration(days: 14),
  }) async {
    final directory = await getApplicationCacheDirectory();
    final root = Directory('${directory.path}/prjct_rpck');
    if (!await root.exists()) await root.create(recursive: true);
    return DiskCache(root, defaultTtl: defaultTtl);
  }

  static String keyFor(String raw) => sha256.convert(utf8.encode(raw)).toString();

  File _fileFor(String raw) => File('${root.path}/${keyFor(raw)}.json');

  Future<Result<String>> read(String key, {Duration? ttl}) async {
    try {
      final file = _fileFor(key);
      if (!await file.exists()) {
        return const FailureResult(
          Failure(FailureKind.io, 'no cached entry'),
        );
      }
      final age = DateTime.now().difference(await file.lastModified());
      if (age > (ttl ?? defaultTtl)) {
        await file.delete();
        return const FailureResult(Failure(FailureKind.io, 'entry expired'));
      }
      return Success(await file.readAsString());
    } catch (error) {
      return FailureResult(Failure(FailureKind.io, 'cache read failed',
          cause: error));
    }
  }

  Future<Result<void>> write(String key, String content) async {
    try {
      await _fileFor(key).writeAsString(content, flush: true);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(FailureKind.io, 'cache write failed',
          cause: error));
    }
  }

  Future<Result<void>> clear() async {
    try {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      await root.create(recursive: true);
      return const Success(null);
    } catch (error) {
      return FailureResult(Failure(FailureKind.io, 'cache clear failed',
          cause: error));
    }
  }

  /// Deletes every file the cache owns, leaving the directory in place.
  ///
  /// The prototype deleted the OS cache directory itself and then called
  /// `exit(0)`, which left the app with no cache root at all on next launch.
  Future<Result<int>> purgeEntries() async {
    try {
      if (!await root.exists()) return const Success(0);
      var removed = 0;
      await for (final entity in root.list()) {
        if (entity is File) {
          await entity.delete();
          removed++;
        }
      }
      return Success(removed);
    } catch (error) {
      return FailureResult(Failure(FailureKind.io, 'purge failed', cause: error));
    }
  }
}
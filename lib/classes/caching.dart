import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class Caching {
  Future<String> getCachedFile(String url) async {
    final cacheDir = await getApplicationCacheDirectory();
    final cacheFile = File('${cacheDir.path}/$url');
    if (cacheFile.existsSync()) {
      if (kDebugMode) {
        print('Cached file found at ${cacheFile.path}');
      }
      return cacheFile.readAsStringSync();
    }
    return '';
  }

  Future<void> cacheFile(String url, String content) async {
    final cacheDir = await getApplicationCacheDirectory();
    final cacheFile = File('${cacheDir.path}/$url');
    if (kDebugMode) {
      print('Caching file to ${cacheFile.path}');
    }
    await cacheFile.writeAsString(content);
  }

  Future<void> clearCache() async {
    final cacheDir = await getApplicationCacheDirectory();
    final cacheDirFile = File(cacheDir.path);
    if (cacheDirFile.existsSync()) {
      cacheDirFile.deleteSync(recursive: true);
    }
  }
}

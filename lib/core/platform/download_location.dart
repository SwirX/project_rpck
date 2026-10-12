import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../result.dart';

/// Resolves where downloaded payloads belong on each platform.
///
/// The prototype hardcoded `/storage/emulated/0/Download` for Android and threw
/// `UnsupportedError` for everything except Windows, so the Linux build
/// compiled and then failed at the first download.
class DownloadLocation {
  final Directory directory;

  const DownloadLocation(this.directory);

  /// Preferred location, falling back to app documents when the OS has no
  /// user-facing downloads folder (Android without scoped-storage permission).
  static Future<Result<DownloadLocation>> resolve({String? override}) async {
    if (override != null && override.isNotEmpty) {
      return _directoryAt(override);
    }
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          return await _directoryAt(downloads.path);
        }
      }
      final documents = await getApplicationDocumentsDirectory();
      return await _directoryAt('${documents.path}/downloads');
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.io, 'cannot resolve a download location',
            cause: error),
      );
    }
  }

  static Future<Result<DownloadLocation>> _directoryAt(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return Success(DownloadLocation(directory));
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.io, 'cannot use $path', cause: error),
      );
    }
  }

  /// Joins a filename onto the location, rejecting anything that escapes it.
  ///
  /// A repack title is attacker-influenced text and is used as a filename, so a
  /// title containing `../` must not be able to write outside the download
  /// directory.
  Result<String> resolveFileName(String candidate) {
    final cleaned = sanitizeFileName(candidate);
    if (cleaned.isEmpty) {
      return const FailureResult(
        Failure(FailureKind.io, 'filename sanitised to nothing'),
      );
    }
    return Success('${directory.path}/$cleaned');
  }

  /// Reduces arbitrary text to a single, safe path component.
  ///
  /// Directory components are dropped rather than escaped, because the caller
  /// supplies a name it wants flat. The result is empty when nothing meaningful
  /// survives, which callers must treat as a rejected name.
  static String sanitizeFileName(String raw) {
    final lastSegment = raw.split(RegExp(r'[/\\]')).last;
    final escaped = lastSegment
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        // A trailing dot or space is rejected by Windows.
        .replaceAll(RegExp(r'[. ]+$'), '')
        .replaceAll(RegExp(r'^[. ]+'), '');
    if (!RegExp('[A-Za-z0-9]').hasMatch(escaped)) return '';
    return escaped.length <= 120 ? escaped : escaped.substring(0, 120).trim();
  }
}
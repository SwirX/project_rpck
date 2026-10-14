import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../core/platform/download_location.dart';
import '../core/result.dart';
import 'hyperion_manifest.dart';

/// Downloads a release artifact and verifies it.
///
/// The prototype read the entire installer into memory with `http.get` and then
/// called `writeAsBytes`, which cannot work for a multi-megabyte binary, and
/// scraped a MediaFire page for the direct link. Neither is needed: the manifest
/// already carries a URL, and Dio streams to disk in bounded chunks.
class ReleaseInstaller {
  final Dio _dio;
  final String userAgent;

  ReleaseInstaller({required this.userAgent})
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 5),
          followRedirects: true,
          maxRedirects: 8,
        ));

  /// Streams [artifact] into the resolved download directory.
  Future<Result<File>> download(
    ReleaseArtifact artifact, {
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    final location = await DownloadLocation.resolve();
    final target = location.fold(
      (value) => value,
      (_) => null,
    );
    if (target == null) {
      return const FailureResult(
        Failure(FailureKind.io, 'no writable download directory'),
      );
    }
    final path = target.resolveFileName(fileName);
    final resolvedPath = path.fold((value) => value, (_) => null);
    if (resolvedPath == null) {
      return const FailureResult(
        Failure(FailureKind.io, 'release file name is unusable'),
      );
    }

    try {
      await _dio.download(
        artifact.url.toString(),
        resolvedPath,
        deleteOnError: true,
        options: Options(headers: {'User-Agent': userAgent}),
        onReceiveProgress: onProgress,
      );
      return Success(File(resolvedPath));
    } on DioException catch (error) {
      return FailureResult(
        Failure(FailureKind.network, 'release download failed', cause: error),
      );
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.io, 'release could not be written', cause: error),
      );
    }
  }

  /// Compares the file digest against the published checksum.
  ///
  /// [expected] arrives uppercase from Hyperion and the computed digest is
  /// lowercase, so both sides are normalised before comparison.
  static Future<bool> verify(File file, String expected) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString().toLowerCase() == expected.toLowerCase();
    } catch (error) {
      return false;
    }
  }

  void close() => _dio.close(force: true);
}
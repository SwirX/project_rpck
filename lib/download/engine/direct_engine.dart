import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/result.dart';
import '../../domain/models/source_option.dart';
import '../transfer.dart';
import 'download_engine.dart';

/// Streams a payload from an HTTP mirror straight to disk.
///
/// A split mirror is transferred part by part in the order the listing gave
/// them, because the parts only reassemble in that order. Each part resumes
/// into its own `.part` file, so an interrupted transfer continues where it
/// stopped rather than starting the whole mirror again.
class DirectEngine implements DownloadEngine {
  final Dio _client;

  DirectEngine({Dio? client})
      : _client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 5),
              followRedirects: true,
              maxRedirects: 8,
            ));

  @override
  bool supports(SourceOption option) => option is DirectOption;

  @override
  Future<Stream<Transfer>> start(Transfer transfer) async {
    final option = transfer.source as DirectOption;
    final controller = StreamController<Transfer>();

    var receivedTotal = 0;
    var overallTotal = 0;
    var currentPartIndex = 0;
    var lastSpeed = 0.0;

    void emit(TransferStatus status, {String? error}) {
      if (controller.isClosed) return;
      controller.add(
        transfer.copyWith(
          status: status,
          downloadedBytes: receivedTotal,
          totalBytes: overallTotal,
          bytesPerSecond: lastSpeed,
          errorMessage: error,
        ),
      );
    }

    emit(TransferStatus.downloading);

    unawaited(() async {
      for (final part in option.parts) {
        if (controller.isClosed) return;

        final outcome = await _downloadPart(
          url: part.url,
          savePath: '${transfer.savePath}.${part.ordinal}',
          onProgress: (chunk, total, instantaneous) {
            lastSpeed = instantaneous;
            receivedTotal += chunk;
            if (total > 0) overallTotal += total;
            emit(TransferStatus.downloading);
          },
        );

        if (outcome.isFailure) {
          emit(TransferStatus.failed, error: outcome.failureOrNull?.message);
          unawaited(controller.close());
          return;
        }
        if (controller.isClosed) return;

        currentPartIndex++;
        // A part's contribution is already folded into receivedTotal, so it is
        // not added again on the next iteration.
        if (currentPartIndex >= option.parts.length) {
          emit(TransferStatus.completed);
          unawaited(_promoteParts(controller, transfer, option));
          return;
        }
      }
    }());

    return controller.stream;
  }

  /// Renames each part file to its final name once every part has landed.
  Future<void> _promoteParts(
    StreamController<Transfer> controller,
    Transfer transfer,
    DirectOption option,
  ) async {
    for (final part in option.parts) {
      final staged = File('${transfer.savePath}.${part.ordinal}');
      if (!await staged.exists()) continue;
      final destination = File('${transfer.savePath}.part$part.ordinal');
      await staged.rename(destination.path);
    }
    unawaited(controller.close());
  }

  Future<Result<void>> _downloadPart({
    required Uri url,
    required String savePath,
    required void Function(int chunkBytes, int totalBytes, double speed) onProgress,
  }) async {
    final partial = File('$savePath.partial');
    final resumed = await partial.exists() ? await partial.length() : 0;

    var chunkedReceived = 0;
    var lastTick = DateTime.now();
    var bytesAtLastTick = resumed;
    var overallTotal = 0;

    try {
      await _client.download(
        url.toString(),
        partial.path,
        deleteOnError: false,
        options: Options(
          headers: resumed > 0
              ? <String, String>{'Range': 'bytes=$resumed-'}
              : const <String, String>{},
        ),
        onReceiveProgress: (int received, int? total) {
          final delta = received - chunkedReceived;
          chunkedReceived = received;
          if (total != null && total > 0) overallTotal = resumed + total;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTick).inMilliseconds;
          if (elapsedMs < 400) return;
          final speed =
              ((received - bytesAtLastTick) / elapsedMs * 1000).toDouble();
          bytesAtLastTick = received;
          lastTick = now;
          onProgress(delta, overallTotal, speed.clamp(0, 1 << 30).toDouble());
        },
      );
    } on DioException catch (error) {
      return FailureResult(
        Failure(FailureKind.network, 'mirror transfer failed', cause: error),
      );
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.io, 'mirror could not be written', cause: error),
      );
    }

    if (await partial.exists()) await partial.rename(savePath);
    return const Success(null);
  }
}
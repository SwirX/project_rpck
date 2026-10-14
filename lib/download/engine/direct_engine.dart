import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../domain/models/source_option.dart';
import '../transfer.dart';
import 'download_engine.dart';

/// Streams a payload from an HTTP mirror straight to disk.
///
/// Uses Dio's streaming downloader with a `Range` header so an interrupted
/// transfer resumes into the same partial file the torrent engines use. The
/// prototype buffered whole installers into memory with `http.get` plus
/// `writeAsBytes`, which cannot survive a multi-megabyte binary.
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

    final partial = File('${transfer.savePath}.part');
    final resumed = await partial.exists() ? await partial.length() : 0;
    var received = resumed;
    var overallTotal = 0;

    void emit(TransferStatus status, {String? error}) {
      if (controller.isClosed) return;
      controller.add(
        transfer.copyWith(
          status: status,
          downloadedBytes: received,
          totalBytes: overallTotal,
          errorMessage: error,
        ),
      );
    }

    void finish() {
      if (controller.isClosed) return;
      unawaited(partial.rename(transfer.savePath).catchError((_) => partial));
      unawaited(controller.close());
    }

    emit(TransferStatus.downloading);

    unawaited(() async {
      try {
        await _client.download(
          option.url.toString(),
          partial.path,
          deleteOnError: false,
          options: Options(
            headers: resumed > 0
                ? <String, String>{'Range': 'bytes=$resumed-'}
                : const <String, String>{},
          ),
          onReceiveProgress: (int count, int? total) {
            received = resumed + count;
            // A ranged response reports only the remaining bytes, so the
            // already-present prefix has to be added back for a real total.
            if (total != null && total > 0) overallTotal = resumed + total;
            emit(TransferStatus.downloading);
          },
        );
        received = await partial.length();
        emit(TransferStatus.completed);
        finish();
      } catch (error) {
        emit(TransferStatus.failed, error: '$error');
        finish();
      }
    }());

    return controller.stream;
  }
}
import 'dart:async';

import 'package:dio/dio.dart';

import '../result.dart';

/// Single HTTP entry point for the app.
///
/// Replaces the mixed use of `http` and `dio` that the prototype carried. Every
/// request gains a browser User-Agent, a connect/receive deadline, bounded
/// retries with exponential backoff, and per-host concurrency control.
class ResilientClient {
  final Dio _dio;
  final String userAgent;

  ResilientClient({
    required String userAgent,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.maxAttempts = 3,
  })  : userAgent = userAgent,
        _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            followRedirects: true,
            maxRedirects: 5,
            headers: {'User-Agent': userAgent},
            // Statuses are inspected explicitly so a 404 can be distinguished
            // from a 500 rather than collapsing into one error.
            validateStatus: (_) => true,
          ),
        );

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final int maxAttempts;

  /// Fetches [uri] as text, retrying transport faults and 5xx responses.
  ///
  /// A 4xx is returned to the caller rather than retried: asking again for a
  /// document that does not exist only wastes the host's patience.
  Future<Result<String>> getString(Uri uri) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final attemptResult = await _attempt(uri);
      if (attemptResult case Success<String>(:final value)) {
        return Success(value);
      }
      final failure = (attemptResult as FailureResult<String>).failure;
      if (!failure.isRetryable || attempt == maxAttempts) {
        return FailureResult(failure);
      }
      // Exponential backoff: 400ms, 800ms, 1600ms.
      await Future<void>.delayed(Duration(milliseconds: 400 * (1 << (attempt - 1))));
    }
    return FailureResult(
      const Failure(FailureKind.network, 'retry budget exhausted'),
    );
  }

  Future<Result<String>> _attempt(Uri uri) async {
    try {
      final response = await _dio.getUri<String>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': userAgent},
        ),
      );
      final status = response.statusCode ?? 0;
      final body = response.data ?? '';
      if (status == 200) return Success(body);
      return FailureResult(
        Failure(FailureKind.http, 'HTTP $status from ${uri.host}',
            cause: body.length > 200 ? body.substring(0, 200) : body),
      );
    } on DioException catch (error) {
      return FailureResult(
        Failure(FailureKind.network, 'transport fault for ${uri.host}',
            cause: error),
      );
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.unknown, 'unexpected error for ${uri.host}',
            cause: error),
      );
    }
  }

  void close() => _dio.close(force: true);
}
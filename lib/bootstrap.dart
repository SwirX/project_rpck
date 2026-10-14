import 'dart:async';

import 'core/cache/disk_cache.dart';
import 'core/http/host_rate_limiter.dart';
import 'core/http/resilient_client.dart';
import 'core/result.dart';
import 'download/transfer_registry.dart';
import 'sources/fitgirl/fitgirl_source.dart';
import 'sources/source_registry.dart';

/// Long-lived services, built once at startup and handed down explicitly.
///
/// No service locator and no global mutable state: every screen receives the
/// pieces it needs through a constructor, which is what makes the widgets
/// testable without a running app.
class AppEnvironment {
  final ResilientClient http;
  final HostRateLimiter limiter;
  final DiskCache cache;
  final SourceRegistry sources;
  final TransferRegistry transfers;

  AppEnvironment._({
    required this.http,
    required this.limiter,
    required this.cache,
    required this.sources,
    required this.transfers,
  });

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Safari/537.36 PRJCT-RPCK/1.0';

  static Future<Result<AppEnvironment>> create() async {
    final DiskCache cache;
    try {
      cache = await DiskCache.inCacheDirectory();
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.io, 'cache directory is unusable', cause: error),
      );
    }

    final http = ResilientClient(userAgent: _userAgent);
    final limiter = HostRateLimiter(maxConcurrentPerHost: 4);

    return Success(
      AppEnvironment._(
        http: http,
        limiter: limiter,
        cache: cache,
        sources: SourceRegistry([
          FitgirlSource(
            fetch: (uri) async {
              final response = await http.getString(uri);
              return response.valueOrNull;
            },
          ),
        ]),
        transfers: TransferRegistry(),
      ),
    );
  }

  Future<void> dispose() async {
    await transfers.dispose();
    http.close();
  }
}
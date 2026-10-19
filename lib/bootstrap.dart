import 'dart:async';

import 'core/cache/disk_cache.dart';
import 'core/http/host_rate_limiter.dart';
import 'core/http/resilient_client.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/result.dart';
import 'data/artwork_service.dart';
import 'data/catalogue_database.dart';
import 'data/catalogue_repository.dart';
import 'download/transfer_registry.dart';
import 'features/onboarding/onboarding_shell.dart';
import 'sources/fitgirl/fitgirl_source.dart';
import 'sources/source_registry.dart';
import 'storefront/storefront_client.dart';

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
  final CatalogueRepository catalogue;
  final StorefrontClient storefront;
  final ArtworkService artwork;

  /// Cached at construction so the library page can render it synchronously.
  final DateTime? lastIndexedAt;

  AppEnvironment._({
    required this.http,
    required this.limiter,
    required this.cache,
    required this.sources,
    required this.transfers,
    required this.catalogue,
    required this.storefront,
    required this.artwork,
    required this.lastIndexedAt,
  });

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Safari/537.36 PRJCT-RPCK/1.0';

  static Future<Result<AppEnvironment>> create() async {
    final DiskCache cache;
    final CatalogueDatabase database;
    try {
      cache = await DiskCache.inCacheDirectory();
      // Android uses the plugin's bundled native library; desktop uses the FFI
      // driver, which needs no platform channel.
      if (!Platform.isAndroid) sqfliteFfiInit();
      database = await CatalogueDatabase.open(
        directory: (await getApplicationSupportDirectory()).path,
        factory: Platform.isAndroid ? sqflite.databaseFactory : databaseFactoryFfi,
      );
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.io, 'local storage is unusable', cause: error),
      );
    }

    final http = ResilientClient(userAgent: _userAgent);
    final limiter = HostRateLimiter(maxConcurrentPerHost: 4);

    final registry = SourceRegistry([
      FitgirlSource(
        fetch: (uri) async => (await http.getString(uri)).valueOrNull,
      ),
    ]);

    Future<String?> fetchText(Uri uri) async =>
        (await http.getString(uri)).valueOrNull;

    return Success(
      AppEnvironment._(
        http: http,
        limiter: limiter,
        cache: cache,
        sources: registry,
        transfers: TransferRegistry(),
        catalogue: CatalogueRepository(database),
        storefront: StorefrontClient(fetch: fetchText),
        artwork: ArtworkService(database: database, catalog: registry),
        lastIndexedAt: await database.lastIndexedAt(),
      ),
    );
  }

  /// Clears onboarding so the wizard runs again, keeping the catalogue.
  Future<void> resetOnboarding() =>
      OnboardingProgress.load().then((progress) => progress.reset());

  Future<void> dispose() async {
    await transfers.dispose();
    await catalogue.database.close();
    http.close();
  }
}
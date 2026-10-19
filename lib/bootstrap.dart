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
import 'download/transfer_journal.dart';
import 'download/transfer_registry.dart';
import 'features/onboarding/onboarding_shell.dart';
import 'sources/fitgirl/fitgirl_source.dart';
import 'sources/source_registry.dart';
import 'storefront/storefront_client.dart';
import 'storefront/storefront_resolver.dart';
import 'ui/app_settings.dart';
import 'ui/settings_controller.dart';

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
  final StorefrontResolver storefrontResolver;
  final ArtworkService artwork;

  /// Settings for the running session. Owned here rather than by the widget
  /// tree because the services above are built before any widget exists.
  final SettingsController settings;

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
    required this.storefrontResolver,
    required this.artwork,
    required this.settings,
    required this.lastIndexedAt,
  });

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Safari/537.36 PRJCT-RPCK/1.0';

  static Future<Result<AppEnvironment>> create() async {
    final DiskCache cache;
    final CatalogueDatabase database;
    late final Directory supportDirectory;
    try {
      cache = await DiskCache.inCacheDirectory();
      // Android uses the plugin's bundled native library; desktop uses the FFI
      // driver, which needs no platform channel.
      if (!Platform.isAndroid) sqfliteFfiInit();
      supportDirectory = await getApplicationSupportDirectory();
      database = await CatalogueDatabase.open(
        directory: supportDirectory.path,
        factory: Platform.isAndroid ? sqflite.databaseFactory : databaseFactoryFfi,
      );
    } catch (error) {
      return FailureResult(
        Failure(FailureKind.io, 'local storage is unusable', cause: error),
      );
    }

    final http = ResilientClient(userAgent: _userAgent);
    final limiter = HostRateLimiter(maxConcurrentPerHost: 4);
    final settings = SettingsController(await _loadSettings());

    Future<String?> fetchText(Uri uri) async =>
        (await http.getString(uri)).valueOrNull;

    final storefrontClient = StorefrontClient(fetch: fetchText);
    final registry = SourceRegistry([
      FitgirlSource(
        fetch: (uri) async => (await http.getString(uri)).valueOrNull,
      ),
    ]);

    return Success(
      AppEnvironment._(
        http: http,
        limiter: limiter,
        cache: cache,
        sources: registry,
        catalogue: CatalogueRepository(database),
        storefront: storefrontClient,
        storefrontResolver: StorefrontResolver(storefrontClient),
        artwork: ArtworkService(
          database: database,
          catalog: registry,
          settings: settings,
        ),
        transfers: TransferRegistry(
          settings: settings,
          journal: await TransferJournal.open(supportDirectory.path),
        ),
        settings: settings,
        lastIndexedAt: await database.lastIndexedAt(),
      ),
    );
  }

  /// Falls back to defaults when preferences cannot be read.
  ///
  /// A missing preference store is not a reason to refuse to start; the user
  /// simply gets the out-of-the-box configuration.
  static Future<AppSettings> _loadSettings() async {
    try {
      return await AppSettings.load();
    } catch (error) {
      return const AppSettings();
    }
  }

  /// Picks up transfers a previous session left unfinished.
  ///
  /// Started once the shell is on screen rather than during [create], so a
  /// resumed download reports into a UI that exists. Returns how many resumed.
  Future<int> resumeTransfers() => transfers.restorePending();

  /// Clears onboarding so the wizard runs again, keeping the catalogue.
  Future<void> resetOnboarding() =>
      OnboardingProgress.load().then((progress) => progress.reset());

  Future<void> dispose() async {
    await transfers.dispose();
    await catalogue.database.close();
    http.close();
  }
}
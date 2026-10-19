import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/domain/models/repack.dart';
import 'package:project_rpck/features/repack/repack_detail_body.dart';
import 'package:project_rpck/storefront/storefront_game.dart';
import 'package:project_rpck/ui/app_settings.dart';
import 'package:project_rpck/ui/rpck_top_bar.dart';
import 'package:project_rpck/ui/settings_controller.dart';

import 'package:project_rpck/features/repack/repack_page.dart'
    show StorefrontDetail;

/// A real `appdetails` record for one app, trimmed to the fields that matter.
/// Captured 2026-10-19. This app carries no `metacritic` and no
/// `recommendations`, which is exactly why both must be optional.
const _appId = 3415450;

Map<String, dynamic> _record() => {
      'steam_appid': _appId,
      'name': 'A Pizza Delivery',
      'type': 'game',
      'short_description': 'Deliver a pizza across a liminal world.',
      'detailed_description':
          '<h2>Game Features</h2><ul><li>Meditative Exploration</li></ul>',
      'header_image': 'https://cdn.steamstatic.com/header.jpg',
      'background': 'https://cdn.steamstatic.com/bg.jpg',
      'developers': ['Eric Osuna'],
      'publishers': ['Dolores Entertainment'],
      'genres': [
        {'id': 1, 'description': 'Indie'},
        {'id': 2, 'description': 'Adventure'},
      ],
      'categories': [
        {'id': 2, 'description': 'Single-player'},
        {'id': 1, 'description': 'Steam Achievements'},
      ],
      'platforms': {'windows': true, 'mac': false, 'linux': false},
      'release_date': {'coming_soon': false, 'date': 'Dec 04, 2025'},
      'achievements': {'total': 18},
      'required_age': 0,
      'website': 'http://example.invalid',
      'price_overview': {
        'currency': 'USD',
        'initial': 1399,
        'final': 1399,
        'discount_percent': 0,
        'final_formatted': r'$13.99',
      },
      'screenshots': [
        {
          'path_full': 'https://cdn.steamstatic.com/ss1.1920x1080.jpg',
          'path_thumbnail': 'https://cdn.steamstatic.com/ss1.600x338.jpg',
        },
        {
          'path_full': 'https://cdn.steamstatic.com/ss2.1920x1080.jpg',
          'path_thumbnail': 'https://cdn.steamstatic.com/ss2.600x338.jpg',
        },
      ],
    };

void main() {
  group('StorefrontGame.fromJson', () {
    late StorefrontGame game;

    setUp(() => game = StorefrontGame.fromJson(_record()));

    test('reads the people behind the game', () {
      expect(game.developers, ['Eric Osuna']);
      expect(game.publishers, ['Dolores Entertainment']);
    });

    test('reads genres and features separately', () {
      expect(game.genres, ['Indie', 'Adventure']);
      expect(game.categories, ['Single-player', 'Steam Achievements']);
    });

    test('reads the platform list from the availability flags', () {
      expect(game.platforms, ['Windows']);
    });

    test('reads price, achievements and age', () {
      expect(game.price, r'$13.99');
      expect(game.achievementCount, 18);
      expect(game.requiredAge, 0);
    });

    test('keeps both screenshot sizes', () {
      expect(game.screenshots.length, 2);
      expect(game.screenshots.first.full, contains('1920x1080'));
      expect(game.screenshots.first.thumbnail, contains('600x338'));
    });

    test('flattens the long description to plain text', () {
      expect(game.detailedDescription, 'Game Features\nMeditative Exploration');
      expect(game.detailedDescription, isNot(contains('<')));
    });

    test('absent optional fields cost a row, not the record', () {
      // The captured app carries neither of these.
      expect(game.metacriticScore, isNull);
      expect(game.reviewCount, 0);
    });

    test('reads a metacritic score when the store has one', () {
      final withScore = StorefrontGame.fromJson({
        ..._record(),
        'metacritic': {'score': 82},
        'recommendations': {'total': 4123},
      });
      expect(withScore.metacriticScore, 82);
      expect(withScore.reviewCount, 4123);
    });

    test('an empty record does not throw', () {
      final thin = StorefrontGame.fromJson(const {});
      expect(thin.title, 'Unknown');
      expect(thin.isThin, isTrue);
    });

    test('a screenshot with only one size still renders', () {
      final game = StorefrontGame.fromJson({
        'screenshots': [
          {'path_full': 'https://cdn.steamstatic.com/only-full.jpg'},
        ],
      });
      expect(game.screenshots.single.thumbnail,
          'https://cdn.steamstatic.com/only-full.jpg');
    });

    test('a discounted price without formatting is composed', () {
      final game = StorefrontGame.fromJson({
        'price_overview': {'currency': 'EUR', 'final': 499},
      });
      expect(game.price, 'EUR 4.99');
    });

    test('a free game has no price row', () {
      final game = StorefrontGame.fromJson({
        'price_overview': {'currency': 'USD', 'final': 0},
      });
      expect(game.price, isNull);
    });
  });

  group('RepackDetailBody', () {
    late StorefrontGame game;

    setUp(() => game = StorefrontGame.fromJson(_record()));

    Future<void> pump(WidgetTester tester, {StorefrontDetail? detail}) async {
      // A ListView only builds what is near the viewport, and the gallery and
      // description sit well below the fold on a 600px-tall surface.
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const <ThemeExtension<dynamic>>[RpckPalette.dark],
          ),
          home: AppSettingsScope(
            controller: SettingsController(),
            settings: const AppSettings(),
            child: Scaffold(
              body: RepackDetailBody(
                title: 'A Pizza Delivery',
                sourceId: 'fitgirl',
                loadingRepack: false,
                storefront: detail,
                onStartDownload: (_) {},
                repack: Repack(
                  title: 'A Pizza Delivery',
                  sourceUri: Uri.parse('https://example.invalid/g'),
                  sourceId: 'fitgirl',
                  description: 'Repack listing prose.',
                  screenshots: const [],
                  info: const {'repack_size': '1.4 GB'},
                  repackFeatures: const [],
                  sources: const [],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the storefront facts', (tester) async {
      await pump(tester, detail: StorefrontDetail(game: game, matchScore: 90));
      await tester.pump();

      expect(find.text('developer'), findsOneWidget);
      expect(find.text('Eric Osuna'), findsOneWidget);
      expect(find.text('Dolores Entertainment'), findsOneWidget);
      expect(find.text(r'$13.99'), findsOneWidget);
      expect(find.text('18'), findsWidgets);
    });

    testWidgets('shows a screenshot gallery with a count', (tester) async {
      await pump(tester, detail: StorefrontDetail(game: game, matchScore: 90));
      await tester.pump();

      expect(find.text('SCREENSHOTS (2)'), findsOneWidget);
      expect(find.byType(ScreenshotGallery), findsOneWidget);
    });

    testWidgets('prefers the storefront long description', (tester) async {
      await pump(tester, detail: StorefrontDetail(game: game, matchScore: 90));
      await tester.pump();

      expect(find.textContaining('Meditative Exploration'), findsOneWidget);
      expect(find.text('Repack listing prose.'), findsNothing);
    });

    testWidgets('falls back to the repack description', (tester) async {
      await pump(tester);
      await tester.pump();

      expect(find.text('Repack listing prose.'), findsOneWidget);
    });

    testWidgets('omits every optional block when there is no storefront',
        (tester) async {
      await pump(tester);
      await tester.pump();

      expect(find.byType(ScreenshotGallery), findsNothing);
      expect(find.byType(StorefrontFacts), findsNothing);
      expect(find.text('GAME DETAILS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a thin storefront record renders no facts panel',
        (tester) async {
      await pump(
        tester,
        detail: StorefrontDetail(game: StorefrontGame.fromJson(const {}), matchScore: 1),
      );
      await tester.pump();

      expect(find.text('GAME DETAILS'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
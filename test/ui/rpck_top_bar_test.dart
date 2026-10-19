import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/ui/rpck_top_bar.dart';

/// Wraps [child] in the app theme so the palette extension resolves.
Widget _hosted(Widget child) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<dynamic>>[RpckPalette.dark],
      ),
      home: Scaffold(body: child),
    );

void main() {
  group('RpckTopBar leading slot', () {
    testWidgets('keeps a back button against the left edge', (tester) async {
      await tester.pumpWidget(_hosted(
        RpckTopBar(
          leading: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
        ),
      ));

      final iconLeft =
          tester.renderObject<RenderBox>(find.byIcon(Icons.arrow_back_rounded))
              .localToGlobal(Offset.zero)
              .dx;

      // A leading slot stretched across the row makes IconButton centre its
      // icon, which put the arrow in the middle of the bar.
      expect(iconLeft, lessThan(80),
          reason: 'the back icon drifted away from the leading edge');
    });

    testWidgets('keeps the wordmark against the left edge', (tester) async {
      await tester.pumpWidget(_hosted(
        const RpckTopBar(leading: RpckWordmark()),
      ));

      final left = tester
          .renderObject<RenderBox>(find.byType(RpckWordmark))
          .localToGlobal(Offset.zero)
          .dx;
      expect(left, lessThan(40));
    });

    testWidgets('renders trailing actions at the right edge', (tester) async {
      await tester.pumpWidget(_hosted(
        RpckTopBar(
          leading: const RpckWordmark(),
          trailing: [
            TopBarAction(
              icon: Icons.settings_rounded,
              tooltip: 'Settings',
              onPressed: () {},
              badge: 3,
            ),
          ],
        ),
      ));

      final barWidth = tester
          .renderObject<RenderBox>(find.byType(RpckTopBar))
          .size
          .width;
      final actionRight = tester
          .renderObject<RenderBox>(find.byType(TopBarAction))
          .localToGlobal(Offset.zero)
          .dx;

      expect(actionRight, greaterThan(barWidth / 2));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('search renders beneath the title row', (tester) async {
      await tester.pumpWidget(_hosted(
        RpckTopBar(
          leading: const RpckWordmark(),
          search: const TextField(),
        ),
      ));

      final wordmark = tester.getTopLeft(find.byType(RpckWordmark));
      final field = tester.getTopLeft(find.byType(TextField));
      expect(field.dy, greaterThan(wordmark.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long wordmark does not overflow the bar', (tester) async {
      await tester.pumpWidget(_hosted(
        RpckTopBar(
          leading: const RpckWordmark(fontSize: 24),
          trailing: [
            for (final action in <(IconData, String)>[
              (Icons.search_rounded, 'Search'),
              (Icons.download_rounded, 'Downloads'),
              (Icons.settings_rounded, 'Settings'),
              (Icons.info_rounded, 'About'),
            ])
              TopBarAction(
                icon: action.$1,
                tooltip: action.$2,
                onPressed: () {},
              ),
          ],
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a narrow screen with several actions', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_hosted(
        RpckTopBar(
          leading: const RpckWordmark(fontSize: 24),
          trailing: [
            for (final action in <(IconData, String)>[
              (Icons.search_rounded, 'Search'),
              (Icons.download_rounded, 'Downloads'),
              (Icons.settings_rounded, 'Settings'),
              (Icons.info_rounded, 'About'),
              (Icons.tune_rounded, 'Filters'),
            ])
              TopBarAction(
                icon: action.$1,
                tooltip: action.$2,
                onPressed: () {},
              ),
          ],
        ),
      ));

      expect(tester.takeException(), isNull);
      // The wordmark gives way rather than pushing the actions off-screen.
      expect(
        tester.renderObject<RenderBox>(find.byType(TopBarAction).last)
            .localToGlobal(Offset.zero)
            .dx,
        lessThan(320),
      );
    });
  });
}
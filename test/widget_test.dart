import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/main.dart';

/// Advances a bounded number of frames.
///
/// `pumpAndSettle` cannot be used against the splash: it hosts a looping Lottie
/// particle layer that never reports a settled frame. The frame budget is sized
/// to outlast the three second package-info deadline the splash allows itself.
Future<void> advancePastSplash(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('renders the first-run setup gate', (tester) async {
    await tester.pumpWidget(const MyApp(firstSetup: true));
    await advancePastSplash(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Initial Setup'), findsOneWidget);
    expect(find.text('Start Setup'), findsOneWidget);
  });

  testWidgets('does not offer setup again when it already ran',
      (tester) async {
    await tester.pumpWidget(const MyApp(firstSetup: false));
    await advancePastSplash(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Initial Setup'), findsNothing);
  });

  testWidgets('survives a manifest fetch that returns nothing',
      (tester) async {
    // The splash used to throw NoSuchMethodError on `null['versions']` whenever
    // the release manifest could not be read.
    await tester.pumpWidget(const MyApp(firstSetup: true));
    await advancePastSplash(tester);

    expect(tester.takeException(), isNull);
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/result.dart';
import 'package:project_rpck/main.dart';

const _stubFailure = Failure(FailureKind.io, 'cache directory is unusable');

void main() {
  testWidgets('reports a startup failure instead of crashing',
      (tester) async {
    await tester.pumpWidget(
      const PrjctRpckApp(environment: null),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('PRJCT RPCK could not start'), findsOneWidget);
  });

  testWidgets('names the failure when one was supplied', (tester) async {
    await tester.pumpWidget(
      const PrjctRpckApp(
        environment: null,
        startupFailure: _stubFailure,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('cache directory is unusable'), findsOneWidget);
  });
}
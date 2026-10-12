import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/http/host_rate_limiter.dart';

void main() {
  group('HostRateLimiter.withSlot', () {
    test('releases the slot even when the action throws', () async {
      final limiter = HostRateLimiter(maxConcurrentPerHost: 1);

      await expectLater(
        limiter.withSlot('host', () async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );

      // If the slot leaked, the next call would spin forever.
      final result = await limiter
          .withSlot('host', () async => 'ok')
          .timeout(const Duration(seconds: 2));
      expect(result, 'ok');
    });

    test('tracks hosts independently', () async {
      final limiter = HostRateLimiter(maxConcurrentPerHost: 1);
      final results = await Future.wait([
        limiter.withSlot('a', () async => 'a'),
        limiter.withSlot('b', () async => 'b'),
      ]).timeout(const Duration(seconds: 2));
      expect(results, ['a', 'b']);
    });

    test('never exceeds the per-host ceiling', () async {
      final limiter = HostRateLimiter(maxConcurrentPerHost: 3);
      var peak = 0;
      var active = 0;

      Future<void> job() async {
        active++;
        peak = active > peak ? active : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
      }

      await limiter
          .runAll<void>(List.generate(30, (_) => job))
          .timeout(const Duration(seconds: 5));

      expect(peak, lessThanOrEqualTo(3));
    });
  });

  group('HostRateLimiter.runAll', () {
    test('preserves input order in the result list', () async {
      final limiter = HostRateLimiter(maxConcurrentPerHost: 2);
      final result = await limiter.runAll<int>(
        List.generate(10, (index) => () async {
          await Future<void>.delayed(Duration(milliseconds: index % 3));
          return index;
        }),
      );
      expect(result, List.generate(10, (index) => index));
    });

    test('completes every action', () async {
      final limiter = HostRateLimiter(maxConcurrentPerHost: 4);
      var completed = 0;
      await limiter.runAll<void>(List.generate(
        20,
        (_) => () async {
          completed++;
        },
      ));
      expect(completed, 20);
    });

    test('an empty action list resolves immediately', () async {
      final limiter = HostRateLimiter();
      expect(await limiter.runAll<int>(const []), isEmpty);
    });
  });
}
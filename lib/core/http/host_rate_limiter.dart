import 'dart:async';

/// Caps how many requests a single host may have in flight at once.
///
/// The prototype used `Pool(100)`, which opened a hundred simultaneous
/// connections to one host during a full-library sync. That is a self-inflicted
/// rate limit, not throughput. Real sites answer that with a block that outlives
/// the sync.
class HostRateLimiter {
  final Map<String, int> _inFlight = {};
  final int maxConcurrentPerHost;

  HostRateLimiter({this.maxConcurrentPerHost = 4});

  int _slotsFree(String host) => maxConcurrentPerHost - (_inFlight[host] ?? 0);

  /// Waits until the host has capacity, then runs [action] while holding a slot.
  Future<T> withSlot<T>(String host, Future<T> Function() action) async {
    while (_slotsFree(host) <= 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _inFlight[host] = (_inFlight[host] ?? 0) + 1;
    try {
      return await action();
    } finally {
      final remaining = (_inFlight[host] ?? 1) - 1;
      if (remaining <= 0) {
        _inFlight.remove(host);
      } else {
        _inFlight[host] = remaining;
      }
    }
  }

  /// Runs every [actions] with no more than [maxConcurrentPerHost] in flight.
  ///
  /// Unlike `Future.wait`, work is claimed by index rather than by draining a
  /// queue, so the result list keeps input order and no worker can block on a
  /// slot while another worker holds an idle one.
  Future<List<T>> runAll<T>(List<Future<T> Function()> actions) async {
    if (actions.isEmpty) return const [];

    final results = List<T?>.filled(actions.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < actions.length) {
        final index = nextIndex;
        nextIndex++;
        results[index] = await actions[index]();
      }
    }

    final workerCount =
        actions.length < maxConcurrentPerHost ? actions.length : maxConcurrentPerHost;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.cast<T>();
  }
}
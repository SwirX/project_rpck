import '../core/result.dart';
import 'repack_source.dart';

/// Resolves repack sources by id.
///
/// Adding a site is a folder under `lib/sources/` plus one entry here. No
/// feature code changes, because nothing outside this file names a concrete
/// adapter.
class SourceRegistry {
  final Map<String, RepackSourceAdapter> _adapters;

  SourceRegistry(Iterable<RepackSourceAdapter> adapters)
      : _adapters = {for (final adapter in adapters) adapter.id: adapter};

  List<RepackSourceAdapter> get all => _adapters.values.toList(growable: false);

  List<String> get ids => _adapters.keys.toList(growable: false);

  RepackSourceAdapter? operator [](String id) => _adapters[id];

  Future<Result<RepackSourceAdapter>> require(String id) async {
    final adapter = _adapters[id];
    if (adapter == null) {
      return FailureResult(
        Failure(FailureKind.unknown, 'no repack source registered as "$id"'),
      );
    }
    return Success(adapter);
  }
}
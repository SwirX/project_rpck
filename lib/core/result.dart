/// Failure classification shared by every layer that can fail.
///
/// Repack scraping, manifest reads and transfers all fail for the same handful
/// of reasons, and the UI needs to react differently to each. A typed failure
/// lets a caller branch on the cause instead of matching on message text.
enum FailureKind {
  /// The request never reached the host, or the connection dropped.
  network,

  /// The host answered, but not with a success status.
  http,

  /// The response arrived but did not match the expected shape.
  parse,

  /// The response shape is right but the selectors no longer resolve.
  layout,

  /// A local file or directory could not be read or written.
  io,

  /// The user or the app cancelled the operation.
  cancelled,

  /// Anything that does not fit the categories above.
  unknown,
}

class Failure implements Exception {
  final FailureKind kind;
  final String message;
  final Object? cause;

  const Failure(this.kind, this.message, {this.cause});

  bool get isRetryable =>
      kind == FailureKind.network || kind == FailureKind.http;

  @override
  String toString() =>
      'Failure(${kind.name}: $message)${cause == null ? '' : ' <- $cause'}';
}

/// Discriminated result used instead of exceptions across layer boundaries.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;

  bool get isFailure => this is FailureResult<T>;

  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        FailureResult<T>() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Success<T>() => null,
        FailureResult<T>(:final failure) => failure,
      };

  R fold<R>(R Function(T value) onSuccess, R Function(Failure failure) onFailure) {
    return switch (this) {
      Success<T>(:final value) => onSuccess(value),
      FailureResult<T>(:final failure) => onFailure(failure),
    };
  }
}

final class Success<T> extends Result<T> {
  final T value;

  const Success(this.value);
}

final class FailureResult<T> extends Result<T> {
  final Failure failure;

  const FailureResult(this.failure);
}

/// Runs [action], converting any error into a typed [FailureResult].
Future<Result<T>> guard<T>(Future<T> Function() action) async {
  try {
    return Success(await action());
  } on Failure catch (error) {
    return FailureResult(error);
  } catch (error) {
    return FailureResult(Failure(FailureKind.unknown, '$error', cause: error));
  }
}

/// Synchronous counterpart to [guard].
Result<T> guardSync<T>(T Function() action) {
  try {
    return Success(action());
  } on Failure catch (error) {
    return FailureResult(error);
  } catch (error) {
    return FailureResult(Failure(FailureKind.unknown, '$error', cause: error));
  }
}
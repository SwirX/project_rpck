/// Pure semantic-version helpers. Kept free of `dart:io` and Flutter bindings so
/// they can be exercised directly by unit tests.
library;

class SemanticVersion implements Comparable<SemanticVersion> {
  final List<int> parts;

  const SemanticVersion(this.parts);

  /// Parses `major.minor[.patch][-pre][+build]`, ignoring any build metadata.
  ///
  /// Returns null rather than throwing: a malformed manifest field must not be
  /// able to crash the updater.
  static SemanticVersion? tryParse(String raw) {
    final core = raw.split('+').first.split('-').first.trim();
    if (core.isEmpty) return null;
    final parts = <int>[];
    for (final segment in core.split('.')) {
      final value = int.tryParse(segment);
      if (value == null || value < 0) return null;
      parts.add(value);
    }
    return parts.isEmpty ? null : SemanticVersion(parts);
  }

  @override
  int compareTo(SemanticVersion other) {
    final length = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var index = 0; index < length; index++) {
      final mine = index < parts.length ? parts[index] : 0;
      final theirs = index < other.parts.length ? other.parts[index] : 0;
      if (mine != theirs) return mine.compareTo(theirs);
    }
    return 0;
  }

  bool operator >(SemanticVersion other) => compareTo(other) > 0;

  bool operator <(SemanticVersion other) => compareTo(other) < 0;

  @override
  String toString() => parts.join('.');
}

/// True when [candidate] is strictly newer than [current].
///
/// A candidate that cannot be parsed is never newer: an unreadable manifest is
/// treated as "no update" rather than as an update to an unknown version.
bool isNewerVersion({required String current, required String candidate}) {
  final mine = SemanticVersion.tryParse(current);
  final theirs = SemanticVersion.tryParse(candidate);
  if (mine == null || theirs == null) return false;
  return theirs > mine;
}
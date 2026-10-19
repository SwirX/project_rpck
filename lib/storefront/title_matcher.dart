import 'local_repack.dart';

/// Matches a storefront title against locally indexed repack titles.
///
/// Repack listings carry noise a storefront title never has: version numbers,
/// edition suffixes, "FitGirl Repack", language lists and DRM notes. So this
/// compares only the tokens that survive a conservative normalisation, and
/// scores the result on how well the storefront title is covered.
///
/// Two guards exist because live matching surfaced two specific false
/// positives:
///
/// * "Steam Machine" scored 1.0 against "Crazy Machines 3", the only shared
///   token was "machine"/"machines", rescued by edit distance. A storefront
///   title with one meaningful word is a unique name and has to match exactly.
///
/// Known limitation: titles that differ only by a sequel number, such as
/// "Modern Warfare 4" against "Modern Warfare 2", match the same franchise.
/// Separating them would mean comparing numbers, and repack listings embed
/// their own version numbers ("v2.1") that are indistinguishable from a
/// sequel. A franchise-level hint is the intended behaviour here.
abstract final class TitleMatcher {
  /// Words that describe the packaging, the publisher or filler rather than
  /// the game itself.
  static const noise = <String>{
    'repack', 'repacked', 'fitgirl', 'dodi', 'kaos', 'krew', 'rexxed',
    'steamrip', 'steamripped', 'rip', 'edition', 'editions', 'deluxe',
    'ultimate', 'premium', 'goty', 'game', 'games', 'of', 'the', 'and', 'a',
    'an', 'or', 'to', 'for', 'in', 'on', 'at', 'with', 'your', 'my', 'all',
    'from', 'by', 'is', 'dlc', 'dlcs', 'soundtrack', 'ost', 'bonus',
    'bonuses', 'update', 'patch', 'complete', 'redistributable',
  };

  /// Tokens that are only digits behind an optional `v`, e.g. "2", "1.10",
  /// "v1.10.2". These describe a build rather than the game.
  static final _versionLike = RegExp(r'^v?[0-9]+(\.[0-9]+)*$');

  /// Reduces a title to the tokens worth comparing.
  ///
  /// Punctuation becomes a separator so "Half-Life: Alyx" and "Half Life Alyx"
  /// reduce to the same tokens.
  static List<String> tokenize(String raw) {
    final cleaned = StringBuffer();
    for (final rune in raw.toLowerCase().runes) {
      final isWord = (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x61 && rune <= 0x7A);
      cleaned.writeCharCode(isWord ? rune : 0x20);
    }
    return cleaned
        .toString()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .where((token) => !noise.contains(token))
        .where((token) => !_versionLike.hasMatch(token))
        .toList(growable: false);
  }

  /// Score in 0..1, or null when the two titles are not the same game.
  ///
  /// The score is the fraction of the storefront title's tokens found in the
  /// repack title, which keeps the measure one-directional: a repack listing
  /// with many extra words still matches.
  static double? similarity(String storefrontTitle, String repackTitle) {
    final source = tokenize(storefrontTitle);
    if (source.isEmpty) return null;

    final target = tokenize(repackTitle);
    if (target.isEmpty) return null;

    final targetSet = target.toSet();

    var hits = 0;
    for (final token in source) {
      if (targetSet.contains(token)) {
        hits++;
      } else if (source.length > 1 && target.length > 1 &&
          target.any((candidate) => _isClose(token, candidate))) {
        // Fuzzy rescue is only allowed when there is more than one token on
        // each side, so a lone unique word has to match exactly.
        hits++;
      }
    }
    if (hits == 0) return null;

    final score = hits / source.length;

    // A single meaningful word that only matched by edit distance is not a
    // match: "Steam Machine" against "Crazy Machines 3" scored a perfect 1.0
    // this way.
    if (source.length == 1 && !targetSet.contains(source.single)) return null;

    return score;
  }

  /// Best match for [storefrontTitle] among [candidates], above [threshold].
  static TitleMatch? bestMatch(
    String storefrontTitle,
    Iterable<String> candidates, {
    double threshold = 0.85,
  }) {
    TitleMatch? winner;
    for (final candidate in candidates) {
      final score = similarity(storefrontTitle, candidate);
      if (score == null || score < threshold) continue;
      if (winner == null || score > winner.score) {
        winner = TitleMatch(title: candidate, score: score);
      }
    }
    return winner;
  }

  /// Edit distance in 0..1, used only to absorb small misspellings.
  static double _closeness(String left, String right) {
    final distance = _levenshtein(left, right);
    final longest = left.length > right.length ? left.length : right.length;
    if (longest == 0) return 0;
    return 1 - distance / longest;
  }

  /// A shorter token is only forgiven a small edit when it is long enough for
  /// the comparison to mean something; two-letter words collide constantly.
  static bool _isClose(String left, String right) {
    if (left.length < 5 || right.length < 5) return false;
    if ((left.length - right.length).abs() > 2) return false;
    return _closeness(left, right) >= 0.8;
  }

  static int _levenshtein(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (i) => i);
    var current = List<int>.filled(right.length + 1, 0);

    for (var i = 1; i <= left.length; i++) {
      current[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final substitution =
            left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final replacement = previous[j - 1] + substitution;
        current[j] = deletion < insertion
            ? (deletion < replacement ? deletion : replacement)
            : (insertion < replacement ? insertion : replacement);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[right.length];
  }
}

/// A repack title judged to be the same game as a storefront title.
class TitleMatch {
  final String title;
  final double score;

  const TitleMatch({required this.title, required this.score});
}

/// Best local repack for a storefront title, carrying its url and source.
///
/// The caller needs the whole row, not just the title, so a matched trending
/// card can navigate straight into the repack detail.
LocalRepackMatch? bestLocalMatch(
  String storefrontTitle,
  Iterable<LocalRepack> candidates, {
  double threshold = 0.85,
}) {
  LocalRepackMatch? winner;
  for (final candidate in candidates) {
    final score = TitleMatcher.similarity(storefrontTitle, candidate.title);
    if (score == null || score < threshold) continue;
    if (winner == null || score > winner.score) {
      winner = LocalRepackMatch(repack: candidate, score: score);
    }
  }
  return winner;
}

/// A local repack judged to be the same game as a storefront title.
class LocalRepackMatch {
  final LocalRepack repack;
  final double score;

  const LocalRepackMatch({required this.repack, required this.score});
}
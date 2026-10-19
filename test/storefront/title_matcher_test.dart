import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/storefront/local_repack.dart';
import 'package:project_rpck/storefront/title_matcher.dart';

void main() {
  group('tokenize', () {
    test('drops repack noise', () {
      expect(
        TitleMatcher.tokenize('Cyberpunk 2077 Phantom Liberty FitGirl Repack'),
        ['cyberpunk', 'phantom', 'liberty'],
      );
    });

    test('drops version numbers', () {
      expect(TitleMatcher.tokenize('Elden Ring v1.10.2'), ['elden', 'ring']);
    });

    test('drops filler words', () {
      expect(TitleMatcher.tokenize('The Witcher 3'), ['witcher']);
    });

    test('lowercases and splits on punctuation', () {
      expect(TitleMatcher.tokenize('Half-Life: Alyx'), ['half', 'life', 'alyx']);
    });

    test('keeps steam when it is part of a name', () {
      // "Steam Machine" is a title; only "SteamRip" is packaging noise.
      expect(TitleMatcher.tokenize('Steam Machine'), ['steam', 'machine']);
      expect(TitleMatcher.tokenize('Portal 2 SteamRip'), ['portal']);
    });

    test('returns nothing for a title made only of noise', () {
      expect(TitleMatcher.tokenize('FitGirl Repack'), isEmpty);
    });
  });

  group('similarity', () {
    test('matches a storefront title against a noisy repack title', () {
      expect(
        TitleMatcher.similarity(
          'Cyberpunk 2077',
          'Cyberpunk 2077 Phantom Liberty v2.1 FitGirl Repack',
        ),
        1.0,
      );
    });

    test('is one-directional: extra repack words do not hurt', () {
      expect(
        TitleMatcher.similarity('Elden Ring', 'Elden Ring Shadow of the Erdtree'),
        1.0,
      );
    });

    test('returns null when nothing is shared', () {
      expect(TitleMatcher.similarity('Cyberpunk 2077', 'Minecraft'), isNull);
    });

    test('tolerates a small misspelling when other tokens corroborate', () {
      // "elden" matches exactly; the fuzzy "cyberpunkk"/"cyberpunk" covers the
      // rest, so the score stays high enough for the default threshold. Both
      // words are long enough for edit distance to mean something.
      final score = TitleMatcher.similarity('Elden Cyberpunkk', 'Elden Cyberpunk');
      expect(score, greaterThanOrEqualTo(0.85));
    });

    test('a lone word must match exactly, misspelling included', () {
      expect(TitleMatcher.similarity('Cyberpunk', 'Cyberpunkk'), isNull);
      expect(TitleMatcher.similarity('Enshrouded', 'Enshrouded'), 1.0);
    });

    test('short words are never rescued by edit distance', () {
      // "ring"/"ringg" and "it"/"id" would collide constantly at that length.
      expect(TitleMatcher.similarity('Elden Ringg', 'Elden Ring'), 0.5);
    });

    test('a fuzzy-only match scores too low to be used', () {
      // "Steam Machine" vs "Crazy Machines 3" scored 1.0 before these guards.
      final score = TitleMatcher.similarity('Steam Machine', 'Crazy Machines 3');
      expect(score, lessThan(0.85));
    });

    test('treats a sequel-number pair as the same franchise', () {
      // Documented limitation: repack titles embed their own version numbers,
      // so a number cannot be read as a sequel discriminator.
      expect(
        TitleMatcher.similarity(
          'Call of Duty: Modern Warfare 4',
          'Call of Duty Modern Warfare 2 2 DLC',
        ),
        1.0,
      );
    });

    test('accepts when one side states a sequel and the other does not', () {
      expect(TitleMatcher.similarity('Portal 2', 'Portal'), 1.0);
    });

    test('a shared generic word alone scores too low to be used', () {
      // Only "friends" is shared, so the score is well under the threshold and
      // bestLocalMatch never returns it.
      final score = TitleMatcher.similarity(
        'Scam With Your Friends',
        'Golf With Your Friends',
      );
      expect(score, lessThan(0.85));
    });

    test('still matches a genuinely unique single-word title', () {
      expect(
        TitleMatcher.similarity('Enshrouded', 'Enshrouded Deluxe Edition'),
        1.0,
      );
    });

    test('the live Trending false positives are gone', () {
      // Both of these matched a wrong repack before the guards were added.
      expect(
        bestLocalMatch('Steam Machine', const [
          LocalRepack(
            title: 'Crazy Machines 3',
            url: 'https://example.com/a/',
            sourceId: 'fitgirl',
          ),
        ]),
        isNull,
      );
      expect(
        bestLocalMatch('Scam With Your Friends', const [
          LocalRepack(
            title: 'Golf With Your Friends Ultimate Edition',
            url: 'https://example.com/b/',
            sourceId: 'fitgirl',
          ),
        ]),
        isNull,
      );
    });
  });

  group('bestMatch', () {
    final candidates = [
      'Cyberpunk 2077 Phantom Liberty FitGirl Repack',
      'Elden Ring v1.10 FitGirl Repack',
      'Cyberpunk 2077 Update Only',
    ];

    test('picks the best scoring candidate', () {
      final match = TitleMatcher.bestMatch('Cyberpunk 2077', candidates);
      expect(match, isNotNull);
      expect(match!.score, 1.0);
    });

    test('returns null when nothing clears the threshold', () {
      expect(TitleMatcher.bestMatch('Hades', candidates), isNull);
    });

    test('rejects the live false positive', () {
      expect(TitleMatcher.bestMatch('Steam Machine', ['Crazy Machines 3']),
          isNull);
    });

    test('handles an empty candidate list', () {
      expect(TitleMatcher.bestMatch('Cyberpunk 2077', const []), isNull);
    });
  });

  group('bestLocalMatch', () {
    final locals = [
      const LocalRepack(
        title: 'Cyberpunk 2077 Phantom Liberty FitGirl Repack',
        url: 'https://example.com/cp/',
        sourceId: 'fitgirl',
      ),
      const LocalRepack(
        title: 'Crazy Machines 3',
        url: 'https://example.com/cm/',
        sourceId: 'fitgirl',
      ),
    ];

    test('a match carries the url and source for navigation', () {
      final match = bestLocalMatch('Cyberpunk 2077', locals)!;
      expect(match.repack.url, 'https://example.com/cp/');
      expect(match.repack.sourceId, 'fitgirl');
    });

    test('the live false positive yields no navigation target', () {
      expect(bestLocalMatch('Steam Machine', locals), isNull);
    });
  });
}
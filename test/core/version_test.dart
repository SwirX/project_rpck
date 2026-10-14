import 'package:flutter_test/flutter_test.dart';
import 'package:project_rpck/core/version.dart';

void main() {
  List<int> partsOf(String raw) {
    final version = SemanticVersion.tryParse(raw);
    expect(version, isNotNull, reason: 'should parse: $raw');
    return version!.parts;
  }

  group('SemanticVersion.tryParse', () {
    test('reads a three segment version', () {
      expect(partsOf('1.2.3'), [1, 2, 3]);
    });

    test('treats a missing minor and patch as zero', () {
      expect(partsOf('2'), [2]);
    });

    test('strips build metadata', () {
      expect(partsOf('1.2.3+7'), [1, 2, 3]);
    });

    test('strips a pre-release suffix', () {
      expect(partsOf('1.2.3-rc1'), [1, 2, 3]);
    });

    test('returns null for a non numeric segment', () {
      expect(SemanticVersion.tryParse('1.two.3'), isNull);
    });

    test('returns null for an empty string', () {
      expect(SemanticVersion.tryParse(''), isNull);
    });

    test('returns null for a negative segment', () {
      expect(SemanticVersion.tryParse('1.-2'), isNull);
    });
  });

  group('isNewerVersion', () {
    test('a higher minor is newer', () {
      expect(isNewerVersion(current: '1.1.2', candidate: '1.2.0'), isTrue);
    });

    test('an identical version is not newer', () {
      expect(isNewerVersion(current: '1.1.2', candidate: '1.1.2'), isFalse);
    });

    test('a downgrade is not newer', () {
      expect(isNewerVersion(current: '1.1.2', candidate: '1.1.1'), isFalse);
    });

    test('compares the major segment first', () {
      expect(isNewerVersion(current: '1.9.9', candidate: '2.0.0'), isTrue);
      expect(isNewerVersion(current: '2.0.0', candidate: '1.9.9'), isFalse);
    });

    test('1.2 is treated as equal to 1.2.0', () {
      expect(isNewerVersion(current: '1.2.0', candidate: '1.2'), isFalse);
      expect(isNewerVersion(current: '1.2', candidate: '1.2.0'), isFalse);
    });

    test('a shorter but higher minor wins over extra segments', () {
      expect(isNewerVersion(current: '1.1.2', candidate: '1.2'), isTrue);
    });

    test('an unparsable candidate never triggers an update', () {
      expect(isNewerVersion(current: '1.1.2', candidate: 'not-a-version'),
          isFalse);
    });

    test('an unparsable current never triggers an update', () {
      expect(
          isNewerVersion(current: 'unknown', candidate: '9.9.9'), isFalse);
    });
  });
}
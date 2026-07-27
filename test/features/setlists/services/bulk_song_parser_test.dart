import 'package:flutter_test/flutter_test.dart';

import 'package:bandroadie/features/setlists/models/bulk_song_row.dart';
import 'package:bandroadie/features/setlists/services/bulk_song_parser.dart';

// ============================================================================
// BULK SONG PARSER TESTS
// Regression coverage for:
// - Bug: quoted CSV fields with an internal comma corrupting the title
// - Feature: musical Key as a 5th bulk-entry column
// ============================================================================

void main() {
  final parser = BulkSongParser.instance;

  group('Comma corruption bug fix', () {
    test('quoted title with an internal comma is not split', () {
      final result = parser.parse('"John Denver","Take Me Home, Country Road"');

      expect(result.validRows, hasLength(1));
      final row = result.validRows.first;
      expect(row.artist, 'John Denver');
      expect(row.title, 'Take Me Home, Country Road');
    });

    test('internal-comma title combined with a trailing Key column', () {
      final result = parser.parse(
        '"John Denver","Take Me Home, Country Road",118,Standard,G',
      );

      expect(result.validRows, hasLength(1));
      final row = result.validRows.first;
      expect(row.artist, 'John Denver');
      expect(row.title, 'Take Me Home, Country Road');
      expect(row.bpm, 118);
      expect(row.musicalKey, 'G');
    });
  });

  group('No regression — plain comma-delimited paste', () {
    test('unquoted comma-delimited row parses as before', () {
      final result = parser.parse('Aerosmith, Eat The Rich, 123, Standard');

      expect(result.validRows, hasLength(1));
      final row = result.validRows.first;
      expect(row.artist, 'Aerosmith');
      expect(row.title, 'Eat The Rich');
      expect(row.bpm, 123);
      expect(row.tuningLabel, 'Standard');
    });
  });

  group('No regression — tab-delimited paste', () {
    test('tab-delimited row is unaffected by the comma-splitter change', () {
      final result = parser.parse('Aerosmith\tEat The Rich\t123\tStandard');

      expect(result.validRows, hasLength(1));
      final row = result.validRows.first;
      expect(row.artist, 'Aerosmith');
      expect(row.title, 'Eat The Rich');
      expect(row.bpm, 123);
      expect(row.tuningLabel, 'Standard');
    });
  });

  group('No regression — apostrophe un-escaping', () {
    test('doubled apostrophes inside a quoted field are collapsed', () {
      final result = parser.parse(
        '"Van Halen","Ain\'\'t Talkin\'\' \'\'Bout Love",133,Standard',
      );

      expect(result.validRows, hasLength(1));
      expect(result.validRows.first.title, "Ain't Talkin' 'Bout Love");
    });
  });

  group('Key column — valid values', () {
    test('recognized major key parses and normalizes', () {
      final result = parser.parse('Van Halen, Poundcake, 118, Standard, Eb');

      expect(result.validRows, hasLength(1));
      final row = result.validRows.first;
      expect(row.musicalKey, 'Eb');
      expect(row.hasWarning, isFalse);
    });

    test('minor key suffix variants all normalize to the canonical form', () {
      for (final input in ['Bm', 'B minor', 'bm', 'B min']) {
        final result = parser.parse('Artist, Song, , , $input');
        expect(
          result.validRows.first.musicalKey,
          'Bm',
          reason: 'Input "$input" should normalize to Bm',
        );
      }
    });

    test('trailing "major" suffix normalizes to the bare root', () {
      final result = parser.parse('Artist, Song, , , C major');
      expect(result.validRows.first.musicalKey, 'C');
    });
  });

  group('Key column — invalid/unknown values', () {
    test('unrecognized key is a non-fatal warning, row stays valid', () {
      final result = parser.parse('Van Halen, Poundcake, 118, Standard, Zzz');

      expect(result.validRows, hasLength(1));
      final row = result.validRows.first;
      expect(row.isValid, isTrue);
      expect(row.musicalKey, isNull);
      expect(row.warning, BulkSongValidationError.unknownKey);
      expect(row.warningMessage, 'Unknown key ignored');
    });

    test(
        'enharmonic spelling not in the canonical set is unknown (no aliasing)',
        () {
      // "Db" is not in the canonical set (only "C#" is) — must not be aliased.
      final result = parser.parse('Artist, Song, , , Db');
      expect(result.validRows.first.musicalKey, isNull);
      expect(
          result.validRows.first.warning, BulkSongValidationError.unknownKey);
    });

    test('missing Key column leaves musicalKey null with no warning', () {
      final result = parser.parse('Aerosmith, Eat The Rich, 123, Standard');
      final row = result.validRows.first;
      expect(row.musicalKey, isNull);
      expect(row.hasWarning, isFalse);
    });
  });
}

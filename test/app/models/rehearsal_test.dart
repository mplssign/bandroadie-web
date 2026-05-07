import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/models/rehearsal.dart';

void main() {
  group('Rehearsal', () {
    group('fromJson', () {
      test('parses is_potential field correctly when true', () {
        final json = {
          'id': 'test-id',
          'band_id': 'band-id',
          'date': '2026-06-01',
          'start_time': '7:00 PM',
          'end_time': '9:00 PM',
          'location': 'Studio A',
          'notes': null,
          'setlist_id': null,
          'created_at': '2026-05-01T12:00:00Z',
          'updated_at': '2026-05-01T12:00:00Z',
          'is_recurring': false,
          'recurrence_frequency': null,
          'recurrence_days': null,
          'recurrence_until': null,
          'parent_rehearsal_id': null,
          'is_potential': true,
        };

        final rehearsal = Rehearsal.fromJson(json);

        expect(rehearsal.isPotential, true);
        expect(rehearsal.id, 'test-id');
        expect(rehearsal.location, 'Studio A');
      });

      test('parses is_potential field correctly when false', () {
        final json = {
          'id': 'test-id',
          'band_id': 'band-id',
          'date': '2026-06-01',
          'start_time': '7:00 PM',
          'end_time': '9:00 PM',
          'location': 'Studio A',
          'notes': null,
          'setlist_id': null,
          'created_at': '2026-05-01T12:00:00Z',
          'updated_at': '2026-05-01T12:00:00Z',
          'is_recurring': false,
          'recurrence_frequency': null,
          'recurrence_days': null,
          'recurrence_until': null,
          'parent_rehearsal_id': null,
          'is_potential': false,
        };

        final rehearsal = Rehearsal.fromJson(json);

        expect(rehearsal.isPotential, false);
      });

      test('defaults is_potential to false when missing', () {
        final json = {
          'id': 'test-id',
          'band_id': 'band-id',
          'date': '2026-06-01',
          'start_time': '7:00 PM',
          'end_time': '9:00 PM',
          'location': 'Studio A',
          'notes': null,
          'setlist_id': null,
          'created_at': '2026-05-01T12:00:00Z',
          'updated_at': '2026-05-01T12:00:00Z',
          'is_recurring': false,
          'recurrence_frequency': null,
          'recurrence_days': null,
          'recurrence_until': null,
          'parent_rehearsal_id': null,
          // is_potential intentionally omitted
        };

        final rehearsal = Rehearsal.fromJson(json);

        expect(rehearsal.isPotential, false);
      });
    });

    group('toJson', () {
      test('includes is_potential field when true', () {
        final rehearsal = Rehearsal(
          id: 'test-id',
          bandId: 'band-id',
          date: DateTime(2026, 6, 1),
          startTime: '7:00 PM',
          endTime: '9:00 PM',
          location: 'Studio A',
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
          isPotential: true,
        );

        final json = rehearsal.toJson();

        expect(json['is_potential'], true);
        expect(json['location'], 'Studio A');
      });

      test('includes is_potential field when false', () {
        final rehearsal = Rehearsal(
          id: 'test-id',
          bandId: 'band-id',
          date: DateTime(2026, 6, 1),
          startTime: '7:00 PM',
          endTime: '9:00 PM',
          location: 'Studio A',
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
          isPotential: false,
        );

        final json = rehearsal.toJson();

        expect(json['is_potential'], false);
      });
    });
  });
}

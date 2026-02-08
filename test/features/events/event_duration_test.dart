import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/features/events/models/event_form_data.dart';
import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';

void main() {
  group('EventDuration', () {
    test('enum has all 15-minute increments from 15m to 6h', () {
      // Verify all expected durations exist
      expect(EventDuration.min15.minutes, 15);
      expect(EventDuration.min30.minutes, 30);
      expect(EventDuration.min45.minutes, 45);
      expect(EventDuration.hour1.minutes, 60);
      expect(EventDuration.hour1_15.minutes, 75);
      expect(EventDuration.hour1_30.minutes, 90);
      expect(EventDuration.hour1_45.minutes, 105);
      expect(EventDuration.hour2.minutes, 120);
      expect(EventDuration.hour2_15.minutes, 135);
      expect(EventDuration.hour2_30.minutes, 150);
      expect(EventDuration.hour2_45.minutes, 165);
      expect(EventDuration.hour3.minutes, 180);
      expect(EventDuration.hour3_15.minutes, 195);
      expect(EventDuration.hour3_30.minutes, 210);
      expect(EventDuration.hour3_45.minutes, 225);
      expect(EventDuration.hour4.minutes, 240);
      expect(EventDuration.hour4_15.minutes, 255);
      expect(EventDuration.hour4_30.minutes, 270);
      expect(EventDuration.hour4_45.minutes, 285);
      expect(EventDuration.hour5.minutes, 300);
      expect(EventDuration.hour5_15.minutes, 315);
      expect(EventDuration.hour5_30.minutes, 330);
      expect(EventDuration.hour5_45.minutes, 345);
      expect(EventDuration.hour6.minutes, 360);
    });

    test('labels are correctly formatted', () {
      expect(EventDuration.min15.label, '15m');
      expect(EventDuration.hour1.label, '1h');
      expect(EventDuration.hour1_15.label, '1h 15m');
      expect(EventDuration.hour2_30.label, '2h 30m');
    });
  });

  group('EventFormData duration inference', () {
    // These tests verify that the _inferDuration method correctly handles
    // 15-minute increments. This prevents regression of a bug where durations
    // like 2h 15m were incorrectly rounded to 2h.
    //
    // Bug context: The original implementation used hardcoded thresholds that
    // only mapped to 30-minute intervals (e.g., <= 135 returned hour2 instead
    // of hour2_15).

    test('preserves exact 15-minute increment durations when loading gig', () {
      // Create gigs with various 15-minute increment durations and verify
      // they are preserved when converted to EventFormData

      // Test 2h 15m (135 minutes) - the specific case from the bug report
      final gig2h15m = _createGigWithDuration('7:00 PM', '9:15 PM');
      final formData2h15m = EventFormData.fromGig(gig2h15m);
      expect(
        formData2h15m.duration,
        EventDuration.hour2_15,
        reason:
            '2h 15m gig should preserve hour2_15 duration, not round to hour2',
      );
      expect(formData2h15m.duration.minutes, 135);

      // Test 1h 15m (75 minutes)
      final gig1h15m = _createGigWithDuration('7:00 PM', '8:15 PM');
      final formData1h15m = EventFormData.fromGig(gig1h15m);
      expect(formData1h15m.duration, EventDuration.hour1_15);
      expect(formData1h15m.duration.minutes, 75);

      // Test 1h 45m (105 minutes)
      final gig1h45m = _createGigWithDuration('7:00 PM', '8:45 PM');
      final formData1h45m = EventFormData.fromGig(gig1h45m);
      expect(formData1h45m.duration, EventDuration.hour1_45);
      expect(formData1h45m.duration.minutes, 105);

      // Test 3h 45m (225 minutes)
      final gig3h45m = _createGigWithDuration('6:00 PM', '9:45 PM');
      final formData3h45m = EventFormData.fromGig(gig3h45m);
      expect(formData3h45m.duration, EventDuration.hour3_45);
      expect(formData3h45m.duration.minutes, 225);
    });

    test('preserves exact 30-minute increment durations', () {
      // Test 2h (120 minutes)
      final gig2h = _createGigWithDuration('7:00 PM', '9:00 PM');
      final formData2h = EventFormData.fromGig(gig2h);
      expect(formData2h.duration, EventDuration.hour2);
      expect(formData2h.duration.minutes, 120);

      // Test 2h 30m (150 minutes)
      final gig2h30m = _createGigWithDuration('7:00 PM', '9:30 PM');
      final formData2h30m = EventFormData.fromGig(gig2h30m);
      expect(formData2h30m.duration, EventDuration.hour2_30);
      expect(formData2h30m.duration.minutes, 150);
    });

    test(
      'preserves exact 15-minute increment durations when loading rehearsal',
      () {
        // Test 2h 15m for rehearsals as well
        final rehearsal2h15m = _createRehearsalWithDuration(
          '7:00 PM',
          '9:15 PM',
        );
        final formData = EventFormData.fromRehearsal(rehearsal2h15m);
        expect(
          formData.duration,
          EventDuration.hour2_15,
          reason: '2h 15m rehearsal should preserve hour2_15 duration',
        );
        expect(formData.duration.minutes, 135);
      },
    );

    test('handles edge case durations by finding closest match', () {
      // If somehow a duration of 137 minutes (2h 17m) is stored,
      // it should map to the closest value (2h 15m = 135 minutes)
      // rather than rounding to a 30-minute interval
      final gigOddDuration = _createGigWithDuration('7:00 PM', '9:17 PM');
      final formData = EventFormData.fromGig(gigOddDuration);
      // 137 minutes is closer to 135 (hour2_15) than to 150 (hour2_30)
      expect(formData.duration, EventDuration.hour2_15);
    });
  });
}

// Helper to create a Gig with specific start/end times for testing
Gig _createGigWithDuration(String startTime, String endTime) {
  final now = DateTime(2026, 2, 15);
  return Gig(
    id: 'test-gig-id',
    bandId: 'test-band-id',
    name: 'Test Gig',
    location: 'Test Venue',
    date: now,
    startTime: startTime,
    endTime: endTime,
    isPotential: false,
    requiredMemberIds: {},
    createdAt: now,
    updatedAt: now,
  );
}

// Helper to create a Rehearsal with specific start/end times for testing
Rehearsal _createRehearsalWithDuration(String startTime, String endTime) {
  final now = DateTime(2026, 2, 15);
  return Rehearsal(
    id: 'test-rehearsal-id',
    bandId: 'test-band-id',
    location: 'Test Location',
    date: now,
    startTime: startTime,
    endTime: endTime,
    isRecurring: false,
    createdAt: now,
    updatedAt: now,
  );
}

import 'package:flutter_test/flutter_test.dart';

import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/gig_date.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/features/events/events_repository.dart';
import 'package:bandroadie/features/events/models/event_form_data.dart';

final _now = DateTime(2026);

Gig _gig(DateTime date,
    {bool isPotential = false, List<DateTime> extra = const []}) {
  return Gig(
    id: 'gig-1',
    bandId: 'band-1',
    name: 'Test Gig',
    date: date,
    startTime: '7:00 PM',
    endTime: '10:00 PM',
    location: 'Venue',
    isPotential: isPotential,
    additionalDates: extra
        .map((d) => GigDate(
            id: 'gd-$d',
            gigId: 'gig-1',
            date: d,
            createdAt: _now,
            updatedAt: _now))
        .toList(),
    createdAt: _now,
    updatedAt: _now,
  );
}

Rehearsal _rehearsal(DateTime date, {bool isPotential = false}) {
  return Rehearsal(
    id: 'rehearsal-1',
    bandId: 'band-1',
    date: date,
    startTime: '7:00 PM',
    endTime: '9:00 PM',
    location: 'Practice Space',
    isPotential: isPotential,
    createdAt: _now,
    updatedAt: _now,
  );
}

EventFormData _gigForm(DateTime date,
    {bool isPotentialGig = false, List<DateTime> extra = const []}) {
  return EventFormData(
    type: EventType.gig,
    date: date,
    hour: 7,
    minutes: 0,
    isPM: true,
    duration: EventDuration.hour3,
    location: 'Venue',
    name: 'Test Gig',
    isPotentialGig: isPotentialGig,
    additionalDates: extra
        .map((d) =>
            AdditionalDateEntry(date: d, hour: 7, minutes: 0, isPM: true))
        .toList(),
  );
}

EventFormData _rehearsalForm(DateTime date, {bool isPotentialGig = false}) {
  return EventFormData(
    type: EventType.rehearsal,
    date: date,
    hour: 7,
    minutes: 0,
    isPM: true,
    duration: EventDuration.hour2,
    location: 'Practice Space',
    isPotentialGig: isPotentialGig,
  );
}

void main() {
  final d10 = DateTime(2026, 2, 10);
  final d11 = DateTime(2026, 2, 11);
  final d12 = DateTime(2026, 2, 12);
  final d15 = DateTime(2026, 2, 15);

  group('didGigSchedulingChange', () {
    test('false when date, is_potential, and additional dates match', () {
      expect(didGigSchedulingChange(_gig(d10), _gigForm(d10)), isFalse);
    });

    test('true when main date changes by one day', () {
      expect(didGigSchedulingChange(_gig(d10), _gigForm(d11)), isTrue);
    });

    test('true when is_potential flips true to false', () {
      final pre = _gig(d10, isPotential: true);
      expect(didGigSchedulingChange(pre, _gigForm(d10)), isTrue);
    });

    test('true when is_potential flips false to true', () {
      final post = _gigForm(d10, isPotentialGig: true);
      expect(didGigSchedulingChange(_gig(d10), post), isTrue);
    });

    test('false when same y/m/d but different time-of-day', () {
      final post = _gigForm(DateTime(2026, 2, 10, 12));
      expect(didGigSchedulingChange(_gig(d10), post), isFalse);
    });

    test('false when additional-date sets match (same order)', () {
      final pre = _gig(d10, isPotential: true, extra: [d12, d15]);
      final post = _gigForm(d10, isPotentialGig: true, extra: [d12, d15]);
      expect(didGigSchedulingChange(pre, post), isFalse);
    });

    test('false when additional-date sets match but reordered', () {
      final pre = _gig(d10, isPotential: true, extra: [d12, d15]);
      final post = _gigForm(d10, isPotentialGig: true, extra: [d15, d12]);
      expect(didGigSchedulingChange(pre, post), isFalse);
    });

    test('true when an additional date is added', () {
      final pre = _gig(d10, isPotential: true, extra: [d12]);
      final post = _gigForm(d10, isPotentialGig: true, extra: [d12, d15]);
      expect(didGigSchedulingChange(pre, post), isTrue);
    });

    test('true when an additional date is swapped for another', () {
      final pre = _gig(d10, isPotential: true, extra: [d12, d15]);
      final post = _gigForm(d10, isPotentialGig: true, extra: [d12, d11]);
      expect(didGigSchedulingChange(pre, post), isTrue);
    });
  });

  group('didRehearsalSchedulingChange', () {
    test('false when main date and is_potential match', () {
      expect(
        didRehearsalSchedulingChange(_rehearsal(d10), _rehearsalForm(d10)),
        isFalse,
      );
    });

    test('true when main date differs', () {
      expect(
        didRehearsalSchedulingChange(_rehearsal(d10), _rehearsalForm(d11)),
        isTrue,
      );
    });

    test('true when is_potential flips', () {
      final post = _rehearsalForm(d10, isPotentialGig: true);
      expect(didRehearsalSchedulingChange(_rehearsal(d10), post), isTrue);
    });

    test('false when same y/m/d but different time-of-day', () {
      final post = _rehearsalForm(DateTime(2026, 2, 10, 12));
      expect(didRehearsalSchedulingChange(_rehearsal(d10), post), isFalse);
    });
  });
}

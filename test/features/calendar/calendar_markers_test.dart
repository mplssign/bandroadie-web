import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/features/calendar/calendar_markers.dart';
import 'package:bandroadie/features/calendar/models/calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final date = DateTime(2026, 9, 11);
  final timestamp = DateTime(2026, 9);

  test('potential gig uses only the potential calendar marker', () {
    final gig = Gig(
      id: 'gig-1',
      bandId: 'band-1',
      name: 'Potential Gig',
      date: date,
      startTime: '19:00',
      endTime: '21:00',
      location: 'Venue',
      isPotential: true,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final event = CalendarEvent.fromGig(gig);
    final markers =
        buildCalendarMarkers(gigs: [gig], rehearsals: const [])[dayKey(date)]!;

    expect(event.isPotential, isTrue);
    expect(markers.potentialGig, isTrue);
    expect(markers.gig, isFalse);
  });

  test('potential rehearsal uses only the potential calendar marker', () {
    final rehearsal = Rehearsal(
      id: 'rehearsal-1',
      bandId: 'band-1',
      date: date,
      startTime: '18:00',
      endTime: '20:00',
      location: 'Studio',
      createdAt: timestamp,
      updatedAt: timestamp,
      isPotential: true,
    );

    final event = CalendarEvent.fromRehearsal(rehearsal);
    final markers = buildCalendarMarkers(
        gigs: const [], rehearsals: [rehearsal])[dayKey(date)]!;

    expect(event.isPotential, isTrue);
    expect(markers.potentialRehearsal, isTrue);
    expect(markers.rehearsal, isFalse);
  });
}

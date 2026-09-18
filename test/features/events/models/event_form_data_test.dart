import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/features/events/models/event_form_data.dart';

void main() {
  group('EventFormData.soundcheckTimeDisplay', () {
    test('returns formatted H:MM AM/PM string when all fields set', () {
      final formData = EventFormData(
        type: EventType.gig,
        date: DateTime(2026, 6),
        hour: 7,
        minutes: 0,
        isPM: true,
        duration: EventDuration.hour3,
        location: 'Minneapolis',
        soundcheckHour: 7,
        soundcheckMinutes: 30,
        soundcheckIsPM: true,
      );

      expect(formData.soundcheckTimeDisplay, '7:30 PM');
    });

    test('returns null when any soundcheck field is null', () {
      final formData = EventFormData(
        type: EventType.gig,
        date: DateTime(2026, 6),
        hour: 7,
        minutes: 0,
        isPM: true,
        duration: EventDuration.hour3,
        location: 'Minneapolis',
        soundcheckHour: 7,
        soundcheckIsPM: true,
      );

      expect(formData.soundcheckTimeDisplay, isNull);
    });
  });
}

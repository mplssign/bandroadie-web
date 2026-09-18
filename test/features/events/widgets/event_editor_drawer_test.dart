import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/features/events/widgets/event_editor_drawer.dart';

void main() {
  group('computeSoundcheckDefault', () {
    test('load-in set: soundcheck defaults to load-in + 1 hour', () {
      final result = computeSoundcheckDefault(
        loadInHour: 5,
        loadInMinutes: 30,
        loadInIsPM: true,
        selectedHour: 7,
        selectedMinutes: 0,
        isPM: true,
      );

      expect(result.hour, 6);
      expect(result.minutes, 30);
      expect(result.isPM, true);
    });

    test('load-in unset: soundcheck defaults to gig start - 1 hour', () {
      final result = computeSoundcheckDefault(
        loadInHour: null,
        loadInMinutes: null,
        loadInIsPM: null,
        selectedHour: 7,
        selectedMinutes: 0,
        isPM: true,
      );

      expect(result.hour, 6);
      expect(result.minutes, 0);
      expect(result.isPM, true);
    });

    test('load-in unset: wraps correctly across midnight', () {
      final result = computeSoundcheckDefault(
        loadInHour: null,
        loadInMinutes: null,
        loadInIsPM: null,
        selectedHour: 12,
        selectedMinutes: 0,
        isPM: false,
      );

      expect(result.hour, 11);
      expect(result.minutes, 0);
      expect(result.isPM, true);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/models/gig.dart';

Gig _buildGig({String? address, String? state}) {
  return Gig(
    id: 'test-id',
    bandId: 'band-id',
    name: 'Test Gig',
    date: DateTime(2026, 6, 1),
    startTime: '7:00 PM',
    endTime: '10:00 PM',
    location: 'Minneapolis',
    address: address,
    state: state,
    isPotential: false,
    createdAt: DateTime(2026, 5, 1),
    updatedAt: DateTime(2026, 5, 1),
  );
}

void main() {
  group('Gig', () {
    group('fullLocationDisplay', () {
      test('address, location, and state all present returns two lines', () {
        final gig = _buildGig(address: '123 Main St', state: 'MN');

        expect(gig.fullLocationDisplay, '123 Main St\nMinneapolis, MN');
      });

      test(
          'address blank/null with location and state present returns one line',
          () {
        final gig = _buildGig(address: null, state: 'MN');

        expect(gig.fullLocationDisplay, 'Minneapolis, MN');
      });

      test(
          'address and location present with state blank/null returns one line',
          () {
        final gig = _buildGig(address: '123 Main St', state: null);

        expect(gig.fullLocationDisplay, '123 Main St\nMinneapolis');
      });

      test(
          'address and state blank/null with only location present returns one line',
          () {
        final gig = _buildGig(address: null, state: null);

        expect(gig.fullLocationDisplay, 'Minneapolis');
      });

      test('address is whitespace-only string is treated as blank', () {
        final gig = _buildGig(address: '   ', state: 'MN');

        expect(gig.fullLocationDisplay, 'Minneapolis, MN');
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/models/gig.dart';

Gig _buildGig({String? address, String? state}) {
  return Gig(
    id: 'test-id',
    bandId: 'band-id',
    name: 'Test Gig',
    date: DateTime(2026, 6),
    startTime: '7:00 PM',
    endTime: '10:00 PM',
    location: 'Minneapolis',
    address: address,
    state: state,
    isPotential: false,
    createdAt: DateTime(2026, 5),
    updatedAt: DateTime(2026, 5),
  );
}

void main() {
  group('Gig', () {
    group('fromJson', () {
      test('parses nested gig contacts join rows', () {
        final gig = Gig.fromJson({
          'id': 'gig-id',
          'band_id': 'band-id',
          'name': 'Test Gig',
          'date': '2026-06-01',
          'start_time': '7:00 PM',
          'end_time': '10:00 PM',
          'location': 'Minneapolis',
          'is_potential': false,
          'gig_dates': const [],
          'gig_contacts': [
            {
              'contact_id': 'contact-1',
              'contacts': {
                'id': 'contact-1',
                'band_id': 'band-id',
                'name': 'Casey Booker',
                'title': 'Promoter',
                'company': 'First Ave',
                'phone': '555-111-2222',
                'email': 'casey@example.com',
                'notes': 'Prefers text',
                'created_at': '2026-05-01T12:00:00.000Z',
                'updated_at': '2026-05-02T12:00:00.000Z',
              },
            },
            {
              'contact_id': 'contact-2',
              'contacts': {
                'id': 'contact-2',
                'band_id': 'band-id',
                'name': 'Jamie Crew',
                'title': null,
                'company': 'Roadhouse',
                'phone': null,
                'email': null,
                'notes': null,
                'created_at': null,
                'updated_at': null,
              },
            },
          ],
          'created_at': '2026-05-01T12:00:00.000Z',
          'updated_at': '2026-05-02T12:00:00.000Z',
        });

        expect(gig.contacts, hasLength(2));
        expect(gig.contacts.first.id, 'contact-1');
        expect(gig.contacts.first.name, 'Casey Booker');
        expect(gig.contacts.first.company, 'First Ave');
        expect(gig.contacts.last.id, 'contact-2');
        expect(gig.contacts.last.name, 'Jamie Crew');
      });
    });

    group('fullLocationDisplay', () {
      test('address, location, and state all present returns two lines', () {
        final gig = _buildGig(address: '123 Main St', state: 'MN');

        expect(gig.fullLocationDisplay, '123 Main St\nMinneapolis, MN');
      });

      test(
          'address blank/null with location and state present returns one line',
          () {
        final gig = _buildGig(state: 'MN');

        expect(gig.fullLocationDisplay, 'Minneapolis, MN');
      });

      test(
          'address and location present with state blank/null returns one line',
          () {
        final gig = _buildGig(address: '123 Main St');

        expect(gig.fullLocationDisplay, '123 Main St\nMinneapolis');
      });

      test(
          'address and state blank/null with only location present returns one line',
          () {
        final gig = _buildGig();

        expect(gig.fullLocationDisplay, 'Minneapolis');
      });

      test('address is whitespace-only string is treated as blank', () {
        final gig = _buildGig(address: '   ', state: 'MN');

        expect(gig.fullLocationDisplay, 'Minneapolis, MN');
      });
    });
  });
}

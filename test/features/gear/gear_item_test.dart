import 'package:flutter_test/flutter_test.dart';

import 'package:bandroadie/features/gear/models/gear_item.dart';

void main() {
  group('GearOwnerType', () {
    test('fromDbValue maps known values', () {
      expect(GearOwnerType.fromDbValue('band'), GearOwnerType.band);
      expect(GearOwnerType.fromDbValue('member'), GearOwnerType.member);
    });

    test('fromDbValue falls back to band for unknown values', () {
      expect(GearOwnerType.fromDbValue('unknown'), GearOwnerType.band);
    });
  });

  group('GearItem', () {
    test('fromJson/toJson round-trip for band-owned item', () {
      final source = {
        'id': 'gear-1',
        'band_id': 'band-1',
        'name': 'PA Mixer',
        'purchased_on': '2026-01-15',
        'purchased_from': 'Roadie Supply',
        'price_cents': 129999,
        'owner_type': 'band',
        'owner_user_id': null,
        'created_by': 'user-1',
        'created_at': '2026-01-15T12:00:00.000Z',
        'updated_at': '2026-01-16T12:00:00.000Z',
      };

      final item = GearItem.fromJson(source);
      final json = item.toJson();

      expect(json['id'], source['id']);
      expect(json['band_id'], source['band_id']);
      expect(json['name'], source['name']);
      expect(json['purchased_on'], source['purchased_on']);
      expect(json['purchased_from'], source['purchased_from']);
      expect(json['price_cents'], source['price_cents']);
      expect(json['owner_type'], source['owner_type']);
      expect(json['owner_user_id'], source['owner_user_id']);
      expect(json['created_by'], source['created_by']);
    });

    test('fromJson/toJson round-trip for member-owned item', () {
      final source = {
        'id': 'gear-2',
        'band_id': 'band-1',
        'name': 'Bass Amp',
        'purchased_on': null,
        'purchased_from': null,
        'price_cents': null,
        'owner_type': 'member',
        'owner_user_id': 'user-2',
        'created_by': null,
        'created_at': '2026-02-01T08:30:00.000Z',
        'updated_at': '2026-02-01T08:30:00.000Z',
      };

      final item = GearItem.fromJson(source);
      final json = item.toJson();

      expect(json['owner_type'], 'member');
      expect(json['owner_user_id'], 'user-2');
      expect(json['purchased_on'], isNull);
      expect(json['price_cents'], isNull);
    });

    test('constructor enforces owner shape invariant', () {
      expect(
        () => GearItem(
          id: 'gear-3',
          bandId: 'band-1',
          name: 'Invalid Gear',
          ownerType: GearOwnerType.member,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

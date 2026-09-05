// Verifies that selectBand() invalidates the three band-scoped providers
// enumerated in ActiveBandNotifier._invalidateBandScopedProviders():
//   membersProvider, contactsProvider, venuesProvider.
//
// Offline approach: we prime each provider into a known non-initial error state
// by calling their null-bandId path (no Supabase needed), then trigger
// selectBand() via a seeded ActiveBandNotifier override, then assert each
// provider has been reset to its initial build() state (error == null).
// Going through selectBand() end-to-end (rather than container.invalidate()
// directly) means the test exercises the real invalidation wiring.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';
import 'package:bandroadie/features/contacts/contacts_controller.dart';
import 'package:bandroadie/features/contacts/venues_controller.dart';
import 'package:bandroadie/features/members/members_controller.dart';

// ---------------------------------------------------------------------------
// Test bands — no Supabase required.
// ---------------------------------------------------------------------------

final _band1 = Band(
  id: 'test-band-1',
  name: 'Band One',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

final _band2 = Band(
  id: 'test-band-2',
  name: 'Band Two',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// ---------------------------------------------------------------------------
// Seeded notifier — seeds userBands so selectBand()'s guard passes without
// hitting the network (loadUserBands() is never called here).
// ---------------------------------------------------------------------------

class _SeededActiveBandNotifier extends ActiveBandNotifier {
  @override
  ActiveBandState build() => ActiveBandState(
        userBands: [_band1, _band2],
        activeBand: _band1,
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ActiveBandNotifier.selectBand invalidates band-scoped providers', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer(
        overrides: [
          activeBandProvider.overrideWith(_SeededActiveBandNotifier.new),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('members, contacts, and venues providers reset to initial state',
        () async {
      // Prime each provider into a non-initial error state using the null-bandId
      // short-circuit path — no Supabase call is made for null bandId.
      await container.read(membersProvider.notifier).loadMembers(null);
      await container.read(contactsProvider.notifier).load(null);
      await container.read(venuesProvider.notifier).load(null);

      expect(container.read(membersProvider).error, equals('No band selected'));
      expect(
          container.read(contactsProvider).error, equals('No band selected'));
      expect(container.read(venuesProvider).error, equals('No band selected'));

      // Switch bands — triggers _invalidateBandScopedProviders() inside selectBand().
      await container.read(activeBandProvider.notifier).selectBand(_band2);

      // After invalidation each provider rebuilds to build()'s initial state.
      expect(container.read(membersProvider).error, isNull);
      expect(container.read(contactsProvider).error, isNull);
      expect(container.read(venuesProvider).error, isNull);
    });
  });
}

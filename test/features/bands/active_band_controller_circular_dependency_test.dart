// Regression test for the CircularDependencyError previously thrown by
// ActiveBandNotifier.selectBand() and reset() when they synchronously
// invalidated currentUserPermissionsProvider while that provider's runtime
// dependency edge on activeBandProvider was already registered (established
// as soon as something listens to currentUserPermissionsProvider, e.g.
// app_shell.dart's "Edit Band" gate).
//
// Unlike active_band_controller_invalidation_test.dart, this test must
// actively listen() to currentUserPermissionsProvider to register that edge
// before calling selectBand()/reset() — otherwise Riverpod's
// _debugAssertCanDependOn guard never fires and the test would pass for the
// wrong reason.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';
import 'package:bandroadie/features/members/permissions/band_permissions.dart';
import 'package:bandroadie/features/members/permissions/band_permissions_provider.dart';

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

void main() {
  group('ActiveBandNotifier CircularDependencyError regression', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer(
        overrides: [
          activeBandProvider.overrideWith(_SeededActiveBandNotifier.new),
          // Watches activeBandIdProvider to preserve the runtime dependency
          // edge the guard checks, without needing a Supabase mock.
          currentUserPermissionsProvider.overrideWith((ref) async {
            ref.watch(activeBandIdProvider);
            return BandPermissions.admin;
          }),
        ],
      );

      // Force the provider to build and register the dependency edge.
      container.listen<AsyncValue<BandPermissions>>(
        currentUserPermissionsProvider,
        (_, __) {},
        fireImmediately: true,
      );
    });

    tearDown(() => container.dispose());

    test('selectBand does not throw CircularDependencyError', () async {
      await expectLater(
        container.read(activeBandProvider.notifier).selectBand(_band2),
        completes,
      );

      expect(container.read(activeBandProvider).activeBand?.id, _band2.id);
      expect(container.read(activeBandIdProvider), _band2.id);
    });

    test('reset does not throw CircularDependencyError', () async {
      await expectLater(
        container.read(activeBandProvider.notifier).reset(),
        completes,
      );

      expect(container.read(activeBandProvider).activeBand, isNull);
    });
  });
}

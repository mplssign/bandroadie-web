import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bands/active_band_controller.dart';

class DemoSessionException implements Exception {
  final String message;
  DemoSessionException(this.message);
  @override
  String toString() => message;
}

class DemoSessionService {
  static Future<String> provisionAndEnter(WidgetRef ref) async {
    final client = Supabase.instance.client;
    // Capture notifier synchronously — ref becomes invalid once LoginScreen unmounts.
    final bandNotifier = ref.read(activeBandProvider.notifier);
    try {
      // Reuse a still-valid persisted anonymous session instead of minting a
      // fresh auth.uid() on every entry — a new uid defeats the RPC's dedupe
      // key and forces a full re-clone.
      final currentUser = client.auth.currentUser;
      final hasLiveAnon = client.auth.currentSession != null &&
          currentUser != null &&
          currentUser.isAnonymous == true;
      if (!hasLiveAnon) {
        await client.auth.signInAnonymously();
      }
      final result = await client.rpc('provision_demo_session');
      final bananaId =
          (result as Map<String, dynamic>)['banana_stand_band_id'] as String;
      await bandNotifier.loadAndSelectBand(bananaId);
      return bananaId;
    } on PostgrestException catch (e) {
      await Supabase.instance.client.auth.signOut();
      if (e.message.contains('demo_capacity_exceeded')) {
        throw DemoSessionException(
          "Demo's booked solid — try again in a few minutes.",
        );
      }
      throw DemoSessionException('Demo session failed: ${e.message}');
    } catch (e, st) {
      debugPrint('[DemoSession] ❌ provisionAndEnter failed: $e');
      debugPrint("[DemoSession] ❌ stacktrace: $st");
      await Supabase.instance.client.auth.signOut();
      throw DemoSessionException('Demo session failed: $e');
    }
  }

  static Future<void> exit(WidgetRef ref) async {
    final client = Supabase.instance.client;
    try {
      final response = await client.functions.invoke('exit-demo-session');
      if (response.status < 200 || response.status >= 300) {
        throw DemoSessionException(
          'Demo exit failed: HTTP ${response.status}',
        );
      }
      await client.auth.signOut();
    } catch (e) {
      throw DemoSessionException('Demo exit failed: $e');
    }
  }

  static Future<void> heartbeat() async {
    try {
      await Supabase.instance.client.rpc('heartbeat_demo_session');
    } catch (_) {
      // heartbeat failures must not crash the app
    }
  }

  /// Best-effort teardown when the app is terminating (AppLifecycleState.detached).
  /// Fire-and-forget: frees the demo slot immediately on graceful close without
  /// blocking shutdown. All errors are swallowed — the DB cron sweep is the
  /// guaranteed backstop when this signal never lands (hard-kill / crash).
  static Future<void> releaseSlotOnDetach() async {
    try {
      await Supabase.instance.client.functions.invoke('exit-demo-session');
    } catch (_) {
      // Best-effort only; cron reaps the slot if this never completes.
    }
  }

  /// Pure predicate (testable seam): release a demo slot only on true termination
  /// of an anonymous session — never on ordinary backgrounding, and never for a
  /// real (non-anonymous) user.
  static bool shouldReleaseDemoOnLifecycle(
    AppLifecycleState state, {
    required bool isAnonymous,
  }) =>
      state == AppLifecycleState.detached && isAnonymous;
}

import 'package:flutter/foundation.dart';
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
      await client.rpc('exit_demo_session');
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
}

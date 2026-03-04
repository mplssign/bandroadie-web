// ============================================================================
// BAND PERMISSIONS PROVIDER
// Riverpod provider that exposes BandPermissions for the current user
// in the active band.
//
// Flow:
//   1. Read current user's band_members.role for the active band
//   2. If role == contributor, fetch contributor_permissions row
//   3. Return BandPermissions object
//
// Default: all contributor permissions are TRUE if row is missing.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services/supabase_client.dart';
import '../../auth/auth_state_provider.dart';
import '../../bands/active_band_controller.dart';
import 'band_permissions.dart';
import 'contributor_permissions.dart';

/// Provider for current user's permissions in the active band.
/// Returns BandPermissions.admin as default (safe fallback for existing users).
///
/// Watches both [activeBandIdProvider] and [authStateProvider] so that
/// permissions are re-fetched whenever the active band OR the logged-in
/// user changes (e.g. sign-out → sign-in as a different account).
final currentUserPermissionsProvider =
    FutureProvider<BandPermissions>((ref) async {
  // Watch auth state so we re-run when user signs in/out
  final authState = ref.watch(authStateProvider);

  final bandId = ref.watch(activeBandIdProvider);
  if (bandId == null) {
    // No active band — return admin as safe fallback
    return BandPermissions.admin;
  }

  // Use the session user from auth state (reactive) instead of
  // imperatively reading supabase.auth.currentUser.
  final userId = authState.session?.user.id;
  if (userId == null) {
    return BandPermissions.admin;
  }

  try {
    // Fetch current user's role in this band
    final response = await supabase
        .from('band_members')
        .select('id, role')
        .eq('band_id', bandId)
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (response == null) {
      // Not a member of this band — return admin as fallback
      // (shouldn't happen in normal flow)
      return BandPermissions.admin;
    }

    final role = response['role'] as String? ?? 'admin';
    final memberId = response['id'] as String;

    // If contributor, fetch sub-permissions
    ContributorPermissions? subPerms;
    if (role == 'contributor') {
      try {
        final permResponse = await supabase
            .from('contributor_permissions')
            .select()
            .eq('band_member_id', memberId)
            .maybeSingle();

        if (permResponse != null) {
          subPerms = ContributorPermissions.fromJson(permResponse);
        } else {
          // No row found (RLS blocked or row missing) — fail CLOSED
          subPerms = ContributorPermissions.allDisabled;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[BandPermissions] Error fetching contributor permissions: $e',
          );
        }
        // Fail CLOSED on error — restrict contributor until permissions load
        subPerms = ContributorPermissions.allDisabled;
      }
    }

    return BandPermissions.fromRole(role, subPerms: subPerms);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[BandPermissions] Error fetching permissions: $e');
    }
    // Safe fallback — admin permissions
    return BandPermissions.admin;
  }
});

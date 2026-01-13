import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import '../profile/user_band_roles_repository.dart';
import 'member_vm.dart';
import 'pending_invite_vm.dart';

// ============================================================================
// MEMBERS REPOSITORY
// Handles all member-related data fetching from Supabase.
//
// ISOLATION RULES (NON-NEGOTIABLE):
// - Every query REQUIRES a non-null bandId
// - If bandId is null, we throw an error — NEVER query all members
// - Supabase RLS also enforces this, but we add client-side checks
//
// DATA MODEL (4-query approach — NO PostgREST embedded joins):
// - Query A: band_members WHERE band_id = ? AND status IN ('active','invited')
// - Query B: users WHERE id IN (userIds) selecting: id, email, first_name, last_name, phone, roles, profile_completed, created_at
// - Query C: band_invitations WHERE band_id = ? AND status = 'pending'
// - Query D: user_band_roles WHERE band_id = ? AND user_id IN (userIds) for band-specific roles
// - Merge client-side: for each band_member, attach user = usersById[user_id], override roles from user_band_roles if present
//
// BAND-SPECIFIC ROLES:
// - If user_band_roles has a row for (user_id, band_id), use that roles array
// - Otherwise, fall back to users.roles (global roles)
// - This allows users in multiple bands to have different roles per band
//
// INVITATION PENDING RULE:
// - "Invitation pending" text ONLY shows for band_invitations rows (in PendingInviteCard)
// - MemberCard shows members from band_members table (no invitation badge)
// - band_members.status == 'invited' does NOT trigger "Invitation pending" display
//
// RLS DEPENDENCY:
// - Requires migration 056_users_rls_band_members.sql to allow reading bandmates
// ============================================================================

/// Exception thrown when attempting to fetch members without a band context.
class NoBandSelectedError extends Error {
  final String message;
  NoBandSelectedError([
    this.message =
        'No band selected. Cannot fetch members without a band context.',
  ]);

  @override
  String toString() => 'NoBandSelectedError: $message';
}

/// Combined result of members + pending invites
class MembersData {
  final List<MemberVM> members;
  final List<PendingInviteVM> pendingInvites;

  const MembersData({required this.members, required this.pendingInvites});

  bool get isEmpty => members.isEmpty && pendingInvites.isEmpty;
}

class MembersRepository {
  // Simple in-memory cache per bandId
  final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Repository for band-specific roles
  // Uses the same instance throughout the app's lifecycle via the provider
  final UserBandRolesRepository _userBandRolesRepo;

  /// Creates a MembersRepository with an optional UserBandRolesRepository.
  /// If none provided, creates a new instance (for backward compatibility).
  MembersRepository({UserBandRolesRepository? userBandRolesRepo})
    : _userBandRolesRepo = userBandRolesRepo ?? UserBandRolesRepository();

  /// Fetches all members AND pending invites for the specified band.
  ///
  /// IMPORTANT: bandId is REQUIRED. If null, throws NoBandSelectedError.
  /// This prevents accidental cross-band data leakage.
  ///
  /// Uses THREE queries + client-side merge (NO PostgREST joins):
  /// A) band_members for membership rows
  /// B) users for user data (keyed by id = auth.users.id)
  /// C) band_invitations for pending invites
  ///
  /// Set [forceRefresh] to true to bypass cache.
  Future<MembersData> fetchMembersAndInvites({
    required String? bandId,
    bool forceRefresh = false,
  }) async {
    // =========================================
    // BAND ISOLATION CHECK — NON-NEGOTIABLE
    // =========================================
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    // Check cache first
    if (!forceRefresh) {
      final cached = _cache[bandId];
      if (cached != null && !cached.isExpired) {
        // ignore: avoid_print
        print(
          '[MembersRepository] Returning cached: ${cached.data.members.length} members, ${cached.data.pendingInvites.length} invites',
        );
        return cached.data;
      }
    }

    // ignore: avoid_print
    print('[MembersRepository] Fetching members for band: $bandId');

    // =========================================
    // QUERY A: band_members
    // Only include 'active' or 'invited' status members
    // =========================================
    final bandMembersResponse = await supabase
        .from('band_members')
        .select('id, user_id, role, status, joined_at')
        .eq('band_id', bandId)
        .inFilter('status', ['active', 'invited'])
        .order('joined_at', ascending: true);

    final bandMemberRows = List<Map<String, dynamic>>.from(bandMembersResponse);
    // ignore: avoid_print
    print(
      '[MembersRepository] Query A: ${bandMemberRows.length} band_members rows',
    );

    // Collect user IDs for the profile query
    final userIds = bandMemberRows
        .map((row) => row['user_id'] as String)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    // =========================================
    // QUERY B: users (only if we have userIds)
    // users.id = auth.users(id) = band_members.user_id
    // =========================================
    Map<String, Map<String, dynamic>> usersById = {};

    if (userIds.isNotEmpty) {
      // ignore: avoid_print
      print(
        '[MembersRepository] Query B: looking up ${userIds.length} userIds: ${userIds.take(3).toList()}',
      );

      final usersResponse = await supabase
          .from('users')
          .select(
            'id, email, first_name, last_name, phone, address, city, zip, birthday, roles, profile_completed, created_at',
          )
          .inFilter('id', userIds);

      final userRows = List<Map<String, dynamic>>.from(usersResponse);
      // ignore: avoid_print
      print('[MembersRepository] Query B: ${userRows.length} users returned');

      // Build lookup map and log first few (sanitized - no full emails)
      for (int i = 0; i < userRows.length; i++) {
        final user = userRows[i];
        final id = user['id'] as String?;
        if (id != null) {
          usersById[id] = user;
          if (i < 3) {
            final firstName = user['first_name'] as String? ?? '';
            final lastName = user['last_name'] as String? ?? '';
            final hasEmail = (user['email'] as String?)?.isNotEmpty ?? false;
            // ignore: avoid_print
            print(
              '[MembersRepository]   user[$i]: id=${id.substring(0, 8)}... name="$firstName $lastName" hasEmail=$hasEmail',
            );
          }
        }
      }
    }

    // Debug: log missing users count and which IDs are missing
    final missingUsersCount = userIds.length - usersById.length;
    if (missingUsersCount > 0) {
      // ignore: avoid_print
      print(
        '[MembersRepository] ⚠️ Missing users: $missingUsersCount/${userIds.length}',
      );
      // Log which user IDs are missing (truncated for privacy)
      final missingIds = userIds
          .where((id) => !usersById.containsKey(id))
          .toList();
      // ignore: avoid_print
      print(
        '[MembersRepository]   Missing user ID prefixes: ${missingIds.take(5).map((id) => id.substring(0, 8)).toList()}',
      );
      // ignore: avoid_print
      print(
        '[MembersRepository]   Likely cause: RLS policy blocking bandmate reads. Run migration 056_users_rls_band_members.sql',
      );
    }

    // =========================================
    // QUERY C: band_invitations (pending only)
    // =========================================
    final invitesResponse = await supabase
        .from('band_invitations')
        .select('id, email, status, created_at, expires_at')
        .eq('band_id', bandId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    final inviteRows = List<Map<String, dynamic>>.from(invitesResponse);
    // ignore: avoid_print
    print(
      '[MembersRepository] Query C: ${inviteRows.length} pending invitations',
    );

    // =========================================
    // QUERY D: user_band_roles (band-specific roles)
    // Fetch roles for all members in this band
    // =========================================
    Map<String, List<String>> bandSpecificRoles = {};
    if (userIds.isNotEmpty) {
      try {
        bandSpecificRoles = await _userBandRolesRepo.fetchRolesForUsers(
          bandId: bandId,
          userIds: userIds,
        );
        // ignore: avoid_print
        print(
          '[MembersRepository] Query D: ${bandSpecificRoles.length} users have band-specific roles',
        );
      } catch (e) {
        // If query fails, just use empty map (fall back to global roles)
        // ignore: avoid_print
        print('[MembersRepository] Query D failed (using global roles): $e');
      }
    }

    // =========================================
    // MERGE: Combine band_members + users + band_roles
    // =========================================
    final members = <MemberVM>[];
    int resolvedCount = 0;

    for (final memberRow in bandMemberRows) {
      try {
        final odaId = memberRow['user_id'] as String;
        final userRow = usersById[odaId]; // May be null

        if (userRow != null) {
          resolvedCount++;
        }

        // Check if this user has band-specific roles
        final bandRolesOverride = bandSpecificRoles[odaId];

        members.add(
          MemberVM.fromMergedData(
            bandMember: memberRow,
            userRow: userRow,
            bandRolesOverride: bandRolesOverride,
            bandId: bandId,
          ),
        );
      } catch (e) {
        // Skip malformed rows but log the error
        // ignore: avoid_print
        print('[MembersRepository] Failed to parse member: $e');
      }
    }

    // ignore: avoid_print
    print(
      '[MembersRepository] Merged: $resolvedCount/${bandMemberRows.length} members have user rows',
    );

    // =========================================
    // SORT: Alphabetically by last name, then first name
    // =========================================
    members.sort((a, b) {
      // Compare last names first (case-insensitive)
      final lastNameA = (a.lastName ?? '').toLowerCase();
      final lastNameB = (b.lastName ?? '').toLowerCase();
      final lastNameCompare = lastNameA.compareTo(lastNameB);
      if (lastNameCompare != 0) return lastNameCompare;

      // If last names are equal, compare first names
      final firstNameA = (a.firstName ?? '').toLowerCase();
      final firstNameB = (b.firstName ?? '').toLowerCase();
      return firstNameA.compareTo(firstNameB);
    });

    // =========================================
    // PARSE: Pending invites
    // =========================================
    final pendingInvites = <PendingInviteVM>[];
    for (final inviteRow in inviteRows) {
      try {
        pendingInvites.add(PendingInviteVM.fromJson(inviteRow));
      } catch (e) {
        // ignore: avoid_print
        print('[MembersRepository] Failed to parse invite: $e');
      }
    }

    // ignore: avoid_print
    print(
      '[MembersRepository] Final: ${members.length} members, ${pendingInvites.length} pending invites',
    );

    final result = MembersData(
      members: members,
      pendingInvites: pendingInvites,
    );

    // Cache the results
    _cache[bandId] = _CacheEntry(data: result);

    return result;
  }

  /// Legacy method - returns just members (for backward compatibility)
  Future<List<MemberVM>> fetchMembers({
    required String? bandId,
    bool forceRefresh = false,
  }) async {
    final data = await fetchMembersAndInvites(
      bandId: bandId,
      forceRefresh: forceRefresh,
    );
    return data.members;
  }

  /// Removes a member from the band (sets status to 'removed').
  ///
  /// Returns true if successful, false otherwise.
  Future<bool> removeMember({
    required String memberId,
    required String bandId,
  }) async {
    if (bandId.isEmpty || memberId.isEmpty) {
      return false;
    }

    try {
      await supabase
          .from('band_members')
          .update({'status': 'removed'})
          .eq('id', memberId)
          .eq('band_id', bandId);

      // Invalidate cache for this band
      _cache.remove(bandId);

      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[MembersRepository] Failed to remove member: $e');
      return false;
    }
  }

  /// Clears the cache for a specific band or all bands.
  /// Also clears the internal user_band_roles cache to ensure role updates
  /// propagate correctly to the Members screen.
  void clearCache([String? bandId]) {
    if (bandId != null) {
      _cache.remove(bandId);
    } else {
      _cache.clear();
    }
    // CRITICAL: Also clear the user_band_roles cache so role changes
    // from My Profile are reflected when members are reloaded.
    // This fixes the bug where unselected roles still appeared on Members page.
    _userBandRolesRepo.clearCache();
  }

  /// Clears all caches including user band roles.
  /// Called after profile save to ensure Members screen shows updated roles.
  void clearAllCaches() {
    _cache.clear();
    _userBandRolesRepo.clearCache();
  }

  /// Checks if current user is admin/owner of the band.
  Future<bool> isCurrentUserAdmin(String bandId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final response = await supabase
          .from('band_members')
          .select('role')
          .eq('band_id', bandId)
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (response == null) return false;

      final role = response['role'] as String?;
      return role == 'admin' || role == 'owner';
    } catch (e) {
      return false;
    }
  }
}

/// Cache entry with expiration
class _CacheEntry {
  final MembersData data;
  final DateTime createdAt;

  _CacheEntry({required this.data}) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt) > MembersRepository._cacheDuration;
}

// ============================================================================
// PROVIDER
// Provides a singleton MembersRepository that shares the UserBandRolesRepository
// instance. This ensures cache clearing in My Profile propagates correctly.
// ============================================================================

/// Provider for the members repository
final membersRepositoryProvider = Provider<MembersRepository>((ref) {
  // Share the same UserBandRolesRepository instance for consistent caching
  final userBandRolesRepo = ref.read(userBandRolesRepositoryProvider);
  return MembersRepository(userBandRolesRepo: userBandRolesRepo);
});

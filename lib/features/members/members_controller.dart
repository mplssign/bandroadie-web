import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'member_vm.dart';
import 'members_repository.dart';
import 'pending_invite_vm.dart';

// ============================================================================
// MEMBERS CONTROLLER
// Riverpod state management for the Members screen.
//
// BAND SCOPING: Always requires an active band. If band changes, members
// are reloaded automatically via the activeBandProvider listener.
//
// DATA MODEL:
// - members: List<MemberVM> from band_members + users
// - pendingInvites: List<PendingInviteVM> from band_invitations
// ============================================================================

/// State for the members screen
class MembersState {
  /// List of members in the current band
  final List<MemberVM> members;

  /// List of pending invitations
  final List<PendingInviteVM> pendingInvites;

  /// Whether we're currently loading
  final bool isLoading;

  /// Error message if fetch failed
  final String? error;

  /// Whether current user is an admin (can remove members)
  final bool isCurrentUserAdmin;

  const MembersState({
    this.members = const [],
    this.pendingInvites = const [],
    this.isLoading = false,
    this.error,
    this.isCurrentUserAdmin = false,
  });

  /// Whether there are any members to show
  bool get hasMembers => members.isNotEmpty;

  /// Whether there are pending invites
  bool get hasPendingInvites => pendingInvites.isNotEmpty;

  /// Total count (members + invites)
  int get totalCount => members.length + pendingInvites.length;

  /// Copy with new values
  MembersState copyWith({
    List<MemberVM>? members,
    List<PendingInviteVM>? pendingInvites,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isCurrentUserAdmin,
  }) {
    return MembersState(
      members: members ?? this.members,
      pendingInvites: pendingInvites ?? this.pendingInvites,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isCurrentUserAdmin: isCurrentUserAdmin ?? this.isCurrentUserAdmin,
    );
  }
}

/// Notifier that manages members state
class MembersNotifier extends Notifier<MembersState> {
  @override
  MembersState build() {
    return const MembersState();
  }

  /// Gets the repository from the provider.
  /// This ensures we share the same UserBandRolesRepository instance,
  /// so cache clearing in My Profile propagates correctly.
  MembersRepository get _repository => ref.read(membersRepositoryProvider);

  /// Load members and pending invites for the specified band
  Future<void> loadMembers(String? bandId, {bool forceRefresh = false}) async {
    if (bandId == null || bandId.isEmpty) {
      state = state.copyWith(
        members: [],
        pendingInvites: [],
        isLoading: false,
        error: 'No band selected',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final data = await _repository.fetchMembersAndInvites(
        bandId: bandId,
        forceRefresh: forceRefresh,
      );
      final isAdmin = await _repository.isCurrentUserAdmin(bandId);

      state = state.copyWith(
        members: data.members,
        pendingInvites: data.pendingInvites,
        isLoading: false,
        isCurrentUserAdmin: isAdmin,
      );

      // Enhanced debug logging per requirements
      if (kDebugMode) {
        debugPrint(
          '[Members] activeMembers=${data.members.length} pendingInvites=${data.pendingInvites.length}',
        );
        // Log first 3 members with details (sanitized - no full emails)
        for (int i = 0; i < data.members.length && i < 3; i++) {
          final m = data.members[i];
          debugPrint(
            '[Members] [$i] name="${m.name}" status=${m.status} hasUserRow=${m.hasUserRow} hasEmail=${m.email.isNotEmpty}',
          );
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      if (kDebugMode) {
        debugPrint('[MembersController] Error loading members: $e');
      }
    }
  }

  /// Remove a member from the band
  Future<bool> removeMember(String memberId, String bandId) async {
    try {
      final success = await _repository.removeMember(
        memberId: memberId,
        bandId: bandId,
      );

      if (success) {
        // Remove from local state
        state = state.copyWith(
          members: state.members.where((m) => m.memberId != memberId).toList(),
        );
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MembersController] Error removing member: $e');
      }
      return false;
    }
  }

  /// Force refresh the members list
  Future<void> refresh(String? bandId) async {
    await loadMembers(bandId, forceRefresh: true);
  }

  /// Reset state (e.g., on logout or band switch)
  void reset() {
    _repository.clearCache();
    state = const MembersState();
  }
}

/// Provider for members state
final membersProvider = NotifierProvider<MembersNotifier, MembersState>(
  MembersNotifier.new,
);

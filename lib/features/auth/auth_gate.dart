import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/auth_debug_logger.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import '../bands/active_band_controller.dart';
import '../profile/my_profile_screen.dart';
import '../shell/app_shell.dart';
import '../shell/no_band_shell.dart';
import 'auth_state_provider.dart';
import 'login_screen.dart';

// Re-export supabase client for backward compatibility
export '../../app/services/supabase_client.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  bool _initialized = false;
  bool _checkingProfile = false;
  bool? _profileComplete;
  bool _profileSkipped = false; // User chose to skip profile completion
  bool _processingPendingInvite = false;
  bool _hasCheckedPendingInvites =
      false; // Guard: only check invites once per session
  String? _pendingInviteMessage;

  /// Track previous lifecycle state to detect meaningful transitions.
  /// Critical for iPad where inactive is common during multitasking.
  AppLifecycleState? _previousLifecycleState;

  /// SAFEGUARD: Periodic timer to catch session state drift.
  /// This is a belt-and-suspenders approach for iPad review reliability.
  Timer? _sessionSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAuth();
    _startSessionSyncTimer();
  }

  /// SAFEGUARD: Periodically verify session state is in sync.
  /// Runs every 5 seconds to catch any edge cases where state drifts.
  void _startSessionSyncTimer() {
    _sessionSyncTimer?.cancel();
    _sessionSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;

      final providerSession = ref.read(authStateProvider).session;
      final actualSession = supabase.auth.currentSession;

      // Check for state mismatch
      final providerHasSession = providerSession != null;
      final actualHasSession = actualSession != null;

      if (providerHasSession != actualHasSession) {
        debugPrint('[AuthGate] SAFEGUARD: Session sync mismatch detected!');
        debugPrint(
          '  Provider: $providerHasSession, Actual: $actualHasSession',
        );
        AuthDebugLogger.error(
          step: 'sessionSyncTimer',
          message:
              'State mismatch - provider=$providerHasSession, actual=$actualHasSession',
        );
        // Force sync
        ref.read(authStateProvider.notifier).forceRefresh();
      }
    });
  }

  /// Handle app lifecycle changes - critical for iPad magic link support.
  /// iPad multitasking causes different lifecycle patterns than iPhone:
  /// - Split View / Slide Over may keep app in 'inactive' instead of 'paused'
  /// - Magic links may arrive while app is 'inactive' not 'paused'
  /// - Need to refresh on any transition back to 'resumed'
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[AuthGate] Lifecycle: $_previousLifecycleState -> $state');

    AuthDebugLogger.lifecycleEvent(
      from: _previousLifecycleState?.name ?? 'initial',
      to: state.name,
    );

    // Refresh auth state when returning to active state
    // This handles: paused->resumed, inactive->resumed, hidden->resumed
    if (state == AppLifecycleState.resumed) {
      debugPrint('[AuthGate] App resumed - refreshing auth state...');
      // Use post-frame callback to ensure Flutter has fully resumed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(authStateProvider.notifier).refreshSession();
        }
      });
    }

    _previousLifecycleState = state;
  }

  void _initializeAuth() {
    _initialized = true;

    // Check initial session from provider
    final authState = ref.read(authStateProvider);
    debugPrint(
      '[AuthGate] Initial session: ${authState.isAuthenticated ? "present" : "null"}',
    );

    // Listen for auth state changes to trigger profile check
    ref.listenManual(authStateProvider, (previous, next) {
      debugPrint(
        '[AuthGate] Auth state changed: ${previous?.isAuthenticated} -> ${next.isAuthenticated}',
      );

      // Session state changed
      if (previous?.isAuthenticated != next.isAuthenticated) {
        if (next.isAuthenticated) {
          // New session - reset profile check, skip state, and invite check
          setState(() {
            _profileComplete = null;
            _profileSkipped = false;
            _hasCheckedPendingInvites =
                false; // Allow invite check for new session
          });
          _checkProfileComplete();
        } else {
          // Signed out - reset all state
          setState(() {
            _profileComplete = null;
            _profileSkipped = false;
            _hasCheckedPendingInvites = false; // Reset for next login
          });
        }
      }
    });

    // If we have a session, check profile completeness
    if (authState.isAuthenticated) {
      _checkProfileComplete();
    }
  }

  Future<void> _checkProfileComplete() async {
    if (_checkingProfile) return;

    setState(() {
      _checkingProfile = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _profileComplete = false;
          _checkingProfile = false;
        });
        return;
      }

      debugPrint('[AuthGate] Checking profile completeness for user: $userId');

      final response = await supabase
          .from('users')
          .select('first_name, last_name')
          .eq('id', userId)
          .maybeSingle();

      final firstName = response?['first_name'] as String?;
      final lastName = response?['last_name'] as String?;

      final isComplete =
          firstName != null &&
          firstName.trim().isNotEmpty &&
          lastName != null &&
          lastName.trim().isNotEmpty;

      debugPrint(
        '[AuthGate] Profile complete: $isComplete (firstName: $firstName, lastName: $lastName)',
      );

      if (mounted) {
        setState(() {
          _profileComplete = isComplete;
          _checkingProfile = false;
        });

        // If profile is complete, check for pending invites then trigger band loading
        if (isComplete) {
          await _checkAndProcessPendingInvite();
          // Await band loading to ensure bands are loaded after invites are processed
          await ref.read(activeBandProvider.notifier).loadUserBands();
        }
      }
    } catch (e) {
      debugPrint('[AuthGate] Error checking profile: $e');
      if (mounted) {
        setState(() {
          // On error, assume incomplete to be safe
          _profileComplete = false;
          _checkingProfile = false;
        });
      }
    }
  }

  /// Check for pending invitations by email and process them via edge function.
  /// Only runs once per app session to prevent repeated snackbars.
  Future<void> _checkAndProcessPendingInvite() async {
    // Guard: Only check pending invites once per session
    if (_hasCheckedPendingInvites) {
      debugPrint(
        '[AuthGate] Skipping pending invite check - already checked this session',
      );
      return;
    }

    try {
      final userEmail = supabase.auth.currentUser?.email;
      if (userEmail == null || userEmail.isEmpty) {
        return;
      }

      // Mark as checked immediately to prevent concurrent calls
      _hasCheckedPendingInvites = true;

      setState(() {
        _processingPendingInvite = true;
      });

      // Call the edge function which has admin privileges to accept invites
      final response = await supabase.functions.invoke(
        'accept-invite',
        body: {}, // No body needed, uses JWT for auth
      );

      if (response.status != 200) {
        setState(() {
          _processingPendingInvite = false;
        });
        return;
      }

      final data = response.data as Map<String, dynamic>?;
      final acceptedCount = data?['accepted_count'] as int? ?? 0;
      final bandNames = List<String>.from(data?['band_names'] ?? []);

      // Don't show success message - user doesn't need notification

      if (mounted) {
        setState(() {
          _processingPendingInvite = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processingPendingInvite = false;
        });
      }
    }
  }

  /// Called when profile is saved to refresh the gate
  void onProfileSaved() {
    _checkProfileComplete();
  }

  /// Called when user chooses to skip profile completion
  void onSkipProfile() {
    debugPrint('[AuthGate] User skipped profile completion');
    AuthDebugLogger.routerTransition(
      from: 'profile_gate',
      to: 'no_band_shell',
      reason: 'User skipped profile',
    );
    setState(() {
      _profileSkipped = true;
    });
    // Load bands and proceed (user may still have pending invites)
    _checkAndProcessPendingInvite().then((_) {
      ref.read(activeBandProvider.notifier).loadUserBands();
    });
  }

  @override
  void dispose() {
    _sessionSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state from provider - this is reactive!
    // Any change to auth state will trigger a rebuild
    final authState = ref.watch(authStateProvider);

    // Show loading while initializing
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E1E1E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
        ),
      );
    }

    // No session -> show login
    // This check uses the reactive provider state
    if (!authState.isAuthenticated) {
      // SAFEGUARD: Double-check Supabase directly to prevent showing login
      // to authenticated users. This catches edge cases where provider state
      // is out of sync with actual session (critical for iPad review).
      final directSession = supabase.auth.currentSession;
      if (directSession != null) {
        debugPrint(
          '[AuthGate] SAFEGUARD: Provider says no session, but Supabase has one!',
        );
        AuthDebugLogger.error(
          step: 'AuthGate.build',
          message: 'State mismatch - forcing refresh',
        );
        // Force sync and skip showing login
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(authStateProvider.notifier).refreshSession();
          }
        });
        // Show loading while we sync instead of login screen
        return const Scaffold(
          backgroundColor: Color(0xFF1E1E1E),
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
          ),
        );
      }

      debugPrint('[AuthGate] No session - showing login screen');
      AuthDebugLogger.routerTransition(
        from: 'unknown',
        to: 'login',
        reason: 'No authenticated session',
      );
      return const LoginScreen();
    }

    // Session exists - check if we need to verify profile
    // Trigger profile check if not already done
    if (_profileComplete == null && !_checkingProfile) {
      // Schedule profile check for next frame to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkProfileComplete();
      });
    }

    // Session exists but still checking profile or processing pending invite
    if (_profileComplete == null ||
        _checkingProfile ||
        _processingPendingInvite) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF3B82F6)),
              if (_processingPendingInvite) ...[
                const SizedBox(height: 16),
                const Text(
                  'Processing your invite...',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Profile incomplete and not skipped -> show profile screen with skip option
    if (_profileComplete == false && !_profileSkipped) {
      AuthDebugLogger.routerTransition(
        from: 'login',
        to: 'profile_gate',
        reason: 'Profile incomplete',
      );
      return ProfileGateScreen(
        onProfileSaved: onProfileSaved,
        onSkip: onSkipProfile,
      );
    }

    // Profile complete -> check if user has bands
    // Watch the activeBandProvider to get user's bands
    final bandState = ref.watch(activeBandProvider);

    // Still loading bands
    if (bandState.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E1E1E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
        ),
      );
    }

    // Build the main content
    Widget mainContent;

    // No bands -> show NoBandShell (welcome page with menu/band switcher, no footer)
    if (bandState.userBands.isEmpty) {
      AuthDebugLogger.routerTransition(
        from: 'profile_gate',
        to: 'no_band_shell',
        reason: 'User has no bands',
      );
      mainContent = const NoBandShell();
    } else {
      // Has bands -> full app access
      AuthDebugLogger.routerTransition(
        from: 'profile_gate',
        to: 'app_shell',
        reason: 'User has ${bandState.userBands.length} band(s)',
      );
      mainContent = const AppShell();
    }

    // Show success banner if pending invite was just accepted
    if (_pendingInviteMessage != null) {
      return Stack(
        children: [
          mainContent,
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF22C55E),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _pendingInviteMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _pendingInviteMessage = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return mainContent;
  }
}

/// Wrapper for MyProfileScreen that allows skipping profile completion
class ProfileGateScreen extends StatelessWidget {
  final VoidCallback onProfileSaved;
  final VoidCallback? onSkip;

  const ProfileGateScreen({
    super.key,
    required this.onProfileSaved,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Allow pop if onSkip is provided (user can skip profile)
      canPop: onSkip != null,
      child: MyProfileScreen(
        isGated: true,
        onProfileComplete: onProfileSaved,
        onSkip: onSkip,
      ),
    );
  }
}

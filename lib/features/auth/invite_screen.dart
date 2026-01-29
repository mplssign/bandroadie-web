import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';

/// Key for storing pending invite token in SharedPreferences
const String kPendingInviteTokenKey = 'pending_invite_token';

/// InviteScreen handles /invite?token=... deep links for web and mobile.
/// Shows loading, error, and success states, and handles auth + invite acceptance.
class InviteScreen extends StatefulWidget {
  final String? token;
  const InviteScreen({super.key, this.token});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  bool _loading = true;
  String? _error;
  bool _accepted = false;
  String? _bandName;
  bool _needsAuth = false;
  bool _signingIn = false;
  final _emailController = TextEditingController();
  String? _emailError;
  bool _magicLinkSent = false;
  StreamSubscription<AuthState>? _authSubscription;
  bool _hasTriedAccept = false;

  @override
  void initState() {
    super.initState();
    _initAuthListener();
    _handleInvite();
  }

  void _initAuthListener() {
    // Listen for auth state changes to handle PKCE code exchange completing
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        debugPrint('[InviteScreen] Auth state changed: ${data.event.name}');

        // If we get a session and haven't accepted yet, try to accept
        if (data.session != null &&
            !_hasTriedAccept &&
            !_accepted &&
            widget.token != null) {
          debugPrint(
            '[InviteScreen] Session detected, attempting to accept invite',
          );
          _acceptInvite(widget.token!);
        }
      },
      onError: (error) {
        debugPrint('[InviteScreen] Auth error: $error');
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleInvite() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() {
        _error = 'Missing or invalid invite token.';
        _loading = false;
      });
      return;
    }

    // Give Supabase SDK a moment to process any PKCE code in the URL
    // This handles the case where the magic link redirects back with ?code=...
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Check if user is authenticated
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // User not authenticated - show login UI
      // The auth listener will handle accepting the invite if auth completes later
      setState(() {
        _needsAuth = true;
        _loading = false;
      });
      return;
    }

    // User is authenticated - try to accept the invite
    await _acceptInvite(token);
  }

  Future<void> _acceptInvite(String token) async {
    // Mark that we've attempted to accept to avoid duplicate attempts
    _hasTriedAccept = true;

    setState(() {
      _loading = true;
      _error = null;
      _needsAuth = false; // Clear the auth UI if showing
    });

    try {
      debugPrint('[InviteScreen] Calling accept-invite with token: $token');

      final response = await Supabase.instance.client.functions.invoke(
        'accept-invite',
        body: {'token': token},
      );

      debugPrint('[InviteScreen] Response status: ${response.status}');
      debugPrint('[InviteScreen] Response data: ${response.data}');

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']
            : 'Failed to accept invite';
        setState(() {
          _error = errorMsg?.toString() ?? 'Failed to accept invite';
          _loading = false;
        });
        return;
      }

      final data = response.data is Map
          ? response.data
          : jsonDecode(response.data.toString());

      if (data['success'] == true) {
        // Clear pending invite token since we've successfully accepted
        await PendingInviteHelper.clearPendingInviteToken();

        setState(() {
          _accepted = true;
          _bandName = data['band_name']?.toString();
          _loading = false;
        });

        // Wait a moment then redirect to main app
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
          );
        }
      } else {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to accept invite';
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[InviteScreen] Error accepting invite: $e');
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _sendMagicLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _emailError = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _signingIn = true;
      _emailError = null;
    });

    try {
      // Build redirect URL that includes the invite token
      final token = widget.token;
      final redirectUrl = 'https://bandroadie.com/invite?token=$token';

      // Store the invite token in SharedPreferences so AuthGate can pick it up
      // This handles the case where the redirect doesn't work as expected
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kPendingInviteTokenKey, token!);
        debugPrint('[InviteScreen] Stored pending invite token: $token');
      } catch (e) {
        debugPrint(
          '[InviteScreen] ❌ CRITICAL: Failed to persist invite token: $e',
        );
        debugPrint(
          '[InviteScreen] Private browsing mode may prevent invite acceptance',
        );
        // Continue anyway - the URL parameter may still work
      }

      debugPrint(
        '[InviteScreen] Sending magic link to $email with redirect: $redirectUrl',
      );

      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: redirectUrl,
      );

      setState(() {
        _magicLinkSent = true;
        _signingIn = false;
      });
    } catch (e) {
      debugPrint('[InviteScreen] Error sending magic link: $e');
      setState(() {
        _emailError = 'Failed to send magic link. Please try again.';
        _signingIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF3B82F6)),
          SizedBox(height: 16),
          Text(
            'Accepting your invite...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      );
    }

    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
            ),
            child: const Text('Go to App'),
          ),
        ],
      );
    }

    if (_accepted) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          Text(
            _bandName != null
                ? 'You\'ve joined $_bandName!'
                : 'Invite accepted!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Redirecting to the app...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      );
    }

    if (_needsAuth) {
      return _buildAuthUI();
    }

    return const SizedBox.shrink();
  }

  Widget _buildAuthUI() {
    if (_magicLinkSent) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.email_outlined, color: Color(0xFF3B82F6), size: 64),
          const SizedBox(height: 24),
          const Text(
            'Check your email!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'We sent a magic link to\n${_emailController.text.trim()}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Click the link in the email to sign in and accept your band invite.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() {
                _magicLinkSent = false;
              });
            },
            child: const Text(
              'Use a different email',
              style: TextStyle(color: Color(0xFF3B82F6)),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.group_add, color: Color(0xFF3B82F6), size: 64),
        const SizedBox(height: 24),
        const Text(
          'You\'ve been invited to join a band!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Sign in or create an account to accept the invite.',
          style: TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: 320,
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Email address',
              labelStyle: const TextStyle(color: Colors.white54),
              errorText: _emailError,
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF3B82F6)),
              ),
            ),
            onSubmitted: (_) => _sendMagicLink(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 320,
          height: 48,
          child: ElevatedButton(
            onPressed: _signingIn ? null : _sendMagicLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _signingIn
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Send Magic Link',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Helper class to check and process pending invite tokens from AuthGate
class PendingInviteHelper {
  /// Check if there's a pending invite token stored
  static Future<String?> getPendingInviteToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kPendingInviteTokenKey);
    } catch (e) {
      debugPrint('[PendingInviteHelper] ⚠️ SharedPreferences unavailable: $e');
      return null;
    }
  }

  /// Clear the pending invite token
  static Future<void> clearPendingInviteToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPendingInviteTokenKey);
    } catch (e) {
      debugPrint('[PendingInviteHelper] ⚠️ Failed to clear invite token: $e');
      // Silent failure acceptable for cleanup operations
    }
  }

  /// Accept a pending invite by calling the edge function
  /// Returns a map with success/error info
  static Future<Map<String, dynamic>> acceptInvite(String token) async {
    try {
      debugPrint(
        '[PendingInviteHelper] Calling accept-invite with token: $token',
      );

      final response = await Supabase.instance.client.functions.invoke(
        'accept-invite',
        body: {'token': token},
      );

      debugPrint('[PendingInviteHelper] Response status: ${response.status}');
      debugPrint('[PendingInviteHelper] Response data: ${response.data}');

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? response.data['error']
            : 'Failed to accept invite';
        return {
          'success': false,
          'error': errorMsg?.toString() ?? 'Failed to accept invite',
        };
      }

      final data = response.data is Map
          ? response.data
          : jsonDecode(response.data.toString());

      // Clear the pending token after successful acceptance
      await clearPendingInviteToken();

      return {
        'success': data['success'] == true,
        'band_name': data['band_name'],
        'error': data['error'],
      };
    } catch (e) {
      debugPrint('[PendingInviteHelper] Error accepting invite: $e');
      return {
        'success': false,
        'error': 'Something went wrong. Please try again.',
      };
    }
  }
}

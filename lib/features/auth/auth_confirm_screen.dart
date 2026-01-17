import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';

/// AuthConfirmScreen handles /auth/confirm?token_hash=...&type=email
/// Also handles PKCE flow: /auth/confirm?code=...
///
/// This screen is reached when a user clicks a magic link email.
/// It exchanges the token for a session and redirects appropriately.
class AuthConfirmScreen extends StatefulWidget {
  final String? tokenHash;
  final String? code; // PKCE flow uses code parameter
  final String? type;
  const AuthConfirmScreen({super.key, this.tokenHash, this.code, this.type});

  @override
  State<AuthConfirmScreen> createState() => _AuthConfirmScreenState();
}

class _AuthConfirmScreenState extends State<AuthConfirmScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _handleConfirm();
  }

  Future<void> _handleConfirm() async {
    debugPrint('AuthConfirmScreen: _handleConfirm called');
    final tokenHash = widget.tokenHash;
    final code = widget.code;
    final type = widget.type ?? 'email';
    debugPrint(
      'AuthConfirmScreen: tokenHash=$tokenHash, code=${code != null ? "${code.substring(0, 10)}..." : "null"}, type=$type',
    );

    // Check if we have either a code (PKCE) or token_hash
    if ((tokenHash == null || tokenHash.isEmpty) &&
        (code == null || code.isEmpty)) {
      setState(() {
        _error = 'Missing or invalid token.';
        _loading = false;
      });
      return;
    }

    try {
      Session? session;
      User? user;

      // PKCE flow - use code parameter with exchangeCodeForSession
      if (code != null && code.isNotEmpty) {
        debugPrint(
          'AuthConfirmScreen: PKCE flow - exchanging code for session...',
        );
        try {
          final pkceResponse = await Supabase.instance.client.auth
              .exchangeCodeForSession(code);
          session = pkceResponse.session;
          user = session.user;
          debugPrint('AuthConfirmScreen: PKCE exchange successful');
        } catch (e) {
          debugPrint('AuthConfirmScreen: PKCE exchange failed: $e');
          // If PKCE exchange fails, show browser mismatch error
          setState(() {
            _error = 'browser_mismatch';
            _loading = false;
          });
          return;
        }
      } else if (tokenHash != null && tokenHash.startsWith('pkce_')) {
        debugPrint(
          'AuthConfirmScreen: PKCE token_hash detected, using verifyOTP with magiclink type...',
        );
        final response = await Supabase.instance.client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: OtpType.magiclink,
        );
        session = response.session;
        user = response.user;
      } else {
        debugPrint(
          'AuthConfirmScreen: Standard token, using verifyOTP with email type...',
        );
        final response = await Supabase.instance.client.auth.verifyOTP(
          tokenHash: tokenHash!,
          type: OtpType.email,
        );
        session = response.session;
        user = response.user;
      }

      debugPrint(
        'AuthConfirmScreen: response: ${session != null ? "session exists" : "no session"}',
      );

      if (session == null) {
        setState(() {
          _error = 'Failed to verify token. Please request a new magic link.';
          _loading = false;
        });
        return;
      }

      debugPrint('AuthConfirmScreen: Session verified successfully');

      final userId = user?.id;
      debugPrint('AuthConfirmScreen: User ID: $userId');

      if (userId == null) {
        setState(() {
          _error = 'No user ID found after login.';
          _loading = false;
        });
        return;
      }

      // Session established - redirect to AuthGate which handles profile completeness check
      if (!mounted) return;

      debugPrint('AuthConfirmScreen: Redirecting to AuthGate');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );

      setState(() {
        _loading = false;
      });
    } on AuthException catch (e) {
      debugPrint('AuthConfirmScreen: AuthException: ${e.message}');
      // Check for PKCE/browser mismatch errors
      final isBrowserMismatch =
          e.message.contains('code verifier') ||
          e.message.contains('PKCE') ||
          e.message.contains('invalid') ||
          e.message.isEmpty;
      setState(() {
        _error = isBrowserMismatch
            ? 'browser_mismatch'
            : (e.message.isNotEmpty
                  ? e.message
                  : 'Authentication failed. Please request a new magic link.');
        _loading = false;
      });
    } catch (e) {
      debugPrint('AuthConfirmScreen: Error: $e');
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  /// Build helpful instructions for browser mismatch error
  Widget _buildBrowserMismatchHelp() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.browser_not_supported,
            color: Colors.orange,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Login Link Opened in Wrong Browser',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'For security, magic links must be opened in the same browser where you requested them.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎸 Quick Fix:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '1. Go back to your email\n'
                  '2. Copy the magic link URL\n'
                  '3. Paste it directly into this browser\'s address bar',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '💡 Tip: If your email app opens links in its own browser, try "Open in Safari" or "Open in Chrome" instead.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
            icon: const Icon(Icons.refresh),
            label: const Text('Request New Magic Link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: _loading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF3B82F6)),
                  SizedBox(height: 24),
                  Text(
                    'Verifying your login...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              )
            : _error == 'browser_mismatch'
            ? _buildBrowserMismatchHelp()
            : _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/'),
                    child: const Text('Back to Login'),
                  ),
                ],
              )
            : const Text(
                'Login successful! Redirecting...',
                style: TextStyle(color: Colors.white),
              ),
      ),
    );
  }
}

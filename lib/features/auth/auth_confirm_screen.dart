import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gate.dart';
import 'auth_state_provider.dart';

/// AuthConfirmScreen handles /auth/confirm?token_hash=...&type=email
/// Also handles PKCE flow: /auth/confirm?code=...
///
/// This screen is reached when a user clicks a magic link email.
/// It exchanges the token for a session and redirects appropriately.
///
/// IMPORTANT: This screen waits for the auth state provider to sync
/// before navigating to prevent login loops.
class AuthConfirmScreen extends ConsumerStatefulWidget {
  final String? tokenHash;
  final String? code; // PKCE flow uses code parameter
  final String? type;
  const AuthConfirmScreen({super.key, this.tokenHash, this.code, this.type});

  @override
  ConsumerState<AuthConfirmScreen> createState() => _AuthConfirmScreenState();
}

class _AuthConfirmScreenState extends ConsumerState<AuthConfirmScreen> {
  bool _loading = true;
  String? _error;
  bool _isInAppBrowser = false;

  @override
  void initState() {
    super.initState();
    _detectInAppBrowser();
    _handleConfirm();
  }

  /// Detect if user is in an in-app browser (Gmail, Instagram, etc.)
  /// These browsers have restricted cookie/storage access
  void _detectInAppBrowser() {
    // Check user agent for common in-app browser patterns
    // Note: This is a best-effort detection
    try {
      // In Flutter web, we'd need to use dart:html, but for now
      // we'll handle this in the error flow
      _isInAppBrowser = false;
    } catch (e) {
      _isInAppBrowser = false;
    }
  }

  Future<void> _handleConfirm() async {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔐 AUTH CONFIRM: Starting magic link verification');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    final tokenHash = widget.tokenHash;
    final code = widget.code;
    final type = widget.type ?? 'email';
    debugPrint('📧 Token hash: ${tokenHash?.substring(0, 10) ?? "null"}...');
    debugPrint('🔑 PKCE code: ${code != null ? "${code.substring(0, 10)}..." : "null"}');
    debugPrint('📝 Type: $type');

    // Check if we have either a code (PKCE) or token_hash
    if ((tokenHash == null || tokenHash.isEmpty) &&
        (code == null || code.isEmpty)) {
      debugPrint('❌ ERROR: No token or code provided');
      setState(() {
        _error = 'missing_token';
        _loading = false;
      });
      return;
    }

    try {
      Session? session;
      User? user;

      // PKCE flow - use code parameter with exchangeCodeForSession
      if (code != null && code.isNotEmpty) {
        debugPrint('🔄 Using PKCE flow - exchanging code for session...');
        try {
          final pkceResponse = await Supabase.instance.client.auth
              .exchangeCodeForSession(code);
          session = pkceResponse.session;
          user = session.user;
          debugPrint('✅ PKCE exchange successful');
          debugPrint('   User: ${user.email}');
          debugPrint('   Session expires: ${session.expiresAt}');
        } catch (e) {
          debugPrint('❌ PKCE exchange failed: $e');
          final errorMessage = e.toString().toLowerCase();
          // Detect specific error types
          final isExpired = errorMessage.contains('expired') || errorMessage.contains('invalid');
          final isBrowserMismatch = errorMessage.contains('code verifier') || errorMessage.contains('pkce');
          setState(() {
            _error = isExpired ? 'expired_link' : (isBrowserMismatch ? 'browser_mismatch' : 'auth_failed');
            _loading = false;
          });
          return;
        }
      } else if (tokenHash != null && tokenHash.startsWith('pkce_')) {
        debugPrint('🔄 PKCE token_hash detected, using verifyOTP with magiclink type...');
        final response = await Supabase.instance.client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: OtpType.magiclink,
        );
        session = response.session;
        user = response.user;
        debugPrint('✅ Token verification successful (magiclink)');
      } else {
        debugPrint('🔄 Standard token, using verifyOTP with email type...');
        final response = await Supabase.instance.client.auth.verifyOTP(
          tokenHash: tokenHash!,
          type: OtpType.email,
        );
        session = response.session;
        user = response.user;
        debugPrint('✅ Token verification successful (email)');
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

      debugPrint('✅ Session verified successfully');
      debugPrint('   User ID: ${user?.id}');
      debugPrint('   Email: ${user?.email}');
      debugPrint('   Access token: ${session.accessToken.substring(0, 20)}...');

      final userId = user?.id;
      if (userId == null) {
        debugPrint('❌ ERROR: No user ID found after login');
        setState(() {
          _error = 'no_user_id';
          _loading = false;
        });
        return;
      }

      // CRITICAL: Wait for auth state provider to sync
      // This prevents the login loop caused by AuthGate checking
      // session before the provider has updated
      if (!mounted) return;

      debugPrint('⏳ Waiting for auth state provider to sync...');
      
      // Wait for the auth state provider to recognize the session
      int attempts = 0;
      const maxAttempts = 10; // 5 seconds max
      while (attempts < maxAttempts) {
        final authState = ref.read(authStateProvider);
        if (authState.isAuthenticated) {
          debugPrint('✅ Auth state provider synced (attempt ${attempts + 1})');
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
        debugPrint('   Attempt ${attempts}/$maxAttempts...');
      }

      if (attempts >= maxAttempts) {
        debugPrint('⚠️ WARNING: Auth state provider did not sync, proceeding anyway');
      }

      if (!mounted) return;

      debugPrint('🚀 Navigating to AuthGate');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false, // Remove all previous routes
      );

      setState(() {
        _loading = false;
      });
    } on AuthException catch (e) {
      debugPrint('❌ AUTH EXCEPTION: ${e.message}');
      debugPrint('   Status code: ${e.statusCode}');
      
      // Classify error types for better user messaging
      final errorMsg = e.message.toLowerCase();
      String errorType;
      
      if (errorMsg.contains('expired') || errorMsg.contains('invalid grant')) {
        errorType = 'expired_link';
        debugPrint('   Classification: Expired or reused link');
      } else if (errorMsg.contains('code verifier') || errorMsg.contains('pkce')) {
        errorType = 'browser_mismatch';
        debugPrint('   Classification: Browser mismatch (PKCE)');
      } else if (errorMsg.contains('already been consumed')) {
        errorType = 'reused_link';
        debugPrint('   Classification: Link already used');
      } else if (e.message.isEmpty) {
        errorType = 'unknown_error';
        debugPrint('   Classification: Unknown error (empty message)');
      } else {
        errorType = e.message;
        debugPrint('   Classification: Other error');
      }
      
      setState(() {
        _error = errorType;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ UNEXPECTED ERROR: $e');
      setState(() {
        _error = 'unexpected_error';
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

  /// Build error UI with specific messaging based on error type
  Widget _buildErrorUI() {
    IconData icon;
    String title;
    String message;
    Color iconColor;
    
    switch (_error) {
      case 'expired_link':
      case 'reused_link':
        icon = Icons.timer_off;
        iconColor = Colors.orange;
        title = 'Magic Link Expired';
        message = _error == 'reused_link'
            ? 'This magic link has already been used. Each link can only be used once for security.'
            : 'This magic link has expired. Magic links are only valid for a limited time.';
        break;
      case 'browser_mismatch':
        return _buildBrowserMismatchHelp();
      case 'missing_token':
        icon = Icons.link_off;
        iconColor = Colors.red;
        title = 'Invalid Link';
        message = 'The magic link appears to be incomplete or corrupted. Please request a new one.';
        break;
      case 'no_user_id':
        icon = Icons.person_off;
        iconColor = Colors.red;
        title = 'Authentication Failed';
        message = 'We couldn\\'t verify your identity. Please try logging in again.';
        break;
      default:
        icon = Icons.error_outline;
        iconColor = Colors.red;
        title = 'Authentication Error';
        message = _error ?? 'Something went wrong during login. Please try again.';\n    }\n    \n    return Padding(\n      padding: const EdgeInsets.symmetric(horizontal: 32),\n      child: Column(\n        mainAxisSize: MainAxisSize.min,\n        children: [\n          Icon(icon, color: iconColor, size: 48),\n          const SizedBox(height: 16),\n          Text(\n            title,\n            style: const TextStyle(\n              color: Colors.white,\n              fontSize: 18,\n              fontWeight: FontWeight.bold,\n            ),\n            textAlign: TextAlign.center,\n          ),\n          const SizedBox(height: 12),\n          Text(\n            message,\n            style: const TextStyle(color: Colors.white70, fontSize: 14),\n            textAlign: TextAlign.center,\n          ),\n          const SizedBox(height: 24),\n          ElevatedButton.icon(\n            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),\n            icon: const Icon(Icons.email),\n            label: const Text('Request New Magic Link'),\n            style: ElevatedButton.styleFrom(\n              backgroundColor: const Color(0xFFF43F5E),\n              foregroundColor: Colors.white,\n              padding: const EdgeInsets.symmetric(\n                horizontal: 24,\n                vertical: 12,\n              ),\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n\n  @override\n  Widget build(BuildContext context) {\n    return Scaffold(\n      backgroundColor: const Color(0xFF0A0A0A),\n      body: Center(\n        child: _loading\n            ? const Column(\n                mainAxisAlignment: MainAxisAlignment.center,\n                children: [\n                  CircularProgressIndicator(color: Color(0xFF3B82F6)),\n                  SizedBox(height: 24),\n                  Text(\n                    'Verifying your login...',\n                    style: TextStyle(color: Colors.white70, fontSize: 16),\n                  ),\n                ],\n              )\n            : _error != null\n            ? _buildErrorUI()\n            : const Text(\n                'Login successful! Redirecting...',\n                style: TextStyle(color: Colors.white),\n              ),\n      ),\n    );\n  }\n}

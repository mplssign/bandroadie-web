// ============================================================================
// LOGIN SCREEN
// Magic link email login with PWA-style centered layout and polished animation.
//
// LAYOUT STRUCTURE:
// - Content cluster (title + email + pills + button) is centered on screen
// - Uses LayoutBuilder + Center for true centering on all screen sizes
// - SingleChildScrollView ensures no overflow on tiny screens
// - Keyboard-aware: smoothly lifts content when keyboard opens (iOS-style)
//
// ANIMATION TIMELINE (single controller with intervals):
// - 0.00–0.35: Title fades + scales in
// - 0.15–0.50: Email field fades + slides up
// - 0.35–0.70: Domain pills slide in from right
// - 0.55–0.90: Button scales + fades in
//
// DOMAIN SHORTCUT RULES:
// - If no @ exists: append domain (e.g., "tony" → "tony@gmail.com")
// - If @ exists: replace everything after @ (e.g., "tony@old.com" → "tony@gmail.com")
// - Preserves plus addressing (e.g., "tony+test@old.com" → "tony+test@gmail.com")
// - Empty input: focuses field, does nothing
//
// REDUCED MOTION:
// - If MediaQuery.disableAnimations is true, skip to final state instantly.
// ============================================================================

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/services/auth_debug_logger.dart';
import '../../app/theme/design_tokens.dart';
import '../../components/ui/field_hint.dart';
import '../../shared/utils/email_domain_helper.dart';
import '../../shared/widgets/animated_logo.dart';
import 'auth_gate.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _focusNode = FocusNode();
  final _emailHintController = FieldHintController();
  bool _isLoading = false;
  String? _message;
  String? _selectedDomain;
  String? _validationError;

  /// SAFEGUARD: Track if we detected an existing session.
  /// If true, we skip rendering login UI and wait for AuthGate to handle routing.
  bool _sessionDetected = false;

  // Single animation controller for coordinated entrance
  late AnimationController _animController;

  // Keyboard-triggered logo shrink animation
  late AnimationController _logoShrinkController;
  late Animation<double> _logoShrinkScale;

  // Interval-based animations for staggered entrance
  late Animation<double> _titleOpacity;
  late Animation<double> _titleScale;
  late Animation<double> _emailOpacity;
  late Animation<Offset> _emailSlide;
  late Animation<double> _pillsOpacity;
  late Animation<Offset> _pillsSlide;
  late Animation<double> _buttonOpacity;
  late Animation<double> _buttonScale;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
    _initAnimations();
    _initLogoShrinkAnimation();
    _initHintController();
  }

  /// SAFEGUARD: Check if user is already authenticated when LoginScreen mounts.
  /// This should never happen, but if it does, we detect it and log an error.
  /// AuthGate will handle the actual redirect; we just avoid showing login UI.
  void _checkExistingSession() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      if (kDebugMode) {
        debugPrint('[LoginScreen] ERROR: Mounted with existing session!');
        AuthDebugLogger.error(
          step: 'LoginScreen.initState',
          message: 'LoginScreen shown to authenticated user - this is a bug!',
        );
      }
      setState(() {
        _sessionDetected = true;
      });
    }
  }

  void _initHintController() {
    // Email field is always empty on login (no edit mode)
    _emailHintController.initialize(hasInitialValue: false);
    _focusNode.addListener(_onEmailFocusChange);
    _emailController.addListener(_onEmailTextChange);
  }

  void _onEmailFocusChange() {
    if (_focusNode.hasFocus) {
      _emailHintController.onFocus();
      // Shrink logo when keyboard appears
      _logoShrinkController.forward();
    } else {
      // Restore logo when keyboard hides
      _logoShrinkController.reverse();
    }
  }

  void _onEmailTextChange() {
    _emailHintController.onTextChanged(_emailController.text);
  }

  void _initLogoShrinkAnimation() {
    _logoShrinkController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // Shrink to 50% of the displayed size when keyboard is up
    _logoShrinkScale = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(
        parent: _logoShrinkController,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _initAnimations() {
    // Single controller for entire entrance sequence (800ms total)
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Title: 0.00–0.35 (fade + scale from 70% to 70% of maxWidth)
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
      ),
    );
    _titleScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
      ),
    );

    // Email: 0.15–0.50 (fade + slide up)
    _emailOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.15, 0.50, curve: Curves.easeOutCubic),
      ),
    );
    _emailSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.15, 0.50, curve: Curves.easeOutCubic),
          ),
        );

    // Pills: 0.35–0.70 (fade + slide from right)
    _pillsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.70, curve: Curves.easeOutCubic),
      ),
    );
    _pillsSlide = Tween<Offset>(begin: const Offset(0.2, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.35, 0.70, curve: Curves.easeOutCubic),
          ),
        );

    // Button: 0.55–0.90 (fade + scale pop)
    _buttonOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOutCubic),
      ),
    );
    _buttonScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOutBack),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;

    // Start animation on first build
    if (_animController.status == AnimationStatus.dismissed) {
      if (_reduceMotion) {
        _animController.value = 1.0; // Skip to end
      } else {
        _animController.forward();
      }
    }
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailTextChange);
    _focusNode.removeListener(_onEmailFocusChange);
    _emailController.dispose();
    _focusNode.dispose();
    _emailHintController.dispose();
    _animController.dispose();
    _logoShrinkController.dispose();
    super.dispose();
  }

  /// Applies a domain shortcut and updates the text field.
  void _applyDomainShortcut(String domain) {
    if (_isLoading) return;

    final current = _emailController.text;
    final result = applyEmailDomainShortcut(current, domain);

    if (result.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    _emailController.text = result;
    _emailController.selection = TextSelection.fromPosition(
      TextPosition(offset: result.length),
    );

    setState(() {
      _selectedDomain = domain;
      _validationError = null;
    });
  }

  /// Handles keyboard submit action.
  void _handleSubmit() {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _validationError = 'Please enter your email address');
      return;
    }

    if (!email.contains('@') || email.length <= 3) {
      setState(() => _validationError = 'Please enter a valid email address');
      return;
    }

    setState(() => _validationError = null);
    _sendMagicLink();
  }

  Future<void> _sendMagicLink() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _message = 'Please enter your email');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      // Web uses /auth/confirm route, native apps use deep link
      final redirectUrl = kIsWeb 
          ? 'https://bandroadie.com/auth/confirm' 
          : 'bandroadie://login-callback/';
      debugPrint('[LoginScreen] kIsWeb=$kIsWeb, emailRedirectTo=$redirectUrl');

      await supabase.auth.signInWithOtp(
        email: email,
        emailRedirectTo: redirectUrl,
      );

      setState(() {
        _message = 'Check your email for the login link.';
        _isLoading = false;
      });
    } on AuthException catch (e) {
      debugPrint('AuthException: ${e.message} (code: ${e.statusCode})');
      setState(() {
        _message = e.message.isNotEmpty
            ? e.message
            : 'Authentication error. Check your email format.';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Unexpected error: $e');
      setState(() {
        _message = 'Something went wrong. Try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // SAFEGUARD: If we detected an existing session, show loading
    // instead of login UI. AuthGate will handle the redirect.
    if (_sessionDetected) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E1E1E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
        ),
      );
    }

    // KEYBOARD-AWARE CENTERING:
    // MediaQuery.viewInsets.bottom gives keyboard height.
    // We use AnimatedPadding to smoothly lift the content cluster.
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final emailText = _emailController.text.trim();
    final hasValidEmail = emailText.contains('@') && emailText.length > 3;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedPadding(
              padding: EdgeInsets.only(bottom: keyboardHeight * 0.5),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (keyboardHeight * 0.5),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: AnimatedBuilder(
                        animation: _animController,
                        builder: (context, _) => _buildContentCluster(
                          hasValidEmail: hasValidEmail,
                          maxWidth: constraints.maxWidth - 64,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Builds the centered content cluster with all animated elements.
  Widget _buildContentCluster({
    required bool hasValidEmail,
    required double maxWidth,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // === LOGO ===
        _buildLogo(),

        const SizedBox(height: 48),

        // === EMAIL FIELD ===
        _buildEmailField(),

        const SizedBox(height: 12),

        // === DOMAIN PILLS ===
        _buildDomainPills(maxWidth: maxWidth),

        const SizedBox(height: 24),

        // === LOGIN BUTTON ===
        _buildLoginButton(hasValidEmail: hasValidEmail),

        // === MESSAGE ===
        if (_message != null) ...[const SizedBox(height: 20), _buildMessage()],
      ],
    );
  }

  /// Logo with fade + scale animation.
  Widget _buildLogo() {
    return FadeTransition(
      opacity: _titleOpacity,
      child: ScaleTransition(
        scale: _titleScale,
        child: AnimatedBuilder(
          animation: _logoShrinkScale,
          builder: (context, child) =>
              Transform.scale(scale: _logoShrinkScale.value, child: child),
          child: const BandRoadieLogo(height: 80),
        ),
      ),
    );
  }

  /// Email input field with label and validation error.
  Widget _buildEmailField() {
    return FadeTransition(
      opacity: _emailOpacity,
      child: SlideTransition(
        position: _emailSlide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Email address',
              style: TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            AutofillGroup(
              child: TextField(
                controller: _emailController,
                focusNode: _focusNode,
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {
                  _selectedDomain = null;
                  _validationError = null;
                }),
                onSubmitted: (_) => _handleSubmit(),
                decoration: InputDecoration(
                  hintText: 'you@email.com',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: _validationError != null
                        ? const BorderSide(color: Color(0xFFEF4444), width: 1.5)
                        : BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _validationError != null
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFF43F5E),
                      width: 1.5,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
              ),
            ),
            FieldHint(
              text: "We'll email you a secure login link.",
              controller: _emailHintController,
            ),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  _validationError!,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Domain pills row - horizontally scrollable, aligned to email field width.
  Widget _buildDomainPills({required double maxWidth}) {
    // PILL SNAP-ALIGNMENT:
    // The pills container uses the same maxWidth as the email field.
    // This ensures the pills row aligns perfectly with the input above.
    // Pills scroll horizontally within this fixed-width container.

    return FadeTransition(
      opacity: _pillsOpacity,
      child: SlideTransition(
        position: _pillsSlide,
        child: SizedBox(
          width: maxWidth,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: emailDomainShortcuts.asMap().entries.map((entry) {
                final index = entry.key;
                final domain = entry.value;
                final isSelected = _selectedDomain == domain;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index < emailDomainShortcuts.length - 1 ? 8 : 0,
                  ),
                  child: _DomainChip(
                    domain: domain,
                    isSelected: isSelected,
                    isEnabled: !_isLoading,
                    onTap: () => _applyDomainShortcut(domain),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// Login button with scale + fade animation.
  Widget _buildLoginButton({required bool hasValidEmail}) {
    return FadeTransition(
      opacity: _buttonOpacity,
      child: ScaleTransition(
        scale: _buttonScale,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isLoading || !hasValidEmail ? null : _sendMagicLink,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Email Login Link',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ),
    );
  }

  /// Success/error message container.
  Widget _buildMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _message!,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _message!.contains('Check your email')
              ? const Color(0xFF22C55E)
              : const Color(0xFFF59E0B),
          fontSize: 14,
        ),
      ),
    );
  }
}

// ============================================================================
// DOMAIN CHIP
// Individual tappable pill-shaped domain shortcut with selection state.
// ============================================================================

class _DomainChip extends StatelessWidget {
  final String domain;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  const _DomainChip({
    required this.domain,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF43F5E).withValues(alpha: 0.15)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(100), // Pill shape
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF43F5E)
                : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          domain,
          style: TextStyle(
            color: isEnabled
                ? (isSelected
                      ? const Color(0xFFFB7185)
                      : const Color(0xFF94A3B8))
                : const Color(0xFF475569),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

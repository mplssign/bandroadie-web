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

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/services/auth_debug_logger.dart';
import '../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../components/ui/email_domain_shortcut_bar.dart';
import '../../components/ui/field_hint.dart';
import '../../shared/utils/email_domain_helper.dart';
import 'auth_gate.dart';
import '../../app/constants/demo_credentials.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';

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

  // === DEMO LOGIN (Play Store easter egg) ===
  /// Number of times the logo has been tapped in the current sequence.
  int _logoTapCount = 0;

  /// Auto-reset timer — clears tap count after 3 seconds of inactivity.
  Timer? _logoTapResetTimer;

  // === MAGIC LINK COOLDOWN ===
  /// Cooldown timer to prevent rapid-fire magic link requests
  Timer? _cooldownTimer;

  /// Remaining cooldown seconds (0 = no cooldown active)
  int _cooldownSeconds = 0;

  /// Cooldown duration in seconds
  static const int _cooldownDuration = 60;

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

  /// Easter egg: 7 taps on the logo triggers Play Store demo login.
  /// Shows a subtle "X more..." hint from tap 3 onwards.
  /// Auto-resets after 3 seconds of inactivity.
  void _handleLogoTap() {
    // Cancel any pending reset
    _logoTapResetTimer?.cancel();

    setState(() {
      _logoTapCount++;
    });

    if (_logoTapCount >= 7) {
      setState(() {
        _logoTapCount = 0;
      });
      _triggerDemoLogin();
      return;
    }

    // Schedule reset after 3 seconds of inactivity
    _logoTapResetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _logoTapCount = 0;
        });
      }
    });
  }

  /// Performs email+password sign-in with the Play Store demo account.
  /// Called after 7 logo taps. AuthGate handles routing on success.
  Future<void> _triggerDemoLogin() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await supabase.auth.signInWithPassword(
        email: kDemoEmail,
        password: kDemoPassword,
      );
      // On success, authStateProvider fires signedIn and AuthGate routes
      // to AppShell. No further action needed here.
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = 'Demo login failed: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = 'Demo login failed. Please try again.';
        });
      }
    }
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
    // Shrink to 75% of the displayed size when keyboard is up
    _logoShrinkScale = Tween<double>(begin: 1.0, end: 0.75).animate(
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
    _emailSlide =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
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
    _pillsSlide =
        Tween<Offset>(begin: const Offset(0.2, 0), end: Offset.zero).animate(
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
    _logoTapResetTimer?.cancel();
    _cooldownTimer?.cancel();
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

  /// Starts the 60-second cooldown timer after sending a magic link
  void _startCooldownTimer() {
    setState(() {
      _cooldownSeconds = _cooldownDuration;
    });

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) {
          timer.cancel();
          _cooldownTimer = null;
        }
      });
    });
  }

  Future<void> _sendMagicLink() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() => _message = 'Please enter your email');
      return;
    }

    // Don't allow sending if cooldown is active
    if (_cooldownSeconds > 0) {
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      // Web: Redirect to /auth/confirm on the app subdomain
      // Native (Android, iOS, macOS): Use custom scheme (bandroadie://login-callback/)
      final String redirectUrl;
      if (kIsWeb) {
        redirectUrl = 'https://app.bandroadie.com/auth/confirm';
      } else {
        redirectUrl = 'bandroadie://login-callback/';
      }

      await supabase.auth.signInWithOtp(
        email: email,
        emailRedirectTo: redirectUrl,
      );

      // Start cooldown timer after successful send
      _startCooldownTimer();

      setState(() {
        _message = 'Check your email for the login link';
        _isLoading = false;
      });
    } on SocketException catch (e) {
      debugPrint('SocketException: No internet connection - $e');
      setState(() {
        _message =
            'No internet connection. Please check your connection and try again.';
        _isLoading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('TimeoutException: Request timed out - $e');
      setState(() {
        _message =
            'No internet connection. Please check your connection and try again.';
        _isLoading = false;
      });
    } on AuthException catch (e) {
      debugPrint('AuthException: ${e.message} (code: ${e.statusCode})');
      setState(() {
        _message = e.message.isNotEmpty
            ? 'Error: ${e.message}'
            : 'Authentication error. Check your email format.';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Unexpected error: $e');
      setState(() {
        _message =
            'Error: ${e.toString()}\n\nPlease try again or contact support.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // SAFEGUARD: If we detected an existing session, show loading
    // instead of login UI. AuthGate will handle the redirect.
    if (_sessionDetected) {
      return AppScaffold(
        backgroundColor: context.colors.background,
        body: Center(
          child: AppProgressIndicator(
            type: ProgressIndicatorType.circular,
            color: AppColors.primary,
          ),
        ),
      );
    }

    // KEYBOARD-AWARE CENTERING:
    // MediaQuery.viewInsets.bottom gives keyboard height.
    // We use AnimatedPadding to smoothly lift the content cluster.
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final emailText = _emailController.text.trim();
    final hasValidEmail = emailText.contains('@') && emailText.length > 3;

    return AppScaffold(
      backgroundColor: context.colors.background,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) => _buildContentCluster(
                        hasValidEmail: hasValidEmail,
                        maxWidth: constraints.maxWidth - 64,
                        availableHeight:
                            constraints.maxHeight - (keyboardHeight * 0.5),
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

  /// Builds the content cluster.
  ///
  /// Layout contract:
  ///   - Logo occupies the upper half of [availableHeight], centered within it.
  ///     This places the logo's vertical center at exactly half the distance
  ///     between the top of the screen and the top of the email field.
  ///   - Logo width is 90% of the email field width.
  ///   - Form elements start at the midpoint of the available screen height.
  Widget _buildContentCluster({
    required bool hasValidEmail,
    required double maxWidth,
    required double availableHeight,
  }) {
    final logoWidth = (maxWidth * 0.9).clamp(0.0, 600.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // === LOGO — centered in upper half ===
        SizedBox(
          height: availableHeight / 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(child: _buildLogo(logoWidth: logoWidth)),
              if (_logoTapCount >= 3 && _logoTapCount < 7)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    '${7 - _logoTapCount} more...',
                    style: TextStyle(
                      color: AppColors.primary.withValues(alpha: 0.6),
                      fontSize: AppFontSizes.caption,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),

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

        const SizedBox(height: 40),
      ],
    );
  }

  /// Logo with fade + scale animation and a rose glow bloom behind it.
  ///
  /// [logoWidth] is 90% of the email field width, passed from _buildContentCluster.
  Widget _buildLogo({required double logoWidth}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleLogoTap,
      child: FadeTransition(
        opacity: _titleOpacity,
        child: ScaleTransition(
          scale: _titleScale,
          child: AnimatedBuilder(
            animation: _logoShrinkScale,
            builder: (context, child) =>
                Transform.scale(scale: _logoShrinkScale.value, child: child),
            child: Image.asset(
              'assets/images/bandroadie_logo_stacked.png',
              width: logoWidth,
              fit: BoxFit.contain,
            ),
          ),
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
            Text(
              'Email address',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: AppFontSizes.subhead,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            AutofillGroup(
              child: AppTextField(
                controller: _emailController,
                focusNode: _focusNode,
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                hintText: 'you@email.com',
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                onChanged: (_) => setState(() {
                  _selectedDomain = null;
                  _validationError = null;
                }),
                onSubmitted: (_) => _handleSubmit(),
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
                    color: AppColors.error,
                    fontSize: AppFontSizes.caption,
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
          child: EmailDomainShortcutBar(
            controller: _emailController,
            selectedDomain: _selectedDomain,
            onDomainSelected: (domain) => _applyDomainShortcut(domain),
            enabled: !_isLoading,
          ),
        ),
      ),
    );
  }

  /// Login button with scale + fade animation.
  Widget _buildLoginButton({required bool hasValidEmail}) {
    final bool isDisabled =
        _isLoading || !hasValidEmail || _cooldownSeconds > 0;

    return FadeTransition(
      opacity: _buttonOpacity,
      child: ScaleTransition(
        scale: _buttonScale,
        child: AppButton(
          label: _cooldownSeconds > 0
              ? 'Resend in ${_cooldownSeconds}s'
              : 'Email Login Link',
          variant: AppButtonVariant.primary,
          onPressed: isDisabled ? null : _sendMagicLink,
          isLoading: _isLoading,
          fullWidth: true,
        ),
      ),
    );
  }

  /// Success/error message container.
  Widget _buildMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _message!,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _message!.contains('Check your email')
              ? context.colors.success
              : context.colors.warning,
          fontSize: AppFontSizes.subhead,
        ),
      ),
    );
  }
}

// ============================================================================
// DOMAIN CHIP
// Individual tappable pill-shaped domain shortcut with selection state.
// ============================================================================

import 'dart:math';
import 'dart:ui';

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:bandroadie/app/services/supabase_client.dart';

// ============================================================================
// ONBOARDING SCREEN
// Premium first-time user experience with cinematic intro, fluid wizard,
// micro-interactions, and completion celebration.
// ============================================================================

/// Design tokens scoped to the onboarding flow.
class _OB {
  _OB._();

  // Colors
  static const Color bg = Color(0xFF000000);
  static const Color surface = Color(0xFF1E293B);
  static const Color accent = Color(0xFFBE123C);
  static const Color accentLight = Color(0xFFF43F5E);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderMuted = Color(0xFF334155);
  static const Color fieldFill = Color(0xFF1A1A2E);

  // Pill
  static const double pillHeight = 38.0;
  static const double pillRadius = 19.0;

  // Day pill
  static const double daySize = 42.0;
  static const double dayRadius = 21.0;

  // Durations
  static const Duration logoFadeIn = Duration(milliseconds: 600);
  static const Duration taglineDelay = Duration(milliseconds: 500);
  static const Duration taglineFadeIn = Duration(milliseconds: 450);
  static const Duration holdDuration = Duration(milliseconds: 1200);
  static const Duration transitionOut = Duration(milliseconds: 700);

  // Wizard
  static const Duration stepTransition = Duration(milliseconds: 500);
  static const Curve springCurve = Curves.easeOutBack;
  static const Curve fadeCurve = Curves.easeOutCubic;
}

// Month names
const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

// Days per month
const _daysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/// The full first-time onboarding experience.
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onSkip;

  const OnboardingScreen({super.key, required this.onComplete, this.onSkip});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  // ── Phase control ──────────────────────────────────────────────────────
  // 0 = splash, 1 = wizard, 2 = completing
  int _phase = 0;

  // ── Splash animations ─────────────────────────────────────────────────
  late AnimationController _logoController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;

  late AnimationController _taglineController;
  late Animation<double> _taglineOpacity;
  late Animation<Offset> _taglineSlide;
  late Animation<double> _taglineBlur;

  late AnimationController _splashExitController;
  late Animation<double> _logoShrink;
  late Animation<double> _logoSlideUp;
  late Animation<double> _taglineFadeOut;
  late Animation<double> _wizardSlideUp;

  // ── Wizard animations ─────────────────────────────────────────────────
  late AnimationController _stepController;
  int _currentStep = 0;
  bool _goingForward = true;

  // ── Completion animations ─────────────────────────────────────────────
  late AnimationController _completionController;
  late Animation<double> _cardFade;
  late Animation<double> _logoReappear;
  late Animation<double> _dashboardSlide;
  late ConfettiController _confettiController;

  // ── Glow pulse for background ─────────────────────────────────────────
  late AnimationController _glowController;

  // ── Form state ─────────────────────────────────────────────────────────
  final _firstNameController = TextEditingController();
  final _zipController = TextEditingController();
  int? _selectedMonth;
  int? _selectedDay;

  // Validation
  bool _zipError = false;
  final _zipShakeController = ValueNotifier<int>(0);

  // Focus
  final _firstNameFocus = FocusNode();
  final _zipFocus = FocusNode();

  // Step definitions
  static const _totalSteps = 3; // Name, Zip, Birthday

  @override
  void initState() {
    super.initState();
    _initSplashAnimations();
    _initWizardAnimations();
    _initCompletionAnimations();
    _startSplashSequence();
  }

  void _initSplashAnimations() {
    // Logo: scale 0.85→1.0 + fade in, with bounce
    _logoController = AnimationController(
      vsync: this,
      duration: _OB.logoFadeIn,
    );
    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOut));

    // Tagline: fade in + slide up + blur→sharp
    _taglineController = AnimationController(
      vsync: this,
      duration: _OB.taglineFadeIn,
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineController, curve: Curves.easeOut),
    );
    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _taglineController,
            curve: Curves.easeOutCubic,
          ),
        );
    _taglineBlur = Tween<double>(begin: 4.0, end: 0.0).animate(
      CurvedAnimation(parent: _taglineController, curve: Curves.easeOut),
    );

    // Splash exit: logo shrinks/moves up, tagline fades, bg brightens, wizard slides up
    _splashExitController = AnimationController(
      vsync: this,
      duration: _OB.transitionOut,
    );
    _logoShrink = Tween<double>(begin: 1.0, end: 0.55).animate(
      CurvedAnimation(
        parent: _splashExitController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOutCubic),
      ),
    );
    _logoSlideUp = Tween<double>(begin: 0.0, end: -120.0).animate(
      CurvedAnimation(
        parent: _splashExitController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOutCubic),
      ),
    );
    _taglineFadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _splashExitController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    _wizardSlideUp = Tween<double>(begin: 200.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _splashExitController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // Background glow pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  void _initWizardAnimations() {
    _stepController = AnimationController(
      vsync: this,
      duration: _OB.stepTransition,
    )..value = 1.0; // Start fully visible
  }

  void _initCompletionAnimations() {
    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _cardFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );
    _logoReappear = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.2, 0.5, curve: Curves.easeOut),
      ),
    );
    _dashboardSlide = Tween<double>(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _startSplashSequence() async {
    // Brief initial delay for screen to settle
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // 1. Logo fade in + scale
    _logoController.forward();

    // 2. Tagline after delay
    await Future.delayed(_OB.taglineDelay);
    if (!mounted) return;
    _taglineController.forward();

    // 3. Hold
    await Future.delayed(_OB.taglineFadeIn + _OB.holdDuration);
    if (!mounted) return;

    // 4. Transition to wizard
    _splashExitController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _phase = 1);
  }

  void _goToStep(int step) {
    if (step == _currentStep) return;
    if (step < 0 || step >= _totalSteps) return;

    setState(() {
      _goingForward = step > _currentStep;
      _currentStep = step;
    });

    _stepController.value = 0.0;
    _stepController.forward();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    } else {
      _onDone();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  Future<void> _onDone() async {
    // Validate zip if provided
    final zip = _zipController.text.trim();
    if (zip.isNotEmpty && !_isValidZip(zip)) {
      // Navigate to zip step and shake
      _goToStep(1);
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() => _zipError = true);
      _zipShakeController.value++;
      return;
    }

    setState(() => _phase = 2);

    // Save profile
    await _saveProfile();

    // Play celebration
    _confettiController.play();
    _completionController.forward();

    // Wait for completion animation, then transition
    // Use the same path as "Skip for now" so the user lands on the
    // Welcome backstage screen. Fall back to onComplete if onSkip is null.
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    if (widget.onSkip != null) {
      widget.onSkip!();
    } else {
      widget.onComplete();
    }
  }

  void _onSkip() {
    widget.onSkip?.call();
  }

  Future<void> _saveProfile() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final userEmail = supabase.auth.currentUser?.email ?? '';

      String? birthdayStr;
      if (_selectedMonth != null && _selectedDay != null) {
        final month = (_selectedMonth! + 1).toString().padLeft(2, '0');
        final day = _selectedDay!.toString().padLeft(2, '0');
        birthdayStr = '2000-$month-$day';
      }

      await supabase.from('users').upsert({
        'id': userId,
        'email': userEmail,
        'first_name': _firstNameController.text.trim(),
        'zip': _zipController.text.trim(),
        'birthday': birthdayStr,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (kDebugMode) {
        debugPrint('[Onboarding] Profile saved for user=$userId');
      }
    } catch (e) {
      debugPrint('[Onboarding] Save failed: $e');
    }
  }

  bool _isValidZip(String zip) {
    return RegExp(r'^\d{5}(-\d{4})?$').hasMatch(zip);
  }

  @override
  void dispose() {
    _logoController.dispose();
    _taglineController.dispose();
    _splashExitController.dispose();
    _glowController.dispose();
    _stepController.dispose();
    _completionController.dispose();
    _confettiController.dispose();
    _firstNameController.dispose();
    _zipController.dispose();
    _firstNameFocus.dispose();
    _zipFocus.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _OB.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Animated background glow
          _buildBackgroundGlow(),

          // Main content
          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _splashExitController,
                _completionController,
              ]),
              builder: (context, _) => _buildContent(),
            ),
          ),

          // Confetti overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 30,
              maxBlastForce: 20,
              minBlastForce: 8,
              emissionFrequency: 0.06,
              gravity: 0.15,
              colors: const [
                _OB.accent,
                _OB.accentLight,
                Color(0xFFEC4899),
                Color(0xFFF97316),
                Color(0xFFFBBF24),
                Color(0xFF34D399),
                Color(0xFF60A5FA),
                Colors.white,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundGlow() {
    return AnimatedBuilder(
      animation: Listenable.merge([_glowController, _splashExitController]),
      builder: (context, _) {
        final glowIntensity = 0.08 + 0.04 * sin(_glowController.value * pi * 2);
        final exitProgress = _splashExitController.value;
        // Fade the glow out as the wizard slides in
        final glowAlpha = (glowIntensity * (1.0 - exitProgress)).clamp(
          0.0,
          1.0,
        );

        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.3),
              radius: 1.2,
              colors: [
                _OB.accent.withValues(alpha: glowAlpha),
                _OB.bg,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    if (_phase == 0) {
      return _buildSplash();
    } else if (_phase == 2) {
      return _buildCompletion();
    }
    return _buildWizard();
  }

  // ══════════════════════════════════════════════════════════════════════
  // PHASE 0: SPLASH
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildSplash() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _logoController,
        _taglineController,
        _splashExitController,
      ]),
      builder: (context, _) {
        final exitProgress = _splashExitController.value;

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Transform.translate(
                  offset: Offset(0, _logoSlideUp.value),
                  child: Transform.scale(
                    scale:
                        _logoScale.value *
                        (exitProgress > 0 ? _logoShrink.value : 1.0),
                    child: Opacity(
                      opacity: _logoOpacity.value,
                      child: SvgPicture.asset(
                        'assets/images/bandroadie_logo_optimized.svg',
                        height: 90,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Tagline
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SlideTransition(
                  position: _taglineSlide,
                  child: Opacity(
                    opacity:
                        _taglineOpacity.value *
                        (exitProgress > 0 ? _taglineFadeOut.value : 1.0),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: _taglineBlur.value,
                        sigmaY: _taglineBlur.value,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Keeping Your Band in Tune… On Stage and Off',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                            height: 1.5,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PHASE 1: WIZARD
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildWizard() {
    return AnimatedBuilder(
      animation: _splashExitController,
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, _wizardSlideUp.value),
          child: Opacity(
            opacity: _splashExitController.value.clamp(0.0, 1.0),
            child: Column(
              children: [
                // Mini logo at top
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AnimatedBuilder(
                    animation: _splashExitController,
                    builder: (context, _) {
                      return Opacity(
                        opacity: _splashExitController.value.clamp(0.0, 1.0),
                        child: SvgPicture.asset(
                          'assets/images/bandroadie_logo_optimized.svg',
                          height: 36,
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Progress indicator
                _buildProgressDots(),

                // Card area
                Expanded(child: _buildStepCard()),

                // Action bar
                _buildActionBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_totalSteps, (i) {
          final isActive = i == _currentStep;
          final isPast = i < _currentStep;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: isActive
                  ? _OB.accent
                  : isPast
                  ? _OB.accent.withValues(alpha: 0.5)
                  : _OB.borderMuted,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepCard() {
    return AnimatedBuilder(
      animation: _stepController,
      builder: (context, _) {
        // Spring-based slide + opacity
        final progress = _stepController.value;
        final curve = _OB.springCurve;
        final curvedProgress = curve.transform(progress);

        // Outgoing step slides away
        final direction = _goingForward ? -1.0 : 1.0;
        // Incoming step slides in from opposite direction
        final slideOffset = (1.0 - curvedProgress) * -direction * 80;
        final opacity = _OB.fadeCurve.transform(progress).clamp(0.0, 1.0);

        return Transform.translate(
          offset: Offset(slideOffset, 0),
          child: Opacity(
            opacity: opacity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildCurrentStep(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildNameStep();
      case 1:
        return _buildZipStep();
      case 2:
        return _buildBirthdayStep();
      default:
        return const SizedBox();
    }
  }

  // ── Step 1: Name ──────────────────────────────────────────────────────

  Widget _buildNameStep() {
    return _StepCard(
      title: "What should we call you?",
      subtitle: "So your bandmates know who you are.",
      child: _AnimatedTextField(
        controller: _firstNameController,
        focusNode: _firstNameFocus,
        label: 'First Name',
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _nextStep(),
      ),
    );
  }

  // ── Step 2: Zip ───────────────────────────────────────────────────────

  Widget _buildZipStep() {
    return _StepCard(
      title: "Where are you based?",
      subtitle: "Helps us find nearby gigs and venues.",
      child: _ShakeWidget(
        trigger: _zipShakeController,
        child: _AnimatedTextField(
          controller: _zipController,
          focusNode: _zipFocus,
          label: 'Zip Code',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          errorText: _zipError ? 'Enter a valid 5-digit zip code' : null,
          onChanged: (val) {
            if (_zipError && val.length == 5) {
              setState(() => _zipError = false);
            }
          },
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _nextStep(),
        ),
      ),
    );
  }

  // ── Step 3: Birthday ──────────────────────────────────────────────────

  Widget _buildBirthdayStep() {
    final dayCount = _selectedMonth != null
        ? _daysInMonth[_selectedMonth!]
        : 31;

    return _StepCard(
      title: "When's your birthday?",
      subtitle: "We'll make sure your band remembers.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month label
          Text(
            'Month',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _OB.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          // Month pills
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(12, (i) {
              final isSelected = _selectedMonth == i;
              return _AnimatedPill(
                label: _months[i],
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedMonth = i;
                    // Reset day if it exceeds new month's days
                    if (_selectedDay != null &&
                        _selectedDay! > _daysInMonth[i]) {
                      _selectedDay = null;
                    }
                  });
                },
              );
            }),
          ),

          const SizedBox(height: 24),

          // Day label
          Text(
            'Day',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _OB.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          // Day pills – grid layout
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(dayCount, (i) {
              final day = i + 1;
              final isSelected = _selectedDay == day;
              return _AnimatedDayPill(
                day: day,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedDay = day),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Action Bar ────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    final isFirstStep = _currentStep == 0;
    final isLastStep = _currentStep == _totalSteps - 1;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _OB.bg.withValues(alpha: 0.0),
            _OB.bg.withValues(alpha: 0.8),
            _OB.bg,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Buttons row – equal width
          Row(
            children: [
              // Back button
              Expanded(
                child: _ActionButton(
                  label: 'Back',
                  isEnabled: !isFirstStep,
                  isPrimary: false,
                  onTap: isFirstStep ? null : _prevStep,
                ),
              ),
              const SizedBox(width: 16),
              // Next / Done button
              Expanded(
                child: _ActionButton(
                  label: isLastStep ? 'Done' : 'Next',
                  isEnabled: true,
                  isPrimary: true,
                  onTap: _nextStep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Skip link – centered, white text
          if (widget.onSkip != null) _SkipLink(onTap: _onSkip),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PHASE 2: COMPLETION
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildCompletion() {
    return AnimatedBuilder(
      animation: _completionController,
      builder: (context, _) {
        return Stack(
          children: [
            // Fading wizard card
            Opacity(opacity: _cardFade.value, child: _buildWizard()),

            // Logo reappears
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: _logoReappear.value,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * _logoReappear.value,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: SvgPicture.asset(
                          'assets/images/bandroadie_logo_optimized.svg',
                          height: 60,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Opacity(
                    opacity: (_logoReappear.value - 0.3).clamp(0.0, 1.0) / 0.7,
                    child: Text(
                      "You're all set!",
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: _OB.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Dashboard slide up indicator
            Positioned(
              bottom: 60 + _dashboardSlide.value,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: (1.0 - (_dashboardSlide.value / 60.0)).clamp(0.0, 1.0),
                child: Center(
                  child: Text(
                    'Entering your dashboard…',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: _OB.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// REUSABLE COMPONENTS
// ════════════════════════════════════════════════════════════════════════════

/// Step card wrapper with title and subtitle.
class _StepCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _StepCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: _OB.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: _OB.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        child,
        const SizedBox(height: 40),
      ],
    );
  }
}

/// Animated text field with floating label, focus glow, and smooth cursor.
class _AnimatedTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _AnimatedTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
    this.errorText,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<_AnimatedTextField> createState() => _AnimatedTextFieldState();
}

class _AnimatedTextFieldState extends State<_AnimatedTextField>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _isFocused = widget.focusNode.hasFocus);
    if (widget.focusNode.hasFocus) {
      _glowController.forward();
    } else {
      _glowController.reverse();
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowOpacity = _glowController.value * 0.3;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (glowOpacity > 0)
                BoxShadow(
                  color: _OB.accent.withValues(alpha: glowOpacity),
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
            ],
          ),
          child: child,
        );
      },
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        style: GoogleFonts.dmSans(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: _OB.textPrimary,
        ),
        cursorColor: _OB.accent,
        cursorWidth: 2,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: _isFocused ? _OB.accent : _OB.textMuted,
          ),
          floatingLabelStyle: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _OB.accent,
          ),
          errorText: widget.errorText,
          errorStyle: GoogleFonts.dmSans(
            fontSize: 13,
            color: const Color(0xFFEF4444),
          ),
          filled: true,
          fillColor: _OB.fieldFill,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _OB.borderMuted, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _OB.accent, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
          ),
        ),
      ),
    );
  }
}

/// Shake animation widget – triggers shake when [trigger] value changes.
class _ShakeWidget extends StatefulWidget {
  final ValueNotifier<int> trigger;
  final Widget child;

  const _ShakeWidget({required this.trigger, required this.child});

  @override
  State<_ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<_ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _offsetAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -3), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -3, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    widget.trigger.addListener(_onShake);
  }

  void _onShake() {
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_onShake);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_offsetAnimation.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Animated month pill with scale pop on selection.
class _AnimatedPill extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_AnimatedPill> createState() => _AnimatedPillState();
}

class _AnimatedPillState extends State<_AnimatedPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
        );
  }

  @override
  void didUpdateWidget(_AnimatedPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _scaleController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: _OB.pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.isSelected ? _OB.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(_OB.pillRadius),
            border: Border.all(
              color: _OB.accent,
              width: widget.isSelected ? 1.5 : 1,
            ),
          ),
          child: Align(
            widthFactor: 1.0,
            child: Text(
              widget.label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: widget.isSelected ? Colors.white : _OB.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated day pill with scale pop.
class _AnimatedDayPill extends StatefulWidget {
  final int day;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnimatedDayPill({
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_AnimatedDayPill> createState() => _AnimatedDayPillState();
}

class _AnimatedDayPillState extends State<_AnimatedDayPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
        );
  }

  @override
  void didUpdateWidget(_AnimatedDayPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _scaleController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: _OB.daySize,
          height: _OB.daySize,
          decoration: BoxDecoration(
            color: widget.isSelected ? _OB.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(_OB.dayRadius),
            border: Border.all(
              color: _OB.accent,
              width: widget.isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '${widget.day}',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: widget.isSelected
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: widget.isSelected ? Colors.white : _OB.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary / secondary action button with micro-interactions.
class _ActionButton extends StatefulWidget {
  final String label;
  final bool isEnabled;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.isEnabled,
    required this.isPrimary,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.isEnabled;
    final isPrimary = widget.isPrimary;

    return GestureDetector(
      onTapDown: isEnabled ? (_) => _onPressDown() : null,
      onTapUp: isEnabled ? (_) => _onPressUp() : null,
      onTapCancel: isEnabled ? _onPressCancel : null,
      child: AnimatedBuilder(
        animation: _pressScale,
        builder: (context, child) {
          return Transform.scale(scale: _pressScale.value, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 52,
          decoration: BoxDecoration(
            gradient: isPrimary && isEnabled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_OB.accent, _OB.accentLight],
                  )
                : null,
            color: !isPrimary
                ? (isEnabled ? _OB.surface : _OB.surface.withValues(alpha: 0.3))
                : null,
            borderRadius: BorderRadius.circular(12),
            border: !isPrimary
                ? Border.all(
                    color: isEnabled
                        ? _OB.borderMuted
                        : _OB.borderMuted.withValues(alpha: 0.3),
                  )
                : null,
            boxShadow: isPrimary && isEnabled
                ? [
                    BoxShadow(
                      color: _OB.accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isPrimary
                    ? Colors.white
                    : (isEnabled ? _OB.textPrimary : _OB.textMuted),
              ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }

  void _onPressDown() {
    _pressController.forward();
  }

  void _onPressUp() {
    _pressController.reverse();
    widget.onTap?.call();
  }

  void _onPressCancel() {
    _pressController.reverse();
  }
}

/// "Skip for now" animated text link with underline on press.
class _SkipLink extends StatefulWidget {
  final VoidCallback onTap;

  const _SkipLink({required this.onTap});

  @override
  State<_SkipLink> createState() => _SkipLinkState();
}

class _SkipLinkState extends State<_SkipLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isHovered = true),
      onTapUp: (_) {
        setState(() => _isHovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isHovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _isHovered
                ? Colors.white
                : Colors.white.withValues(alpha: 0.7),
            decoration: _isHovered
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: Colors.white.withValues(alpha: 0.5),
          ),
          child: const Text('Skip for now'),
        ),
      ),
    );
  }
}

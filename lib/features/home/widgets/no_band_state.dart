import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// NO BAND STATE
// Shown when user has zero band memberships. Includes staggered entrance
// animations with rubberband feel for the CTA buttons.
// ============================================================================

class NoBandState extends StatefulWidget {
  const NoBandState({super.key});

  @override
  State<NoBandState> createState() => _NoBandStateState();
}

class _NoBandStateState extends State<NoBandState>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _buttonController;

  late Animation<double> _iconFade;
  late Animation<Offset> _iconSlide;
  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;
  late Animation<double> _bodyFade;
  late Animation<double> _createButtonScale;
  late Animation<double> _joinButtonFade;

  @override
  void initState() {
    super.initState();

    // Main entrance controller
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Button pop controller with rubberband
    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Icon: fade + slide up
    _iconFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _iconSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
          ),
        );

    // Title: staggered fade + slide
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
          ),
        );

    // Body fade
    _bodyFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.7, curve: Curves.easeOut),
      ),
    );

    // Create button with rubberband scale
    _createButtonScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _buttonController, curve: AppCurves.rubberband),
    );

    // Join button fade in
    _joinButtonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _buttonController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    // Start animations with stagger
    _entranceController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _buttonController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.space32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Animated music icon with glow
                SlideTransition(
                  position: _iconSlide,
                  child: FadeTransition(
                    opacity: _iconFade,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 56,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.space40),

                // Animated title
                SlideTransition(
                  position: _titleSlide,
                  child: FadeTransition(
                    opacity: _titleFade,
                    child: Text(
                      'Welcome, Roadie!',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.displayLarge.copyWith(fontSize: 28),
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.space16),

                // Animated body copy with roadie humor
                FadeTransition(
                  opacity: _bodyFade,
                  child: Text(
                    "You're backstage, but your band's MIA.\n"
                    "Start your own crew or bug your drummer\n"
                    "(they're late, shocker) to invite you.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 16,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.space48),

                // Create Band button with rubberband pop
                ScaleTransition(
                  scale: _createButtonScale,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.space16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            Spacing.buttonRadius,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded, size: 20),
                          const SizedBox(width: Spacing.space8),
                          Text(
                            'Create a Band',
                            style: AppTextStyles.button.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.space16),

                // Join Band button
                FadeTransition(
                  opacity: _joinButtonFade,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.space16,
                        ),
                        side: BorderSide(
                          color: AppColors.borderMuted,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            Spacing.buttonRadius,
                          ),
                        ),
                      ),
                      child: Text(
                        'Join Existing Band',
                        style: AppTextStyles.button.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.space24),

                // Subtle hint
                FadeTransition(
                  opacity: _bodyFade,
                  child: Text(
                    'Got an invite code? Tap "Join" above.',
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textDisabled,
                    ),
                  ),
                ),

                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

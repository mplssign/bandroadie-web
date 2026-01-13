import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';

// ============================================================================
// EMPTY SETLISTS STATE
// Shown when user has no setlists created yet.
// Uses BrandActionButton for consistent styling with other empty states.
// ============================================================================

class EmptySetlistsState extends StatefulWidget {
  final VoidCallback? onCreateSetlist;

  const EmptySetlistsState({super.key, this.onCreateSetlist});

  @override
  State<EmptySetlistsState> createState() => _EmptySetlistsStateState();
}

class _EmptySetlistsStateState extends State<EmptySetlistsState>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: AppDurations.entrance,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: AppCurves.ease,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: AppCurves.slideIn,
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced motion accessibility setting
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _entranceController.value = 1.0; // Skip animation
    } else if (!_entranceController.isCompleted) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _entranceController.forward();
      });
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
              vertical: Spacing.space48,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.queue_music_rounded,
                    color: AppColors.textMuted,
                    size: 40,
                  ),
                ),

                const SizedBox(height: Spacing.space24),

                // Title
                Text(
                  'No Setlists Yet',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: Spacing.space12),

                // Subtitle
                Text(
                  'Create your first setlist to organize your songs for gigs and rehearsals.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: Spacing.space32),

                // CTA Button - consistent with other empty states
                BrandActionButton(
                  label: '+ Create Setlist',
                  onPressed: widget.onCreateSetlist,
                  icon: Icons.add_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

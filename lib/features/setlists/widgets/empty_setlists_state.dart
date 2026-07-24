import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/brand_action_button.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

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
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    AppIcons.setlists,
                    color: context.colors.textMuted,
                    size: 40,
                  ),
                ),

                const SizedBox(height: Spacing.space24),

                // Title
                Text(
                  'No Setlists Yet',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: AppFontSizes.title2,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),

                const SizedBox(height: Spacing.space12),

                // Subtitle
                Text(
                  'Create your first setlist to organize your songs for gigs and rehearsals.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),

                const SizedBox(height: Spacing.space32),

                // CTA Button - consistent with other empty states
                BrandActionButton(
                  label: '+ Create Setlist',
                  onPressed: widget.onCreateSetlist,
                  icon: AppIcons.add,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

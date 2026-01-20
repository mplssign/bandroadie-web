import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/design_tokens.dart';
import 'empty_section_card.dart';
import 'home_app_bar.dart';
import 'quick_actions_row.dart';
import 'section_header.dart';

// ============================================================================
// EMPTY HOME STATE
// Shown when user has a band but no gigs/rehearsals scheduled.
// Features staggered entrance animations for visual polish.
// ============================================================================

class EmptyHomeState extends StatefulWidget {
  final String bandName;
  final String? bandAvatarColor;
  final String? bandImageUrl;
  final File? localImageFile;
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;
  final VoidCallback? onScheduleRehearsal;
  final VoidCallback? onCreateGig;
  final VoidCallback? onCreateSetlist;
  final VoidCallback? onBlockOut;

  const EmptyHomeState({
    super.key,
    required this.bandName,
    required this.onMenuTap,
    required this.onAvatarTap,
    this.bandAvatarColor,
    this.bandImageUrl,
    this.localImageFile,
    this.onScheduleRehearsal,
    this.onCreateGig,
    this.onCreateSetlist,
    this.onBlockOut,
  });

  @override
  State<EmptyHomeState> createState() => _EmptyHomeStateState();
}

class _EmptyHomeStateState extends State<EmptyHomeState>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late List<Animation<double>> _fadeAnimations;
  late List<Animation<Offset>> _slideAnimations;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    // Create staggered animations for 4 sections
    _fadeAnimations = List.generate(4, (index) {
      final start = index * 0.15;
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );
    });

    _slideAnimations = List.generate(4, (index) {
      final start = index * 0.15;
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start, end, curve: AppCurves.slideIn),
        ),
      );
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedSection(int index, Widget child) {
    return SlideTransition(
      position: _slideAnimations[index],
      child: FadeTransition(opacity: _fadeAnimations[index], child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Note: No Scaffold here - the parent (AppShell or HomeScreen) provides it
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // App bar - wrapped in SliverToBoxAdapter since HomeAppBar is not a sliver
        SliverToBoxAdapter(
          child: HomeAppBar(
            bandName: widget.bandName,
            onMenuTap: widget.onMenuTap,
            onAvatarTap: widget.onAvatarTap,
            bandAvatarColor: widget.bandAvatarColor,
            bandImageUrl: widget.bandImageUrl,
            localImageFile: widget.localImageFile,
          ),
        ),

        // Main content
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Spacing.space32),

                // Empty hero message
                _buildAnimatedSection(0, _EmptyHeroSection()),

                const SizedBox(height: 34),

                // Rehearsal section
                _buildAnimatedSection(
                  1,
                  EmptySectionCard(
                    title: 'No Rehearsal Scheduled',
                    subtitle: 'The stage is empty and the amps are cold.',
                    buttonLabel: 'Schedule Rehearsal',
                    onButtonPressed: widget.onScheduleRehearsal,
                  ),
                ),

                const SizedBox(height: 34),

                // Gigs section
                _buildAnimatedSection(
                  2,
                  EmptySectionCard(
                    title: 'No Upcoming Gigs',
                    subtitle:
                        'The spotlight awaits — time to book your next show.',
                    buttonLabel: 'Create Gig',
                    onButtonPressed: widget.onCreateGig,
                  ),
                ),

                const SizedBox(height: 17),

                // Quick actions
                _buildAnimatedSection(
                  3,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Quick Actions'),
                      const SizedBox(height: Spacing.space16),
                      QuickActionsRow(
                        onScheduleRehearsal: widget.onScheduleRehearsal,
                        onCreateGig: widget.onCreateGig,
                        onCreateSetlist: widget.onCreateSetlist,
                        onBlockOut: widget.onBlockOut,
                      ),
                    ],
                  ),
                ),

                // Bottom padding for nav bar (extra space to scroll past)
                SizedBox(
                  height:
                      Spacing.space48 +
                      Spacing.bottomNavHeight +
                      MediaQuery.of(context).padding.bottom +
                      32, // Extra scroll clearance
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Hero section for empty state with encouraging copy
class _EmptyHeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.space24),
      decoration: BrandButton.decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: AppColors.accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: Spacing.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Let's get this show started!",
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Spacing.space4),
                    Text(
                      'Add your first gig or rehearsal below.',
                      style: AppTextStyles.cardSubtitle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

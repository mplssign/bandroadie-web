import 'dart:io';

import 'package:flutter/material.dart';

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
  final VoidCallback? onCreateRehearsal;
  final VoidCallback? onCreateGig;
  final VoidCallback? onCreateSetlist;

  const EmptyHomeState({
    super.key,
    required this.bandName,
    required this.onMenuTap,
    required this.onAvatarTap,
    this.bandAvatarColor,
    this.bandImageUrl,
    this.localImageFile,
    this.onCreateRehearsal,
    this.onCreateGig,
    this.onCreateSetlist,
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

    // Create staggered animations for 3 sections
    _fadeAnimations = List.generate(3, (index) {
      final start = index * 0.15;
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );
    });

    _slideAnimations = List.generate(3, (index) {
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
                const SizedBox(height: 34),

                // Rehearsal section
                _buildAnimatedSection(
                  0,
                  EmptySectionCard(
                    title: 'No Rehearsal Scheduled',
                    subtitle: 'The stage is empty and the amps are cold.',
                    buttonLabel: 'Create Rehearsal',
                    onButtonPressed: widget.onCreateRehearsal,
                  ),
                ),

                const SizedBox(height: 34),

                // Gigs section
                _buildAnimatedSection(
                  1,
                  EmptySectionCard(
                    title: 'No Upcoming Gigs',
                    subtitle:
                        'The spotlight awaits — time to book your next show.',
                    buttonLabel: 'Create Gig',
                    onButtonPressed: widget.onCreateGig,
                  ),
                ),

                const SizedBox(height: 17),

                // Quick actions (only shown when at least one action is available)
                if (widget.onCreateRehearsal != null ||
                    widget.onCreateGig != null ||
                    widget.onCreateSetlist != null)
                  _buildAnimatedSection(
                    2,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Quick Actions'),
                        const SizedBox(height: Spacing.space16),
                        QuickActionsRow(
                          onAddEvent:
                              widget.onCreateRehearsal ?? widget.onCreateGig,
                          onCreateSetlist: widget.onCreateSetlist,
                          showAddEvent: widget.onCreateRehearsal != null ||
                              widget.onCreateGig != null,
                          showCreateSetlist: widget.onCreateSetlist != null,
                        ),
                      ],
                    ),
                  ),

                // Bottom padding for nav bar (extra space to scroll past)
                SizedBox(
                  height: Spacing.space48 +
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

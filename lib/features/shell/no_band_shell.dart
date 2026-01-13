import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../bands/active_band_controller.dart';
import '../bands/create_band_screen.dart';
import '../feedback/bug_report_screen.dart';
import '../home/widgets/band_switcher.dart';
import '../home/widgets/side_drawer.dart';
import '../profile/my_profile_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../tips/tips_and_tricks_screen.dart';
import 'overlay_state.dart';

// ============================================================================
// NO BAND SHELL
// Shown when user has completed profile but has no bands.
// Has menu and band switcher access but NO footer tabs.
// User can create a band or wait for an invite.
// ============================================================================

class NoBandShell extends ConsumerWidget {
  const NoBandShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlayState = ref.watch(overlayStateProvider);
    final overlayNotifier = ref.read(overlayStateProvider.notifier);
    final bandState = ref.watch(activeBandProvider);

    // Get user info for drawer
    final user = Supabase.instance.client.auth.currentUser;
    final userEmail = user?.email ?? '';

    // Watch the user profile provider to get first_name and last_name from database
    final profileAsync = ref.watch(userProfileProvider);
    final userName = profileAsync.when(
      data: (profile) {
        if (profile == null) return '';
        final first = profile.firstName ?? '';
        final last = profile.lastName ?? '';
        return [first, last].where((s) => s.isNotEmpty).join(' ');
      },
      loading: () => '',
      error: (_, __) => '',
    );

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Stack(
        children: [
          // Welcome content (no footer)
          Positioned.fill(
            child: _NoBandContent(
              onOpenMenu: () => overlayNotifier.openMenuDrawer(),
              onOpenBandSwitcher: () => overlayNotifier.openBandSwitcher(),
            ),
          ),

          // Menu drawer overlay
          if (overlayState == ActiveOverlay.menuDrawer)
            _MenuDrawerLayer(
              isOpen: true,
              onClose: overlayNotifier.closeOverlay,
              userName: userName,
              userEmail: userEmail,
            ),

          // Band switcher overlay (for creating new band)
          if (overlayState == ActiveOverlay.bandSwitcher)
            _BandSwitcherLayer(
              isOpen: true,
              onClose: overlayNotifier.closeOverlay,
              bands: bandState.userBands,
              activeBandId: bandState.activeBand?.id,
            ),
        ],
      ),
    );
  }
}

/// The welcome content shown when user has no bands
class _NoBandContent extends StatefulWidget {
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenBandSwitcher;

  const _NoBandContent({
    required this.onOpenMenu,
    required this.onOpenBandSwitcher,
  });

  @override
  State<_NoBandContent> createState() => _NoBandContentState();
}

class _NoBandContentState extends State<_NoBandContent>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _buttonController;

  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _logoScale;
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

    // Logo: fade + subtle slide up + subtle scale
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
          ),
        );
    _logoScale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
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
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar with menu and band switcher icons
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.space16,
                vertical: Spacing.space8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Menu button
                  IconButton(
                    icon: const Icon(
                      Icons.menu_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: widget.onOpenMenu,
                  ),
                  // Band switcher button (to create band)
                  IconButton(
                    icon: const Icon(
                      Icons.groups_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: widget.onOpenBandSwitcher,
                  ),
                ],
              ),
            ),

            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.space32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated logo with subtle fade, slide, and scale
                    SlideTransition(
                      position: _logoSlide,
                      child: FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Image.asset(
                            'assets/images/bandroadie_horiz.png',
                            height: 64,
                            fit: BoxFit.contain,
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
                          'Welcome backstage!',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.displayLarge.copyWith(
                            fontSize: 28,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: Spacing.space16),

                    // Animated body copy
                    FadeTransition(
                      opacity: _bodyFade,
                      child: Text(
                        'Create your band or ask a fellow\nbandmate to invite you.',
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
                          onPressed: () {
                            // Use custom fade+slide transition
                            Navigator.of(context).push(
                              fadeSlideRoute(page: const CreateBandScreen()),
                            );
                          },
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
                          child: Text(
                            'Create a Band',
                            style: AppTextStyles.button.copyWith(fontSize: 16),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: Spacing.space16),

                    // Secondary text
                    FadeTransition(
                      opacity: _joinButtonFade,
                      child: Text(
                        'Or wait for an invite from your band',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Menu drawer layer for NoBandShell
class _MenuDrawerLayer extends ConsumerWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final String userName;
  final String userEmail;

  const _MenuDrawerLayer({
    required this.isOpen,
    required this.onClose,
    required this.userName,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DrawerOverlayContent(
      isOpen: isOpen,
      onClose: onClose,
      userName: userName,
      userEmail: userEmail,
      onProfileTap: () {
        onClose();
        // Use custom fade+slide transition for smooth navigation
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const MyProfileScreen()));
      },
      onSettingsTap: () {
        onClose();
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const SettingsScreen()));
      },
      onTipsAndTricksTap: () {
        onClose();
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const TipsAndTricksScreen()));
      },
      onReportBugsTap: () {
        onClose();
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const BugReportScreen()));
      },
      onLogOutTap: () async {
        onClose();
        await Supabase.instance.client.auth.signOut();
      },
    );
  }
}

/// Band switcher layer for NoBandShell (primarily for creating new band)
class _BandSwitcherLayer extends ConsumerWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final List<Band> bands;
  final String? activeBandId;

  const _BandSwitcherLayer({
    required this.isOpen,
    required this.onClose,
    required this.bands,
    this.activeBandId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BandSwitcherOverlayContent(
      isOpen: isOpen,
      onClose: onClose,
      bands: bands,
      activeBandId: activeBandId,
      onBandSelected: (band) {
        onClose();
        ref.read(activeBandProvider.notifier).selectBand(band);
      },
      onCreateBand: () {
        onClose();
        // Use custom fade+slide transition for smooth navigation
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const CreateBandScreen()));
      },
      onEditBand: () {
        // No active band to edit in this state
        onClose();
      },
    );
  }
}

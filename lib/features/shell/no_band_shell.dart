import 'dart:convert';

import 'package:confetti/confetti.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/shared/widgets/animated_logo.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../bands/create_band_screen.dart';
import '../feedback/bug_report_screen.dart';
import '../home/widgets/band_switcher.dart';
import '../home/widgets/side_drawer.dart';
import '../profile/my_profile_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/data_backup_service.dart';
import '../settings/settings_screen.dart';
import '../tips/tips_and_tricks_screen.dart';
import 'overlay_state.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// NO BAND SHELL
// ============================================================================

class NoBandShell extends ConsumerWidget {
  final bool isNewUser;

  const NoBandShell({super.key, this.isNewUser = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlayState = ref.watch(overlayStateProvider);
    final overlayNotifier = ref.read(overlayStateProvider.notifier);
    final bandState = ref.watch(activeBandProvider);

    final user = Supabase.instance.client.auth.currentUser;
    final userEmail = user?.email ?? '';

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

    final userBands = bandState.userBands;
    final activeBandId = bandState.activeBand?.id;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _NoBandContent(
              onOpenMenu: () => overlayNotifier.openMenuDrawer(),
              onOpenBandSwitcher: userBands.isNotEmpty
                  ? () => overlayNotifier.openBandSwitcher()
                  : null,
              isNewUser: isNewUser,
              onRestoreSuccess: () {
                ref.read(activeBandProvider.notifier).loadUserBands();
              },
            ),
          ),
          if (overlayState == ActiveOverlay.menuDrawer)
            _MenuDrawerLayer(
              isOpen: true,
              onClose: overlayNotifier.closeOverlay,
              userName: userName,
              userEmail: userEmail,
            ),
          if (overlayState == ActiveOverlay.bandSwitcher)
            _BandSwitcherLayer(
              isOpen: true,
              onClose: overlayNotifier.closeOverlay,
              bands: userBands,
              activeBandId: activeBandId,
            ),
        ],
      ),
    );
  }
}

/// The welcome content shown when user has no bands
class _NoBandContent extends StatefulWidget {
  final VoidCallback onOpenMenu;
  final VoidCallback? onOpenBandSwitcher;
  final bool isNewUser;
  final VoidCallback? onRestoreSuccess;

  const _NoBandContent({
    required this.onOpenMenu,
    this.onOpenBandSwitcher,
    this.isNewUser = false,
    this.onRestoreSuccess,
  });

  @override
  State<_NoBandContent> createState() => _NoBandContentState();
}

class _NoBandContentState extends State<_NoBandContent>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _buttonController;
  ConfettiController? _confettiController;

  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _logoScale;
  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;
  late Animation<double> _bodyFade;
  late Animation<double> _createButtonScale;

  bool _isImporting = false;

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
    _logoSlide =
        Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(
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
    _titleSlide =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
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

    // Start animations with stagger
    _entranceController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _buttonController.forward();
    });

    // Fire confetti once for brand new users
    if (widget.isNewUser) {
      _confettiController = ConfettiController(
        duration: const Duration(seconds: 3),
      );
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _confettiController?.play();
      });
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _buttonController.dispose();
    _confettiController?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESTORE FROM BACKUP
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRestoreConfirmDialog(
      BuildContext context, BandBackupStats stats) {
    Widget statRow(String label, int count) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: AppFontSizes.subhead,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppFontSizes.subhead,
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.primary, size: 24),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Restore from Backup?',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: AppFontSizes.title),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: AppFontSizes.subhead),
                children: [
                  const TextSpan(text: 'A band named '),
                  TextSpan(
                    text: stats.bandName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                      text: ' will be recreated with the following data:'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            statRow('Members', stats.memberCount),
            statRow('Songs', stats.songCount),
            statRow('Setlists', stats.setlistCount),
            statRow('Gigs', stats.gigCount),
            statRow('Rehearsals', stats.rehearsalCount),
            statRow('Block-out dates', stats.blockOutCount),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'This will create a new band and populate it with your '
                'backup data. This cannot be undone.',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: AppFontSizes.caption,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
              fontSize: AppFontSizes.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Restore Band'),
        ),
      ],
    );
  }

  Future<void> _performRestore() async {
    // Step 1: File pick
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context, message: 'Could not open file picker.');
      }
      return;
    }
    if (result == null || result.files.single.bytes == null) return;

    // Step 2: Decode bytes
    final String jsonContent;
    try {
      jsonContent = utf8.decode(result.files.single.bytes!);
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context,
            message: 'Could not read the selected file.');
      }
      return;
    }

    // Step 3: Validate and preview
    final BandBackupStats stats;
    try {
      stats = DataBackupService.previewBackup(jsonContent);
    } on DataBackupException catch (e) {
      if (mounted) showErrorSnackBar(context, message: e.message);
      return;
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context,
            message: 'This file does not appear to be a valid backup.');
      }
      return;
    }

    if (!mounted) return;

    // Step 4: Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildRestoreConfirmDialog(context, stats),
    );
    if (confirmed != true || !mounted) return;

    // Step 5: Import
    setState(() => _isImporting = true);
    try {
      await DataBackupService.importBandData(jsonContent, null);
      if (mounted) {
        showSuccessSnackBar(context, message: 'Band restored successfully!');
        widget.onRestoreSuccess?.call();
      }
    } on DataBackupException catch (e) {
      if (mounted) showErrorSnackBar(context, message: e.message);
    } catch (e) {
      if (mounted) {
        final msg = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        showErrorSnackBar(context, message: 'Restore failed: $msg');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
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
                      AppIcons.menu,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: widget.onOpenMenu,
                  ),
                  // Band switcher button (only shown if user has bands)
                  if (widget.onOpenBandSwitcher != null)
                    IconButton(
                      icon: const Icon(
                        AppIcons.users,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: widget.onOpenBandSwitcher,
                    )
                  else
                    const SizedBox(width: 48), // Placeholder to maintain layout
                ],
              ),
            ),

            // Main content
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth - (Spacing.space32 * 2);
                  final logoWidth = (maxWidth * 0.9).clamp(0.0, 600.0);

                  return Padding(
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
                              child: BandRoadieLogo(
                                width: logoWidth,
                                asset:
                                    'assets/images/bandroadie_logo_rose_tag.svg',
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
                                fontSize: AppFontSizes.display,
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
                              fontSize: AppFontSizes.body,
                              height: 1.6,
                              color: context.colors.textSecondary,
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
                                  fadeSlideRoute(
                                      page: const CreateBandScreen()),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
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
                                style: AppTextStyles.button
                                    .copyWith(fontSize: AppFontSizes.body),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: Spacing.space16),

                        // Restore from backup — secondary action for users with no bands
                        FadeTransition(
                          opacity: _bodyFade,
                          child: TextButton(
                            onPressed: _isImporting ? null : _performRestore,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                vertical: Spacing.space12,
                                horizontal: Spacing.space16,
                              ),
                            ),
                            child: _isImporting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Restore from backup',
                                    style: AppTextStyles.body.copyWith(
                                      fontSize: AppFontSizes.subhead,
                                      color: AppColors.primary,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (_confettiController == null) return content;

    return Stack(
      children: [
        content,
        // Confetti burst from top center — fires once for new users
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController!,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 30,
            maxBlastForce: 20,
            minBlastForce: 8,
            gravity: 0.3,
            emissionFrequency: 0.05,
            shouldLoop: false,
            colors: const [
              Color(0xFFF43F5E), // rose (brand accent)
              Color(0xFFFFFFFF), // white
              Color(0xFFFBBF24), // amber
              Color(0xFF34D399), // emerald
              Color(0xFF60A5FA), // blue
            ],
          ),
        ),
      ],
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
    // bands parameter is non-nullable List<Band> - no null check needed
    // but add empty check for safety before accessing isEmpty

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
      // Only show Edit Band button if there are bands
      onEditBand: bands.isNotEmpty
          ? () {
              onClose();
              // Navigate to edit band screen if there's an active band
              // (this shouldn't happen in NoBandShell, but handle gracefully)
            }
          : null,
    );
  }
}

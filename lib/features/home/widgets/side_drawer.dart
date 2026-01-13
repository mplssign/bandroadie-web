import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/services/app_version_service.dart';

// ============================================================================
// SIDE DRAWER - FIGMA NODE 27-69 "Menu"
// Matches Figma mock exactly
// Width: 336px (max 400px)
// Background: gray-950 (#020617)
// ============================================================================

/// Design tokens extracted from Figma Dev panel
class _DrawerTokens {
  _DrawerTokens._();

  // Layout
  static const double drawerWidth = 336.0;
  static const double drawerMaxWidth = 400.0;

  // Colors - Figma exact hex values
  static const Color background = Color(0xFF020617); // gray-950
  static const Color divider = Color(0xFF1E293B); // gray-800
  static const Color iconDefault = Color(0xFF9CA3AF); // lighter gray for icons
  static const Color iconAccent = Color(0xFFF43F5E); // rose-500
  static const Color textPrimary = Color(0xFFFFFFFF); // white
  static const Color textSecondary = Color(
    0xFF9CA3AF,
  ); // lighter gray for secondary text
  static const Color pressedBg = Color(0x14FFFFFF); // ~8% white

  // Header padding - Figma: pt 12, pr 12, pb 16, pl 24
  static const EdgeInsets headerPadding = EdgeInsets.only(
    top: 12,
    right: 12,
    bottom: 16,
    left: 24,
  );

  // User info padding - Figma: left 24
  static const EdgeInsets userInfoPadding = EdgeInsets.symmetric(
    horizontal: 24,
  );

  // Nav item padding - Figma: pl 24, pr 12, pt 16, pb 16
  static const EdgeInsets navItemPadding = EdgeInsets.only(
    left: 24,
    right: 12,
    top: 16,
    bottom: 16,
  );

  // Footer padding - Figma: left 24, bottom 20
  static const EdgeInsets footerPadding = EdgeInsets.only(
    left: 24,
    right: 24,
    bottom: 20,
  );

  // Spacing
  static const double iconTextGap = 16.0;
  static const double iconSize = 24.0;
  static const double closeButtonSize = 48.0;
  static const double closeButtonInnerSize = 40.0;
  static const double closeIconSize = 24.0;
  static const double sectionGap = 56.0; // Gap before Log Out

  // Typography - Updated per Figma specs
  // Name: 18px, weight 500, primary text color
  static const TextStyle nameStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: textPrimary,
    decoration: TextDecoration.none,
  );

  // Email: 16px, weight 400, lighter gray
  static const TextStyle emailStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
    decoration: TextDecoration.none,
  );

  // Nav item: 16px, weight 400, lighter gray
  static const TextStyle navItemStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
    decoration: TextDecoration.none,
  );

  // Nav item logout: 16px, weight 400, rose-500
  static const TextStyle navItemLogoutStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: iconAccent,
    decoration: TextDecoration.none,
  );

  // Footer app name: 12px, weight 400, lighter gray
  static const TextStyle footerAppNameStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
    decoration: TextDecoration.none,
  );

  // Footer version: 12px, weight 400, lighter gray
  static const TextStyle footerVersionStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: textSecondary,
    decoration: TextDecoration.none,
  );
}

// ============================================================================
// SIDE DRAWER WIDGET
// ============================================================================

class SideDrawer extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String? appVersion;
  final VoidCallback onClose;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onTipsAndTricksTap;
  final VoidCallback onReportBugsTap;
  final VoidCallback onLogOutTap;
  final bool isVisible;

  const SideDrawer({
    super.key,
    required this.userName,
    required this.userEmail,
    this.appVersion,
    required this.onClose,
    required this.onProfileTap,
    required this.onSettingsTap,
    required this.onTipsAndTricksTap,
    required this.onReportBugsTap,
    required this.onLogOutTap,
    this.isVisible = true,
  });

  @override
  State<SideDrawer> createState() => _SideDrawerState();
}

class _SideDrawerState extends State<SideDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _userNameFade;
  late Animation<Offset> _userNameSlide;
  late Animation<double> _userEmailFade;
  late Animation<Offset> _userEmailSlide;

  @override
  void initState() {
    super.initState();

    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Close button: 0-40%
    _headerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      ),
    );
    _headerSlide = Tween<Offset>(begin: const Offset(0.1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: const Interval(0, 0.4, curve: Curves.easeOutCubic),
          ),
        );

    // User name: 15-55%
    _userNameFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: const Interval(0.15, 0.55, curve: Curves.easeOut),
      ),
    );
    _userNameSlide =
        Tween<Offset>(begin: const Offset(-0.05, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: const Interval(0.15, 0.55, curve: Curves.easeOutCubic),
          ),
        );

    // Email: 30-70%
    _userEmailFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );
    _userEmailSlide =
        Tween<Offset>(begin: const Offset(-0.03, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic),
          ),
        );

    if (widget.isVisible) {
      _staggerController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant SideDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _staggerController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _DrawerTokens.drawerWidth,
      constraints: const BoxConstraints(maxWidth: _DrawerTokens.drawerMaxWidth),
      color: _DrawerTokens.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close button
          _buildHeader(),

          // User info section
          _buildUserInfo(),

          // Spacing before nav items (Figma: ~24px gap)
          const SizedBox(height: 24),

          // Navigation items
          const DrawerSectionDivider(),
          DrawerNavItem(
            icon: Icons.person_outline_rounded,
            iconColor: _DrawerTokens.iconDefault,
            label: 'My Profile',
            onTap: widget.onProfileTap,
          ),
          const DrawerSectionDivider(),
          DrawerNavItem(
            icon: Icons.settings_outlined,
            iconColor: _DrawerTokens.iconDefault,
            label: 'Settings',
            onTap: widget.onSettingsTap,
          ),
          const DrawerSectionDivider(),
          DrawerNavItem(
            icon: Icons.lightbulb_outline_rounded,
            iconColor: _DrawerTokens.iconDefault,
            label: 'Tips & Tricks',
            onTap: widget.onTipsAndTricksTap,
          ),
          const DrawerSectionDivider(),
          DrawerNavItem(
            icon: Icons.bug_report_outlined,
            iconColor: _DrawerTokens.iconDefault,
            label: 'Report Bugs',
            onTap: widget.onReportBugsTap,
          ),
          const DrawerSectionDivider(),

          // Gap before Log Out (Figma: 56px)
          const SizedBox(height: _DrawerTokens.sectionGap),

          // Log Out section
          const DrawerSectionDivider(),
          DrawerNavItem(
            icon: Icons.logout_rounded,
            iconColor: _DrawerTokens.iconAccent,
            label: 'Log Out',
            labelStyle: _DrawerTokens.navItemLogoutStyle,
            onTap: widget.onLogOutTap,
          ),
          const DrawerSectionDivider(),

          const Spacer(),

          // Footer with app version
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: _DrawerTokens.headerPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            // Close button with stagger animation
            FadeTransition(
              opacity: _headerFade,
              child: SlideTransition(
                position: _headerSlide,
                child: _CloseButton(onTap: widget.onClose),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    return Padding(
      padding: _DrawerTokens.userInfoPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User name (primary - visually prominent)
          FadeTransition(
            opacity: _userNameFade,
            child: SlideTransition(
              position: _userNameSlide,
              child: Text(
                widget.userName,
                style: _DrawerTokens.nameStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 4), // Small gap between name and email
          // Email (secondary - less prominent)
          FadeTransition(
            opacity: _userEmailFade,
            child: SlideTransition(
              position: _userEmailSlide,
              child: Text(
                widget.userEmail,
                style: _DrawerTokens.emailStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: _DrawerTokens.footerPadding,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('BandRoadie', style: _DrawerTokens.footerAppNameStyle),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://bandroadie.com/privacy'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  color: _DrawerTokens.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: _DrawerTokens.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.appVersion ?? AppVersionService.displayVersion,
              style: _DrawerTokens.footerVersionStyle,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CLOSE BUTTON
// Figma: 48x48 container, 40x40 circular hit area
// ============================================================================

class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    _controller.reverse();
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: _DrawerTokens.closeButtonSize,
              height: _DrawerTokens.closeButtonSize,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: _DrawerTokens.closeButtonInnerSize,
                  height: _DrawerTokens.closeButtonInnerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isPressed
                        ? _DrawerTokens.pressedBg
                        : Colors.transparent,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: _DrawerTokens.iconDefault,
                    size: _DrawerTokens.closeIconSize,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// DRAWER NAV ITEM
// Figma: pl 24, pr 12, py 16, icon 24px, gap 16px, text 16px
// Micro-interactions: scale 0.98, bg brighten, icon pop 1.05, haptic
// ============================================================================

class DrawerNavItem extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final TextStyle? labelStyle;
  final VoidCallback onTap;

  const DrawerNavItem({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelStyle,
    required this.onTap,
  });

  @override
  State<DrawerNavItem> createState() => _DrawerNavItemState();
}

class _DrawerNavItemState extends State<DrawerNavItem>
    with TickerProviderStateMixin {
  late AnimationController _pressController;
  late AnimationController _iconPopController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _iconPopAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();

    // Press animation
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 90),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeOut));

    // Icon pop animation
    _iconPopController = AnimationController(
      duration: const Duration(milliseconds: 140),
      vsync: this,
    );
    _iconPopAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.05,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_iconPopController);
  }

  @override
  void dispose() {
    _pressController.dispose();
    _iconPopController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    _pressController.reverse();
    _iconPopController.forward(from: 0);
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          color: _isPressed ? _DrawerTokens.pressedBg : Colors.transparent,
          padding: _DrawerTokens.navItemPadding,
          child: Row(
            children: [
              // Icon with pop animation
              AnimatedBuilder(
                animation: _iconPopAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _iconPopAnimation.value,
                    child: child,
                  );
                },
                child: Icon(
                  widget.icon,
                  color: widget.iconColor,
                  size: _DrawerTokens.iconSize,
                ),
              ),
              const SizedBox(width: _DrawerTokens.iconTextGap),
              Expanded(
                child: Text(
                  widget.label,
                  style: widget.labelStyle ?? _DrawerTokens.navItemStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DRAWER SECTION DIVIDER
// Figma: Full width, 1px height, gray-800 (#1E293B)
// Spans full width of menu content area for clean separation
// ============================================================================

class DrawerSectionDivider extends StatelessWidget {
  const DrawerSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 1,
      color: _DrawerTokens.divider,
    );
  }
}

// ============================================================================
// DRAWER OVERLAY
// Manages drawer animation, scrim, and dismissal gestures
// - easeOutBack overshoot on open (rubber-band feel)
// - Snappier close with easeInCubic
// - Smooth scrim fade with backdrop blur
// ============================================================================

class DrawerOverlay extends StatefulWidget {
  final Widget child;
  final bool isOpen;
  final VoidCallback onClose;
  final String userName;
  final String userEmail;
  final String? appVersion;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onTipsAndTricksTap;
  final VoidCallback onReportBugsTap;
  final VoidCallback onLogOutTap;

  const DrawerOverlay({
    super.key,
    required this.child,
    required this.isOpen,
    required this.onClose,
    required this.userName,
    required this.userEmail,
    this.appVersion,
    required this.onProfileTap,
    required this.onSettingsTap,
    required this.onTipsAndTricksTap,
    required this.onReportBugsTap,
    required this.onLogOutTap,
  });

  @override
  State<DrawerOverlay> createState() => _DrawerOverlayState();
}

class _DrawerOverlayState extends State<DrawerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scrimAnimation;

  double _dragStartX = 0;
  double _currentDrag = 0;

  static const Curve _openCurve = _EaseOutBack();
  static const Curve _closeCurve = Curves.easeInCubic;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 280), // Open duration
      reverseDuration: const Duration(milliseconds: 220), // Close duration
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: _openCurve,
            reverseCurve: _closeCurve,
          ),
        );

    _scrimAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    if (widget.isOpen) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant DrawerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _dragStartX = details.globalPosition.dx;
    _currentDrag = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.globalPosition.dx - _dragStartX;
    _currentDrag = delta;

    if (_currentDrag < 0) {
      final progress = (-_currentDrag / _DrawerTokens.drawerWidth).clamp(
        0.0,
        1.0,
      );
      _controller.value = 1 - progress;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    if (velocity < -200 || _controller.value < 0.5) {
      widget.onClose();
    } else {
      _controller.forward();
    }
    _currentDrag = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main content
        widget.child,

        // Scrim overlay
        AnimatedBuilder(
          animation: _scrimAnimation,
          builder: (context, _) {
            if (_scrimAnimation.value == 0) {
              return const SizedBox.shrink();
            }

            return GestureDetector(
              onTap: widget.onClose,
              child: Container(
                color: Colors.black.withValues(
                  alpha: 0.6 * _scrimAnimation.value,
                ),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 2 * _scrimAnimation.value,
                      sigmaY: 2 * _scrimAnimation.value,
                    ),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            );
          },
        ),

        // Drawer panel
        SlideTransition(
          position: _slideAnimation,
          child: GestureDetector(
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            child: SideDrawer(
              userName: widget.userName,
              userEmail: widget.userEmail,
              appVersion: widget.appVersion,
              isVisible: widget.isOpen,
              onClose: widget.onClose,
              onProfileTap: () {
                widget.onClose();
                widget.onProfileTap();
              },
              onSettingsTap: () {
                widget.onClose();
                widget.onSettingsTap();
              },
              onTipsAndTricksTap: () {
                widget.onClose();
                widget.onTipsAndTricksTap();
              },
              onReportBugsTap: () {
                widget.onClose();
                widget.onReportBugsTap();
              },
              onLogOutTap: () {
                widget.onClose();
                widget.onLogOutTap();
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// DRAWER OVERLAY CONTENT
// Standalone version for rendering at AppShell level (above bottom nav).
// Does NOT wrap a child - just renders scrim + drawer panel.
// ============================================================================

class DrawerOverlayContent extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final String userName;
  final String userEmail;
  final String? appVersion;
  final VoidCallback onProfileTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onTipsAndTricksTap;
  final VoidCallback onReportBugsTap;
  final VoidCallback onLogOutTap;

  const DrawerOverlayContent({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.userName,
    required this.userEmail,
    this.appVersion,
    required this.onProfileTap,
    required this.onSettingsTap,
    required this.onTipsAndTricksTap,
    required this.onReportBugsTap,
    required this.onLogOutTap,
  });

  @override
  State<DrawerOverlayContent> createState() => _DrawerOverlayContentState();
}

class _DrawerOverlayContentState extends State<DrawerOverlayContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scrimAnimation;

  double _dragStartX = 0;
  double _currentDrag = 0;

  static const Curve _openCurve = _EaseOutBack();
  static const Curve _closeCurve = Curves.easeInCubic;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: _openCurve,
            reverseCurve: _closeCurve,
          ),
        );

    _scrimAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    if (widget.isOpen) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant DrawerOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _dragStartX = details.globalPosition.dx;
    _currentDrag = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.globalPosition.dx - _dragStartX;
    _currentDrag = delta;

    if (_currentDrag < 0) {
      final progress = (-_currentDrag / _DrawerTokens.drawerWidth).clamp(
        0.0,
        1.0,
      );
      _controller.value = 1 - progress;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    if (velocity < -200 || _controller.value < 0.5) {
      widget.onClose();
    } else {
      _controller.forward();
    }
    _currentDrag = 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Don't render anything when fully closed
        if (_controller.value == 0) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            // Scrim overlay (fills entire screen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: Container(
                  color: Colors.black.withValues(
                    alpha: 0.5 * _scrimAnimation.value,
                  ),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 8 * _scrimAnimation.value,
                        sigmaY: 8 * _scrimAnimation.value,
                      ),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),
              ),
            ),

            // Drawer panel
            SlideTransition(
              position: _slideAnimation,
              child: GestureDetector(
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                child: SideDrawer(
                  userName: widget.userName,
                  userEmail: widget.userEmail,
                  appVersion: widget.appVersion,
                  isVisible: widget.isOpen,
                  onClose: widget.onClose,
                  onProfileTap: widget.onProfileTap,
                  onSettingsTap: widget.onSettingsTap,
                  onTipsAndTricksTap: widget.onTipsAndTricksTap,
                  onReportBugsTap: widget.onReportBugsTap,
                  onLogOutTap: widget.onLogOutTap,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// CUSTOM CURVES
// ============================================================================

/// easeOutBack with controlled overshoot for rubber-band feel
class _EaseOutBack extends Curve {
  const _EaseOutBack();

  @override
  double transformInternal(double t) {
    const c1 = 1.3; // Subtle overshoot
    const c3 = c1 + 1;
    return 1 + c3 * ((t - 1) * (t - 1) * (t - 1)) + c1 * ((t - 1) * (t - 1));
  }
}

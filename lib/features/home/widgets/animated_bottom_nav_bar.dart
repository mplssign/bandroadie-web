import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/scroll/scroll_blur_notifier.dart';
import '../../../shared/widgets/glass_surface.dart';

// ============================================================================
// ANIMATED BOTTOM NAV BAR
// Figma: height 68px, bg gray-800 #1e293b, blur 2px, padding 16px h, 8pt top, 6pb
//
// FULLY CONTROLLED COMPONENT:
// - Selection is ALWAYS derived from `selectedIndex` prop
// - No internal selection state
// - Spring-animated highlight moves between items
// - Scale-down micro-interaction on press
// ============================================================================

/// Navigation item data
class NavItem {
  final IconData icon;
  final String label;

  const NavItem({required this.icon, required this.label});
}

/// Default navigation items
const List<NavItem> kDefaultNavItems = [
  NavItem(icon: Icons.home_rounded, label: 'Dashboard'),
  NavItem(icon: Icons.queue_music_rounded, label: 'Setlists'),
  NavItem(icon: Icons.calendar_today_rounded, label: 'Calendar'),
  NavItem(icon: Icons.people_rounded, label: 'Members'),
];

/// Navigation tab indices
class NavTabIndex {
  static const int dashboard = 0;
  static const int setlists = 1;
  static const int calendar = 2;
  static const int members = 3;
}

class AnimatedBottomNavBar extends ConsumerStatefulWidget {
  /// Currently selected tab index
  final int selectedIndex;

  /// Callback when a tab is tapped
  final ValueChanged<int>? onItemTapped;

  /// Optional custom navigation items
  final List<NavItem> items;

  const AnimatedBottomNavBar({
    super.key,
    required this.selectedIndex,
    this.onItemTapped,
    this.items = kDefaultNavItems,
  });

  @override
  ConsumerState<AnimatedBottomNavBar> createState() =>
      _AnimatedBottomNavBarState();
}

class _AnimatedBottomNavBarState extends ConsumerState<AnimatedBottomNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _highlightController;

  // Current animated position value (0.0 to 3.0 for 4 tabs)
  double _currentPosition = 0.0;

  // Track which item is being pressed for scale animation
  int? _pressedIndex;

  // Stored listener reference for cleanup
  VoidCallback? _animationListener;

  // Spring configuration - bouncy feel with quick settle
  static const SpringDescription _springDesc = SpringDescription(
    mass: 1.0,
    stiffness: 350.0,
    damping: 22.0,
  );

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.selectedIndex.toDouble();
    _highlightController = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(AnimatedBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _animateToIndex(widget.selectedIndex);
    }
  }

  void _animateToIndex(int newIndex) {
    final targetPosition = newIndex.toDouble();
    final startPosition = _currentPosition;

    // Create spring simulation from current position to new position
    final spring = SpringSimulation(
      _springDesc,
      startPosition,
      targetPosition,
      0.0, // initial velocity
    );

    // Stop any running animation
    _highlightController.stop();

    // Remove previous listener if exists
    if (_animationListener != null) {
      _highlightController.removeListener(_animationListener!);
    }

    // Create new listener for this animation
    _animationListener = () {
      setState(() {
        // Spring simulation gives position at time t (in seconds)
        // Controller value is 0-1, multiply by expected duration
        final t = _highlightController.value * 0.6; // ~600ms animation
        _currentPosition = spring.x(t);

        // Snap to target when close enough
        if ((_currentPosition - targetPosition).abs() < 0.005) {
          _currentPosition = targetPosition;
        }
      });
    };
    _highlightController.addListener(_animationListener!);

    // Animate for duration based on spring settling time
    _highlightController.reset();
    _highlightController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.linear, // Spring handles the easing
    );
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  void _handleTap(int index) {
    if (index != widget.selectedIndex) {
      widget.onItemTapped?.call(index);
    }
  }

  void _handleTapDown(int index) {
    setState(() => _pressedIndex = index);
  }

  void _handleTapUp(int index) {
    setState(() => _pressedIndex = null);
  }

  void _handleTapCancel() {
    setState(() => _pressedIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    // Watch scroll blur for dynamic glass effect
    final scrollBlur = ref.watch(scrollBlurProvider);

    // Dynamic blur: 8 at rest, 18 when scrolled
    final blurSigma = scrollBlur.lerpTo(8.0, 18.0);
    // Dynamic tint: 0.10 at rest, 0.25 when scrolled
    final tintOpacity = scrollBlur.lerpTo(0.10, 0.25);
    // Dynamic edge fade: 0.15 at rest, 0.55 when scrolled
    final edgeFadeStrength = scrollBlur.lerpTo(0.15, 0.55);

    // Get safe area bottom padding for iOS home indicator
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return GlassSurface(
      // Total height = nav content (68px) + safe area bottom padding
      height: Spacing.bottomNavHeight + bottomSafeArea,
      blurSigma: blurSigma,
      tintOpacity: tintOpacity,
      edge: GlassEdge.top, // Shadow at top edge (content scrolls above)
      edgeFadeStrength: edgeFadeStrength,
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        top: 8,
        // Include safe area in bottom padding
        bottom: 6 + bottomSafeArea,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemCount = widget.items.length;
          final availableWidth = constraints.maxWidth;
          final itemWidth = availableWidth / itemCount;

            return Stack(
              children: [
                // Animated highlight layer - uses _currentPosition directly
                Builder(
                  builder: (context) {
                    // Calculate the highlight position based on current animated value
                    final highlightWidth = 80.0; // Fixed highlight width
                    // Center the highlight within the item slot
                    final left =
                        (_currentPosition * itemWidth) +
                        (itemWidth - highlightWidth) / 2;

                    return Positioned(
                      left: left,
                      top: 0,
                      child: Container(
                        width: highlightWidth,
                        height: Spacing.navItemHeight, // 53px
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(
                            Spacing.buttonRadius,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Navigation items layer
                Row(
                  children: List.generate(widget.items.length, (index) {
                    final item = widget.items[index];
                    final isActive = index == widget.selectedIndex;
                    final isPressed = _pressedIndex == index;

                    return Expanded(
                      child: _AnimatedNavItem(
                        icon: item.icon,
                        label: item.label,
                        isActive: isActive,
                        isPressed: isPressed,
                        onTap: () => _handleTap(index),
                        onTapDown: () => _handleTapDown(index),
                        onTapUp: () => _handleTapUp(index),
                        onTapCancel: _handleTapCancel,
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
    );
  }
}

class _AnimatedNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isPressed;
  final VoidCallback onTap;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;

  const _AnimatedNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isPressed,
    required this.onTap,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: Spacing.navItemHeight,
        child: Center(
          child: AnimatedScale(
            scale: isPressed ? 0.92 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
            child: SizedBox(
              width: 80,
              height: Spacing.navItemHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: AppColors.textNav,
                    size: isActive ? 20.5 : 20,
                  ),
                  SizedBox(height: isActive ? 4 : 6),
                  Text(
                    label,
                    style: AppTextStyles.navLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LEGACY WRAPPERS - DEPRECATED
// These are kept for backward compatibility but should NOT be used.
// Use AppShell with currentTabProvider instead.
// ============================================================================

/// @Deprecated: Use AppShell with currentTabProvider instead
/// This wrapper is kept only for backward compatibility during migration.
class BottomNavBar extends StatelessWidget {
  final VoidCallback? onSetlistsTap;
  final VoidCallback? onCalendarTap;
  final VoidCallback? onMembersTap;

  const BottomNavBar({
    super.key,
    this.onSetlistsTap,
    this.onCalendarTap,
    this.onMembersTap,
  });

  @override
  Widget build(BuildContext context) {
    // This is a fallback - ideally AppShell handles all navigation
    debugPrint(
      '[BottomNavBar] WARNING: Using deprecated BottomNavBar. '
      'Migrate to AppShell with currentTabProvider.',
    );
    return AnimatedBottomNavBar(
      selectedIndex: NavTabIndex.dashboard,
      onItemTapped: (index) {
        debugPrint('[BottomNavBar] Tap on index $index - not handled');
      },
    );
  }
}

/// @Deprecated: Use AppShell with currentTabProvider instead
class SetlistsBottomNavBar extends StatelessWidget {
  final VoidCallback? onDashboardTap;
  final VoidCallback? onCalendarTap;
  final VoidCallback? onMembersTap;

  const SetlistsBottomNavBar({
    super.key,
    this.onDashboardTap,
    this.onCalendarTap,
    this.onMembersTap,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[SetlistsBottomNavBar] WARNING: Using deprecated nav bar. '
      'Migrate to AppShell with currentTabProvider.',
    );
    return AnimatedBottomNavBar(
      selectedIndex: NavTabIndex.setlists,
      onItemTapped: (index) {
        debugPrint('[SetlistsBottomNavBar] Tap on index $index - not handled');
      },
    );
  }
}

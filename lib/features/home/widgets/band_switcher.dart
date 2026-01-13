import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/models/band.dart';
import '../../../app/theme/design_tokens.dart';
import '../../bands/widgets/band_avatar.dart';

// ============================================================================
// BAND SWITCHER DRAWER - FIGMA NODE 28-3120
// Opens from the RIGHT side when avatar is tapped
// Shows list of user's bands with active band highlighted
// ============================================================================

/// Design tokens for Band Switcher (from Figma)
class _BandSwitcherTokens {
  _BandSwitcherTokens._();

  // Layout
  static const double drawerWidth = 336.0;
  static const double drawerMaxWidth = 400.0;

  // Colors - Figma exact
  static const Color background = Color(0xFF020617); // gray-950
  static const Color divider = Color(0xFF1E293B); // gray-800
  static const Color iconDefault = Color(0xFFFFFFFF); // white
  static const Color pressedBg = Color(0x14FFFFFF); // ~8% white

  // Selected band row - solid background with visible top/bottom borders
  static const Color selectedBackground = Color(0xFF1E293B); // gray-800
  static const Color selectedBorderColor = Color(0xFF334155); // gray-700

  // Header padding - Figma: pt 12, pr 12, pb 16, pl 24
  static const EdgeInsets headerPadding = EdgeInsets.only(
    top: 12,
    right: 12,
    bottom: 16,
    left: 24,
  );

  // Band item padding - Figma: pl 24, pr 16, py 8
  static const EdgeInsets bandItemPadding = EdgeInsets.only(
    left: 24,
    right: 16,
    top: 8,
    bottom: 8,
  );

  // Button section padding
  static const EdgeInsets buttonSectionPadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 16,
  );

  // Spacing
  static const double avatarSize = 40.0;
  static const double avatarTextGap = 16.0;
  static const double bandRowHeight = 56.0;
  static const double closeButtonSize = 48.0;
  static const double closeButtonInnerSize = 40.0;
  static const double closeIconSize = 24.0;
  static const double dividerWidth = 335.0;

  // Typography - Band name: 18px, medium weight, matching Figma mock
  // No underline decoration - plain text only
  static const TextStyle bandNameStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: iconDefault,
    decoration: TextDecoration.none,
  );
}

// ============================================================================
// BAND SWITCHER WIDGET
// ============================================================================

class BandSwitcher extends StatefulWidget {
  final List<Band> bands;
  final String? activeBandId;
  final VoidCallback onClose;
  final ValueChanged<Band> onBandSelected;
  final VoidCallback onCreateBand;
  final VoidCallback? onEditBand;
  final bool isVisible;

  const BandSwitcher({
    super.key,
    required this.bands,
    this.activeBandId,
    required this.onClose,
    required this.onBandSelected,
    required this.onCreateBand,
    this.onEditBand,
    this.isVisible = true,
  });

  @override
  State<BandSwitcher> createState() => _BandSwitcherState();
}

class _BandSwitcherState extends State<BandSwitcher>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();

    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _headerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _staggerController,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      ),
    );
    _headerSlide = Tween<Offset>(begin: const Offset(-0.1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: const Interval(0, 0.4, curve: Curves.easeOutCubic),
          ),
        );

    if (widget.isVisible) {
      _staggerController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant BandSwitcher oldWidget) {
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
      width: _BandSwitcherTokens.drawerWidth,
      constraints: const BoxConstraints(
        maxWidth: _BandSwitcherTokens.drawerMaxWidth,
      ),
      color: _BandSwitcherTokens.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close button
          _buildHeader(),

          // Band list
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: widget.bands.length,
              itemBuilder: (context, index) {
                final band = widget.bands[index];
                final isActive = band.id == widget.activeBandId;
                return _BandListItem(
                  band: band,
                  isActive: isActive,
                  onTap: () => widget.onBandSelected(band),
                  showDivider: !isActive && index < widget.bands.length - 1,
                );
              },
            ),
          ),

          // Button section
          _buildButtonSection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: _BandSwitcherTokens.headerPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
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

  Widget _buildButtonSection() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: _BandSwitcherTokens.buttonSectionPadding,
        child: Column(
          children: [
            // Edit Band button (primary action)
            if (widget.onEditBand != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onClose();
                    widget.onEditBand!();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                  ),
                  child: const Text(
                    'Edit Band',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

            // Create new band button (text button underneath)
            const SizedBox(height: Spacing.space12),
            TextButton(
              onPressed: () {
                widget.onClose();
                widget.onCreateBand();
              },
              child: Text(
                '+ Create New Band',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CLOSE BUTTON
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
              width: _BandSwitcherTokens.closeButtonSize,
              height: _BandSwitcherTokens.closeButtonSize,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: _BandSwitcherTokens.closeButtonInnerSize,
                  height: _BandSwitcherTokens.closeButtonInnerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isPressed
                        ? _BandSwitcherTokens.pressedBg
                        : Colors.transparent,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: _BandSwitcherTokens.iconDefault,
                    size: _BandSwitcherTokens.closeIconSize,
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
// BAND LIST ITEM
// Shows band avatar + name, with active state highlighting
// ============================================================================

class _BandListItem extends StatefulWidget {
  final Band band;
  final bool isActive;
  final VoidCallback onTap;
  final bool showDivider;

  const _BandListItem({
    required this.band,
    required this.isActive,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  State<_BandListItem> createState() => _BandListItemState();
}

class _BandListItemState extends State<_BandListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();

    _pressController = AnimationController(
      duration: const Duration(milliseconds: 90),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
    _pressController.reverse();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selected state: solid background with top/bottom borders
            // Non-selected: standard background
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              height: _BandSwitcherTokens.bandRowHeight,
              padding: _BandSwitcherTokens.bandItemPadding,
              decoration: BoxDecoration(
                color: widget.isActive
                    ? _BandSwitcherTokens.selectedBackground
                    : (_isPressed
                          ? _BandSwitcherTokens.pressedBg
                          : _BandSwitcherTokens.background),
                border: widget.isActive
                    ? const Border(
                        top: BorderSide(
                          color: _BandSwitcherTokens.selectedBorderColor,
                          width: 1,
                        ),
                        bottom: BorderSide(
                          color: _BandSwitcherTokens.selectedBorderColor,
                          width: 1,
                        ),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  // Avatar - no scale/position change on selection
                  BandAvatar.fromBand(
                    widget.band,
                    size: _BandSwitcherTokens.avatarSize,
                    fontSize: 14,
                  ),
                  const SizedBox(width: _BandSwitcherTokens.avatarTextGap),
                  // Band name
                  Expanded(
                    child: Text(
                      widget.band.name,
                      style: _BandSwitcherTokens.bandNameStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Divider (only for non-active items)
            if (widget.showDivider && !widget.isActive)
              Container(
                width: _BandSwitcherTokens.dividerWidth,
                height: 1,
                color: _BandSwitcherTokens.divider,
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// BAND SWITCHER OVERLAY
// Manages the drawer animation from the RIGHT side
// ============================================================================

class BandSwitcherOverlay extends StatefulWidget {
  final Widget child;
  final bool isOpen;
  final VoidCallback onClose;
  final List<Band> bands;
  final String? activeBandId;
  final ValueChanged<Band> onBandSelected;
  final VoidCallback onCreateBand;
  final VoidCallback? onEditBand;

  const BandSwitcherOverlay({
    super.key,
    required this.child,
    required this.isOpen,
    required this.onClose,
    required this.bands,
    this.activeBandId,
    required this.onBandSelected,
    required this.onCreateBand,
    this.onEditBand,
  });

  @override
  State<BandSwitcherOverlay> createState() => _BandSwitcherOverlayState();
}

class _BandSwitcherOverlayState extends State<BandSwitcherOverlay>
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

    // Slide from RIGHT (positive X offset to zero)
    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(1, 0), // Start off-screen to the right
          end: Offset.zero,
        ).animate(
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
  void didUpdateWidget(covariant BandSwitcherOverlay oldWidget) {
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

    // Only allow dragging RIGHT (positive delta) to close
    if (_currentDrag > 0) {
      final progress = (_currentDrag / _BandSwitcherTokens.drawerWidth).clamp(
        0.0,
        1.0,
      );
      _controller.value = 1 - progress;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    // If swiped right with velocity or dragged past half, close
    if (velocity > 200 || _controller.value < 0.5) {
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

        // Drawer panel - positioned on the RIGHT
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: SlideTransition(
            position: _slideAnimation,
            child: GestureDetector(
              onHorizontalDragStart: _handleDragStart,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              child: BandSwitcher(
                bands: widget.bands,
                activeBandId: widget.activeBandId,
                isVisible: widget.isOpen,
                onClose: widget.onClose,
                onBandSelected: (band) {
                  widget.onClose();
                  widget.onBandSelected(band);
                },
                onCreateBand: widget.onCreateBand,
                onEditBand: widget.onEditBand,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// BAND SWITCHER OVERLAY CONTENT
// Standalone version for rendering at AppShell level (above bottom nav).
// Does NOT wrap a child - just renders scrim + drawer panel.
// ============================================================================

class BandSwitcherOverlayContent extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final List<Band> bands;
  final String? activeBandId;
  final ValueChanged<Band> onBandSelected;
  final VoidCallback onCreateBand;
  final VoidCallback? onEditBand;

  const BandSwitcherOverlayContent({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.bands,
    this.activeBandId,
    required this.onBandSelected,
    required this.onCreateBand,
    this.onEditBand,
  });

  @override
  State<BandSwitcherOverlayContent> createState() =>
      _BandSwitcherOverlayContentState();
}

class _BandSwitcherOverlayContentState extends State<BandSwitcherOverlayContent>
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

    // Slide from RIGHT (positive X offset to zero)
    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(1, 0), // Start off-screen to the right
          end: Offset.zero,
        ).animate(
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
  void didUpdateWidget(covariant BandSwitcherOverlayContent oldWidget) {
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

    // Only allow dragging RIGHT (positive delta) to close
    if (_currentDrag > 0) {
      final progress = (_currentDrag / _BandSwitcherTokens.drawerWidth).clamp(
        0.0,
        1.0,
      );
      _controller.value = 1 - progress;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    // If swiped right with velocity or dragged past half, close
    if (velocity > 200 || _controller.value < 0.5) {
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

            // Drawer panel - positioned on the RIGHT
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: GestureDetector(
                  onHorizontalDragStart: _handleDragStart,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  onHorizontalDragEnd: _handleDragEnd,
                  child: BandSwitcher(
                    bands: widget.bands,
                    activeBandId: widget.activeBandId,
                    isVisible: widget.isOpen,
                    onClose: widget.onClose,
                    onBandSelected: (band) {
                      widget.onClose();
                      widget.onBandSelected(band);
                    },
                    onCreateBand: widget.onCreateBand,
                    onEditBand: widget.onEditBand,
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

// ============================================================================
// CUSTOM CURVES
// ============================================================================

class _EaseOutBack extends Curve {
  const _EaseOutBack();

  @override
  double transformInternal(double t) {
    const c1 = 1.3;
    const c3 = c1 + 1;
    return 1 + c3 * ((t - 1) * (t - 1) * (t - 1)) + c1 * ((t - 1) * (t - 1));
  }
}

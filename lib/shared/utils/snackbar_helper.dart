import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// SNACKBAR HELPER
// Single source of truth for snackbar display across the app.
// Ensures consistent duration, positioning (above bottom nav), and styling.
// Uses a custom overlay-based implementation for softer animations.
// ============================================================================

/// Default snackbar duration (1.5 seconds for quick feedback)
const Duration _defaultDuration = Duration(milliseconds: 1500);

/// Softer animation duration for enter/exit (300ms for a gentle feel)
const Duration _animationDuration = Duration(milliseconds: 300);

/// Bottom margin to appear above bottom nav + safe area
/// Calculated as: bottomNavHeight (68) + some padding (16)
const double _bottomMargin = Spacing.bottomNavHeight + Spacing.space16;

/// Track current overlay entry to allow clearing
OverlayEntry? _currentSnackBarEntry;
AnimationController? _currentController;

/// Show a snackbar with app-consistent styling and soft animations.
///
/// [message] - The text to display
/// [backgroundColor] - Optional background color (defaults to theme)
/// [duration] - How long to show (defaults to 1.5s)
/// [action] - Optional action button (e.g., Undo)
void showAppSnackBar(
  BuildContext context, {
  required String message,
  Color? backgroundColor,
  Duration duration = _defaultDuration,
  SnackBarAction? action,
}) {
  // Clear any existing snackbar
  _dismissCurrentSnackBar();

  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  // Get safe area bottom padding
  final safeBottom = MediaQuery.of(context).padding.bottom;

  late OverlayEntry entry;

  // We need a TickerProvider, so we'll use an AnimatedBuilder approach
  entry = OverlayEntry(
    builder: (context) => _AnimatedSnackBar(
      message: message,
      backgroundColor:
          backgroundColor ?? Theme.of(context).snackBarTheme.backgroundColor,
      bottomMargin: _bottomMargin + safeBottom,
      action: action,
      duration: duration,
      onDismiss: () {
        entry.remove();
        if (_currentSnackBarEntry == entry) {
          _currentSnackBarEntry = null;
          _currentController = null;
        }
      },
    ),
  );

  _currentSnackBarEntry = entry;
  overlay.insert(entry);
}

void _dismissCurrentSnackBar() {
  _currentController?.reverse();
  _currentSnackBarEntry?.remove();
  _currentSnackBarEntry = null;
  _currentController = null;
}

/// Internal animated snackbar widget
class _AnimatedSnackBar extends StatefulWidget {
  final String message;
  final Color? backgroundColor;
  final double bottomMargin;
  final SnackBarAction? action;
  final Duration duration;
  final VoidCallback onDismiss;

  const _AnimatedSnackBar({
    required this.message,
    this.backgroundColor,
    required this.bottomMargin,
    this.action,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_AnimatedSnackBar> createState() => _AnimatedSnackBarState();
}

class _AnimatedSnackBarState extends State<_AnimatedSnackBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: _animationDuration,
      reverseDuration: _animationDuration,
      vsync: this,
    );

    // Soft fade animation with easeOutCubic
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Subtle slide up animation
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    _currentController = _controller;

    // Start enter animation
    _controller.forward();

    // Schedule dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) {
            widget.onDismiss();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.backgroundColor ??
        Theme.of(context).snackBarTheme.backgroundColor ??
        AppColors.cardBg;

    return Positioned(
      left: Spacing.space16,
      right: Spacing.space16,
      bottom: widget.bottomMargin,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.space16,
                vertical: Spacing.space12,
              ),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.action != null) ...[
                    const SizedBox(width: Spacing.space8),
                    TextButton(
                      onPressed: () {
                        widget.action!.onPressed();
                        _controller.reverse().then((_) {
                          if (mounted) widget.onDismiss();
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor:
                            widget.action!.textColor ?? AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        widget.action!.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Show a success snackbar (green background)
void showSuccessSnackBar(
  BuildContext context, {
  required String message,
  Duration duration = _defaultDuration,
  SnackBarAction? action,
}) {
  showAppSnackBar(
    context,
    message: message,
    backgroundColor: AppColors.success,
    duration: duration,
    action: action,
  );
}

/// Show an error snackbar (red background)
void showErrorSnackBar(
  BuildContext context, {
  required String message,
  Duration duration = _defaultDuration,
  SnackBarAction? action,
}) {
  showAppSnackBar(
    context,
    message: message,
    backgroundColor: AppColors.error,
    duration: duration,
    action: action,
  );
}

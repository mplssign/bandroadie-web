import 'package:flutter/material.dart';

import 'design_tokens.dart';

// ============================================================================
// BANDROADIE ANIMATION UTILITIES
// Reusable animation widgets and route builders for consistent, purposeful motion.
//
// Design principles:
// - Subtle, not decorative
// - Communicate state changes clearly
// - Never delay core interactions
// - Uses existing AppDurations and AppCurves from design_tokens.dart
// ============================================================================

/// Scale values for press feedback
class AnimScales {
  AnimScales._();

  /// Button press scale-down
  static const double buttonPressed = 0.96;

  /// Card tap scale-down
  static const double cardPressed = 0.98;

  /// Success checkmark scale-up
  static const double successPop = 1.1;
}

// ============================================================================
// REUSABLE ANIMATION WIDGETS
// ============================================================================

/// Animated button wrapper with scale-down feedback on tap.
/// Wraps any child widget to add subtle press animation.
///
/// Usage:
/// ```dart
/// AnimatedPressable(
///   onTap: () => doSomething(),
///   child: MyButton(),
/// )
/// ```
class AnimatedPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  const AnimatedPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
  });

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.enabled
          ? (_) => setState(() => _isPressed = false)
          : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _isPressed = false)
          : null,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: AnimatedScale(
        scale: _isPressed ? AnimScales.buttonPressed : 1.0,
        duration: AppDurations.fast,
        curve: AppCurves.ease,
        child: widget.child,
      ),
    );
  }
}

/// Animated card wrapper with subtle press feedback.
/// Uses a gentler scale than buttons for larger touch targets.
class AnimatedCardPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  const AnimatedCardPressable({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
  });

  @override
  State<AnimatedCardPressable> createState() => _AnimatedCardPressableState();
}

class _AnimatedCardPressableState extends State<AnimatedCardPressable> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.enabled
          ? (_) => setState(() => _isPressed = false)
          : null,
      onTapCancel: widget.enabled
          ? () => setState(() => _isPressed = false)
          : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _isPressed ? AnimScales.cardPressed : 1.0,
        duration: AppDurations.fast,
        curve: AppCurves.ease,
        child: widget.child,
      ),
    );
  }
}

/// Fade-in entrance animation for list items.
/// Animates opacity and vertical position when first built.
///
/// Usage:
/// ```dart
/// FadeSlideIn(
///   delay: Duration(milliseconds: index * 50), // Staggered
///   child: MyCard(),
/// )
/// ```
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppDurations.medium,
    this.beginOffset = const Offset(0, 0.05),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: AppCurves.slideIn));

    _slide = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppCurves.slideIn));

    // Start animation after delay
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Animated loading button that switches between text and spinner.
/// Shows spinner during async operations with smooth transition.
///
/// Usage:
/// ```dart
/// AnimatedLoadingButton(
///   isLoading: _isSaving,
///   onPressed: _save,
///   label: 'Save',
/// )
/// ```
class AnimatedLoadingButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? width;
  final double height;

  const AnimatedLoadingButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.width,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? Theme.of(context).primaryColor;
    final fgColor = foregroundColor ?? Colors.white;

    return AnimatedPressable(
      enabled: !isLoading && onPressed != null,
      onTap: onPressed,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.ease,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isLoading ? bgColor.withOpacity(0.7) : bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: AppDurations.fast,
            child: isLoading
                ? SizedBox(
                    key: const ValueKey('spinner'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fgColor,
                    ),
                  )
                : Text(
                    key: ValueKey('label-$label'),
                    label,
                    style: TextStyle(
                      color: fgColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Success checkmark animation with scale/fade effect.
/// Shows briefly after an action completes successfully.
class AnimatedSuccessCheck extends StatefulWidget {
  final VoidCallback? onComplete;
  final double size;
  final Color color;

  const AnimatedSuccessCheck({
    super.key,
    this.onComplete,
    this.size = 24,
    this.color = Colors.green,
  });

  @override
  State<AnimatedSuccessCheck> createState() => _AnimatedSuccessCheckState();
}

class _AnimatedSuccessCheckState extends State<AnimatedSuccessCheck>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: AppDurations.slow, vsync: this);

    _scale = TweenSequence<double>(
      [
        TweenSequenceItem(
          tween: Tween(begin: 0, end: AnimScales.successPop),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(begin: AnimScales.successPop, end: 1),
          weight: 1,
        ),
      ],
    ).animate(CurvedAnimation(parent: _controller, curve: AppCurves.overshoot));

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5)),
    );

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Icon(Icons.check_circle, size: widget.size, color: widget.color),
      ),
    );
  }
}

// ============================================================================
// PAGE ROUTE BUILDERS
// Custom page transitions for navigation.
// ============================================================================

/// Creates a page route with fade + slide from right transition.
/// Use for standard push navigation.
Route<T> fadeSlideRoute<T>({
  required Widget page,
  RouteSettings? settings,
  Duration duration = AppDurations.medium,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slideAnimation = Tween<Offset>(
        begin: const Offset(0.1, 0), // Slight slide from right
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: AppCurves.ease));

      final fadeAnimation = Tween<double>(
        begin: 0,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: AppCurves.slideIn));

      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(position: slideAnimation, child: child),
      );
    },
  );
}

/// Creates a page route with fade + slide from bottom transition.
/// Use for modal-style screens.
Route<T> fadeSlideUpRoute<T>({
  required Widget page,
  RouteSettings? settings,
  Duration duration = AppDurations.medium,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slideAnimation = Tween<Offset>(
        begin: const Offset(0, 0.05), // Slight slide from bottom
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: AppCurves.ease));

      final fadeAnimation = Tween<double>(
        begin: 0,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: AppCurves.slideIn));

      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(position: slideAnimation, child: child),
      );
    },
  );
}

/// Creates a simple fade-only page route.
/// Use for subtle transitions like tab switches.
Route<T> fadeRoute<T>({
  required Widget page,
  RouteSettings? settings,
  Duration duration = AppDurations.fast,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

// ============================================================================
// STATE CHANGE ANIMATIONS
// ============================================================================

/// Animates a color transition, useful for state changes.
/// Wraps child and smoothly transitions background/border colors.
class AnimatedColorTransition extends StatelessWidget {
  final Widget child;
  final Color color;
  final Duration duration;
  final BorderRadius? borderRadius;
  final bool isBackground;

  const AnimatedColorTransition({
    super.key,
    required this.child,
    required this.color,
    this.duration = AppDurations.fast,
    this.borderRadius,
    this.isBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: AppCurves.ease,
      decoration: BoxDecoration(
        color: isBackground ? color : null,
        border: !isBackground ? Border.all(color: color, width: 2) : null,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}

/// Badge that animates in/out with scale and fade.
/// Use for role badges, status indicators, etc.
class AnimatedBadge extends StatelessWidget {
  final Widget child;
  final bool isVisible;
  final Duration duration;

  const AnimatedBadge({
    super.key,
    required this.child,
    required this.isVisible,
    this.duration = AppDurations.fast,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isVisible ? 1.0 : 0.0,
      duration: duration,
      curve: AppCurves.ease,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: duration,
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// LOADING OVERLAY
// Reusable full-screen overlay with spinner and message.
// Blocks interaction while async operations are running.
// ============================================================================

/// Shows a full-screen loading overlay with a spinner and message.
///
/// Returns a function to dismiss the overlay.
/// The overlay blocks all touch interaction behind it.
///
/// Usage:
/// ```dart
/// final dismiss = showLoadingOverlay(context, message: 'Adding songs…');
/// try {
///   await doWork();
/// } finally {
///   dismiss();
/// }
/// ```
VoidCallback showLoadingOverlay(
  BuildContext context, {
  required String message,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return () {};

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _LoadingOverlayWidget(message: message),
  );

  overlay.insert(entry);

  var dismissed = false;
  return () {
    if (!dismissed) {
      dismissed = true;
      entry.remove();
    }
  };
}

class _LoadingOverlayWidget extends StatefulWidget {
  final String message;
  const _LoadingOverlayWidget({required this.message});

  @override
  State<_LoadingOverlayWidget> createState() => _LoadingOverlayWidgetState();
}

class _LoadingOverlayWidgetState extends State<_LoadingOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 48),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.cardBgElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

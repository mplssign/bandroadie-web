import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/sheet_footer.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// SET BREAK CREATOR
// Bottom sheet for configuring a Set Break's duration (in minutes).
// Uses +/- 5-minute buttons with a centered readout.
// Returns the chosen duration in minutes, or null if cancelled.
// ============================================================================

/// Show the Set Break creator bottom sheet.
///
/// Returns the chosen duration in minutes, or null if cancelled.
Future<int?> showSetBreakCreator(BuildContext context) async {
  HapticFeedback.lightImpact();
  return showAppBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) => const _SetBreakCreatorSheet(),
  );
}

class _SetBreakCreatorSheet extends StatefulWidget {
  const _SetBreakCreatorSheet();

  @override
  State<_SetBreakCreatorSheet> createState() => _SetBreakCreatorSheetState();
}

class _SetBreakCreatorSheetState extends State<_SetBreakCreatorSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  int _minutes = 15; // Default

  static const int _minMinutes = 5;
  static const int _maxMinutes = 60;
  static const int _step = 5;

  Color get _accent => context.colors.primaryDim; // rose

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: AppDurations.normal,
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 0.15, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: AppCurves.slideIn),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _increment() {
    if (_minutes + _step <= _maxMinutes) {
      HapticFeedback.selectionClick();
      setState(() => _minutes += _step);
    }
  }

  void _decrement() {
    if (_minutes - _step >= _minMinutes) {
      HapticFeedback.selectionClick();
      setState(() => _minutes -= _step);
    }
  }

  void _submit() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(_minutes);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.only(bottom: bottomInset),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(AppIcons.timer, color: _accent, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Set Break',
                      style: AppTextStyles.title3.copyWith(color: _accent),
                    ),
                    const Spacer(),
                    // Close button
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        AppIcons.close,
                        color: context.colors.textMuted,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
                child: Text(
                  'How long is this break?',
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Duration stepper ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Minus button
                  _StepperButton(
                    icon: AppIcons.remove,
                    enabled: _minutes > _minMinutes,
                    accent: _accent,
                    onTap: _decrement,
                  ),

                  const SizedBox(width: 28),

                  // Duration readout
                  SizedBox(
                    width: 120,
                    child: Column(
                      children: [
                        Text(
                          '$_minutes',
                          style: AppTextStyles.displayLarge.copyWith(
                            fontSize: AppFontSizes.hero,
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'minutes',
                          style: AppTextStyles.label.copyWith(
                            color: context.colors.textMuted,
                            fontSize: AppFontSizes.subhead,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 28),

                  // Plus button
                  _StepperButton(
                    icon: AppIcons.add,
                    enabled: _minutes < _maxMinutes,
                    accent: _accent,
                    onTap: _increment,
                  ),
                ],
              ),

              const SizedBox(height: 40),

              SheetFooter(
                primaryLabel: 'Add Set Break',
                onPrimary: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular +/- stepper button.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? accent : context.colors.textDisabled;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          color: enabled ? context.colors.surface : Colors.transparent,
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}

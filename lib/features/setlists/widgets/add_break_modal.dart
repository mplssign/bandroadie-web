import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist_item_type.dart';
import '../models/special_item.dart';

// ============================================================================
// ADD BREAK MODAL
// Bottom sheet for selecting break type (Set Break or Pause).
//
// Layout:
//   - Drag handle
//   - Title: "Add Break / Pause"
//   - Two large tap targets:
//     1. SET BREAK – red accent, icon: timer_outlined
//     2. PAUSE – amber accent, icon: pause_circle_outline
//   - "Previously Used" section with saved templates (if any)
// ============================================================================

/// Result from the Add Break modal
class AddBreakResult {
  /// The type selected (setBreak or pause)
  final SetlistItemType type;

  /// If a previously used template was selected, its data
  final SpecialItem? template;

  const AddBreakResult({required this.type, this.template});
}

/// Shows the Add Break modal bottom sheet.
///
/// Returns [AddBreakResult] if user selects a type or template, null if dismissed.
Future<AddBreakResult?> showAddBreakModal(
  BuildContext context, {
  List<SpecialItem> templates = const [],
}) {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<AddBreakResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _AddBreakSheet(templates: templates),
  );
}

class _AddBreakSheet extends StatefulWidget {
  final List<SpecialItem> templates;

  const _AddBreakSheet({required this.templates});

  @override
  State<_AddBreakSheet> createState() => _AddBreakSheetState();
}

class _AddBreakSheetState extends State<_AddBreakSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: AppDurations.medium,
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: AppCurves.rubberband),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breakTemplates = widget.templates
        .where((t) => t.type == SetlistItemType.setBreak)
        .toList();
    final pauseTemplates = widget.templates
        .where((t) => t.type == SetlistItemType.pause)
        .toList();
    final hasTemplates = breakTemplates.isNotEmpty || pauseTemplates.isNotEmpty;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, _slideAnimation.value),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Spacing.cardRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDragHandle(),
            _buildHeader(),
            const Divider(color: AppColors.borderMuted, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type selection cards
                    _buildTypeCard(
                      type: SetlistItemType.setBreak,
                      icon: Icons.timer_outlined,
                      title: 'SET BREAK',
                      subtitle: 'Intermission between sets',
                      accentColor: const Color(0xFFBE123C),
                    ),
                    const SizedBox(height: 12),
                    _buildTypeCard(
                      type: SetlistItemType.pause,
                      icon: Icons.pause_circle_outline_rounded,
                      title: 'PAUSE',
                      subtitle: 'Guitar change, tuning break, band intro...',
                      accentColor: const Color(0xFFF59E0B),
                    ),

                    // Previously used templates
                    if (hasTemplates) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'PREVIOUSLY USED',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...breakTemplates.map((t) => _buildTemplateRow(t)),
                      ...pauseTemplates.map((t) => _buildTemplateRow(t)),
                    ],

                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 16,
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

  Widget _buildDragHandle() {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Add Break / Pause',
              style: AppTextStyles.title3.copyWith(fontSize: 18),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCard({
    required SetlistItemType type,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop(AddBreakResult(type: type));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.scaffoldBg,
          border: Border.all(
            color: accentColor.withValues(alpha: 0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: accentColor.withValues(alpha: 0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateRow(SpecialItem template) {
    final isBreak = template.type == SetlistItemType.setBreak;
    final accentColor = isBreak
        ? const Color(0xFFBE123C)
        : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(
            context,
          ).pop(AddBreakResult(type: template.type, template: template));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            border: Border.all(color: AppColors.borderMuted, width: 1),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            children: [
              Icon(
                isBreak
                    ? Icons.timer_outlined
                    : Icons.pause_circle_outline_rounded,
                color: accentColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.displayTitle,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (template.formattedSubDuration != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        template.formattedSubDuration!,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

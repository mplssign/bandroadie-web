import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/special_item.dart';

// ============================================================================
// SET BREAK CREATOR
// Bottom sheet for creating/editing a Set Break.
//
// Layout:
//   - Drag handle
//   - Title: "Set Break"
//   - Duration picker with 5-minute increment buttons (5, 10, 15, 20, 25, 30)
//   - Save to library toggle
//   - Add button
// ============================================================================

/// Result from the Set Break Creator
class SetBreakResult {
  final int durationMinutes;
  final bool saveAsTemplate;
  final bool deleted;

  const SetBreakResult({
    required this.durationMinutes,
    required this.saveAsTemplate,
    this.deleted = false,
  });
}

/// Shows the Set Break creator bottom sheet.
///
/// If [existingItem] is provided, opens in edit mode.
/// Returns [SetBreakResult] if user creates/saves, null if dismissed.
Future<SetBreakResult?> showSetBreakCreator(
  BuildContext context, {
  SpecialItem? existingItem,
}) {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<SetBreakResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _SetBreakCreatorSheet(existingItem: existingItem),
  );
}

class _SetBreakCreatorSheet extends StatefulWidget {
  final SpecialItem? existingItem;

  const _SetBreakCreatorSheet({this.existingItem});

  @override
  State<_SetBreakCreatorSheet> createState() => _SetBreakCreatorSheetState();
}

class _SetBreakCreatorSheetState extends State<_SetBreakCreatorSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  late int _selectedMinutes;
  bool _saveAsTemplate = true;

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.existingItem?.durationMinutes ?? 15;
    _saveAsTemplate = widget.existingItem?.isSavedTemplate ?? true;

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

  bool get _isEditing => widget.existingItem != null;

  @override
  Widget build(BuildContext context) {
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
          maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                    // Duration label
                    const Text(
                      'DURATION',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Duration selector (minus / value / plus)
                    _buildDurationSelector(),
                    const SizedBox(height: 24),

                    // Save to library toggle
                    _buildSaveToggle(),
                    const SizedBox(height: 24),

                    // Action button
                    _buildActionButton(),
                    if (_isEditing) ...[
                      const SizedBox(height: 12),
                      _buildDeleteButton(),
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
          const Icon(Icons.timer_outlined, color: Color(0xFFBE123C), size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isEditing ? 'Edit Set Break' : 'Set Break',
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

  Widget _buildDurationSelector() {
    const rose700 = Color(0xFFBE123C);
    final canDecrease = _selectedMinutes >= 10;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // -5 button
        GestureDetector(
          onTap: canDecrease
              ? () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedMinutes = (_selectedMinutes - 5).clamp(5, 9999);
                  });
                }
              : null,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: canDecrease ? rose700 : rose700.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '-5',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: canDecrease ? rose700 : rose700.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),

        // Duration value
        SizedBox(
          width: 120,
          child: Center(
            child: Text(
              '$_selectedMinutes min',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),

        // +5 button
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedMinutes += 5;
            });
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: rose700, width: 2),
            ),
            child: const Center(
              child: Text(
                '+5',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: rose700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveToggle() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _saveAsTemplate = !_saveAsTemplate);
      },
      child: Row(
        children: [
          Icon(
            _saveAsTemplate
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: _saveAsTemplate
                ? const Color(0xFFBE123C)
                : AppColors.textMuted,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Save to library for quick reuse',
              style: TextStyle(
                color: _saveAsTemplate
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop(
            SetBreakResult(
              durationMinutes: _selectedMinutes,
              saveAsTemplate: _saveAsTemplate,
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFBE123C),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
        ),
        child: Text(
          _isEditing ? 'Save Changes' : 'Add Set Break',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return Center(
      child: TextButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop(
            SetBreakResult(
              durationMinutes: _selectedMinutes,
              saveAsTemplate: _saveAsTemplate,
              deleted: true,
            ),
          );
        },
        child: const Text(
          'Delete',
          style: TextStyle(
            color: AppColors.error,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../models/setlist_item_type.dart';
import '../../models/special_item.dart';
import '../../special_item_repository.dart';

// ============================================================================
// SET BREAK SCREEN
// Inline screen inside the Add-to-Setlist overlay for creating a Set Break.
//
// Includes:
//   - Duration picker (5-min increments)
//   - Save for quick reuse toggle (off by default)
//   - Saved set breaks list
//   - Add button
// ============================================================================

/// Callback result
class SetBreakScreenResult {
  /// If the user tapped a saved template
  final SpecialItem? template;

  /// If the user created new: duration
  final int? durationMinutes;

  /// If the user created new: save for reuse?
  final bool? saveAsTemplate;

  const SetBreakScreenResult({
    this.template,
    this.durationMinutes,
    this.saveAsTemplate,
  });

  bool get isTemplate => template != null;
}

class SetBreakScreen extends ConsumerStatefulWidget {
  final String bandId;
  final void Function(SetBreakScreenResult result) onAdd;
  final VoidCallback onClose;

  const SetBreakScreen({
    super.key,
    required this.bandId,
    required this.onAdd,
    required this.onClose,
  });

  @override
  ConsumerState<SetBreakScreen> createState() => _SetBreakScreenState();
}

class _SetBreakScreenState extends ConsumerState<SetBreakScreen>
    with SingleTickerProviderStateMixin {
  int _selectedMinutes = 15;
  bool _saveAsTemplate = false;

  List<SpecialItem> _savedBreaks = [];
  bool _loadingTemplates = true;

  late AnimationController _entranceController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward();
      _loadSavedBreaks();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedBreaks() async {
    try {
      final repo = ref.read(specialItemRepositoryProvider);
      final templates = await repo.fetchTemplates(
        bandId: widget.bandId,
        typeFilter: SetlistItemType.setBreak,
      );
      if (mounted) {
        setState(() {
          _savedBreaks = templates;
          _loadingTemplates = false;
        });
      }
    } catch (e) {
      debugPrint('[SetBreakScreen] Error loading templates: $e');
      if (mounted) setState(() => _loadingTemplates = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Duration picker ──
                  const Text(
                    'DURATION',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDurationSelector(),
                  const SizedBox(height: 28),

                  // ── Save toggle ──
                  _buildSaveToggle(),
                  const SizedBox(height: 28),

                  // ── Saved breaks ──
                  if (_loadingTemplates)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  else if (_savedBreaks.isNotEmpty) ...[
                    const Text(
                      'SAVED SET BREAKS',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._savedBreaks.map(_buildSavedBreakRow),
                  ],
                ],
              ),
            ),
          ),

          // ── Footer ──
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Duration selector ─────────────────────────────────────────────────

  Widget _buildDurationSelector() {
    const accent = Color(0xFFBE123C);
    final canDecrease = _selectedMinutes >= 10;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // -5
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
                color: canDecrease ? accent : accent.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '-5',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: canDecrease ? accent : accent.withValues(alpha: 0.4),
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

        // +5
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedMinutes += 5);
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
            ),
            child: const Center(
              child: Text(
                '+5',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Save toggle ───────────────────────────────────────────────────────

  Widget _buildSaveToggle() {
    const accent = Color(0xFFBE123C);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _saveAsTemplate = !_saveAsTemplate);
      },
      child: Row(
        children: [
          Icon(
            _saveAsTemplate
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            color: _saveAsTemplate ? accent : AppColors.textMuted,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Save for quick reuse',
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

  // ── Saved break rows ──────────────────────────────────────────────────

  Widget _buildSavedBreakRow(SpecialItem template) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onAdd(SetBreakScreenResult(template: template));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            border: Border.all(color: AppColors.borderMuted, width: 1),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.timer_outlined,
                color: Color(0xFFBE123C),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  template.displayTitle,
                  style: const TextStyle(
                    color: Color(0xFFBE123C),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

  // ── Footer ────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderMuted, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onAdd(
                SetBreakScreenResult(
                  durationMinutes: _selectedMinutes,
                  saveAsTemplate: _saveAsTemplate,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFBE123C),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: const Text(
                'Add Set Break',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

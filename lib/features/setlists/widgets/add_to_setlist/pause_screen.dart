import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../models/setlist_item_type.dart';
import '../../models/special_item.dart';
import '../../special_item_repository.dart';
import '../masked_duration_input.dart';

// ============================================================================
// PAUSE SCREEN
// Inline screen inside the Add-to-Setlist overlay for creating a Pause.
//
// Includes:
//   - Purpose chips (multi-select from predefined list)
//   - Custom purpose text field
//   - Optional duration input (MM:SS)
//   - Save for quick reuse toggle (off by default)
//   - Saved pauses list
//   - Add button
// ============================================================================

/// Callback result
class PauseScreenResult {
  /// If the user tapped a saved template
  final SpecialItem? template;

  /// If the user created new
  final List<String>? purposes;
  final List<String>? customPurposes;
  final int? durationSeconds;
  final bool? saveAsTemplate;

  const PauseScreenResult({
    this.template,
    this.purposes,
    this.customPurposes,
    this.durationSeconds,
    this.saveAsTemplate,
  });

  bool get isTemplate => template != null;
}

class PauseScreen extends ConsumerStatefulWidget {
  final String bandId;
  final void Function(PauseScreenResult result) onAdd;
  final VoidCallback onClose;

  const PauseScreen({
    super.key,
    required this.bandId,
    required this.onAdd,
    required this.onClose,
  });

  @override
  ConsumerState<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends ConsumerState<PauseScreen>
    with SingleTickerProviderStateMixin {
  final Set<String> _selectedPurposes = {};
  final List<String> _customPurposes = [];
  final _customPurposeController = TextEditingController();
  final _customPurposeFocus = FocusNode();

  int? _durationSeconds;
  bool _hasDuration = false;
  bool _saveAsTemplate = false;

  List<SpecialItem> _savedPauses = [];
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
      _loadSavedPauses();
    });
  }

  @override
  void dispose() {
    _customPurposeController.dispose();
    _customPurposeFocus.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPauses() async {
    try {
      final repo = ref.read(specialItemRepositoryProvider);
      final templates = await repo.fetchTemplates(
        bandId: widget.bandId,
        typeFilter: SetlistItemType.pause,
      );
      if (mounted) {
        setState(() {
          _savedPauses = templates;
          _loadingTemplates = false;
        });
      }
    } catch (e) {
      debugPrint('[PauseScreen] Error loading templates: $e');
      if (mounted) setState(() => _loadingTemplates = false);
    }
  }

  bool get _hasSelections =>
      _selectedPurposes.isNotEmpty || _customPurposes.isNotEmpty;

  void _addCustomPurpose() {
    final text = _customPurposeController.text.trim();
    if (text.isNotEmpty && !_customPurposes.contains(text)) {
      HapticFeedback.selectionClick();
      setState(() {
        _customPurposes.add(text);
        _customPurposeController.clear();
      });
    }
  }

  void _removeCustomPurpose(String purpose) {
    HapticFeedback.selectionClick();
    setState(() => _customPurposes.remove(purpose));
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
                  // ── Purpose chips ──
                  const Text(
                    'PURPOSE',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPurposeChips(),
                  const SizedBox(height: 16),

                  // ── Custom purpose ──
                  _buildCustomPurposeInput(),
                  if (_customPurposes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildCustomPurposesList(),
                  ],
                  const SizedBox(height: 24),

                  // ── Duration ──
                  _buildDurationSection(),
                  const SizedBox(height: 24),

                  // ── Save toggle ──
                  _buildSaveToggle(),
                  const SizedBox(height: 28),

                  // ── Saved pauses ──
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
                  else if (_savedPauses.isNotEmpty) ...[
                    const Text(
                      'SAVED PAUSES',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._savedPauses.map(_buildSavedPauseRow),
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

  // ── Purpose chips ─────────────────────────────────────────────────────

  Widget _buildPurposeChips() {
    const amber = Color(0xFFF59E0B);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: PausePurposes.predefined.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final purpose = PausePurposes.predefined[index];
          final isSelected = _selectedPurposes.contains(purpose);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _selectedPurposes.remove(purpose);
                } else {
                  _selectedPurposes.add(purpose);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? amber.withValues(alpha: 0.15)
                    : AppColors.scaffoldBg,
                border: Border.all(
                  color: isSelected ? amber : AppColors.borderMuted,
                  width: isSelected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(Spacing.chipRadius),
              ),
              child: Text(
                purpose,
                style: TextStyle(
                  color: isSelected ? amber : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Custom purpose input ──────────────────────────────────────────────

  Widget _buildCustomPurposeInput() {
    const amber = Color(0xFFF59E0B);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _customPurposeController,
              focusNode: _customPurposeFocus,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Add custom purpose...',
                hintStyle: AppTextStyles.body.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.scaffoldBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.borderMuted),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.borderMuted),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: amber, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _addCustomPurpose(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _addCustomPurpose,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(color: amber, width: 1),
            ),
            child: const Icon(Icons.add_rounded, color: amber, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomPurposesList() {
    const amber = Color(0xFFF59E0B);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _customPurposes.map((purpose) {
        return Container(
          padding: const EdgeInsets.only(left: 14, right: 6, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.15),
            border: Border.all(color: amber, width: 1),
            borderRadius: BorderRadius.circular(Spacing.chipRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                purpose,
                style: const TextStyle(
                  color: amber,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _removeCustomPurpose(purpose),
                child: const Icon(Icons.close_rounded, color: amber, size: 16),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Duration section ──────────────────────────────────────────────────

  Widget _buildDurationSection() {
    const amber = Color(0xFFF59E0B);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _hasDuration = !_hasDuration;
              if (!_hasDuration) _durationSeconds = null;
            });
          },
          child: Row(
            children: [
              Icon(
                _hasDuration
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: _hasDuration ? amber : AppColors.textMuted,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'DURATION (OPTIONAL)',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        if (_hasDuration) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 110,
            height: 48,
            child: MaskedDurationInput(
              initialSeconds: _durationSeconds ?? 0,
              maxDigits: 3,
              onChanged: (seconds) {
                setState(() {
                  _durationSeconds = seconds > 0 ? seconds : null;
                });
              },
              textStyle: const TextStyle(
                color: amber,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
              backgroundColor: AppColors.scaffoldBg,
              borderColor: AppColors.borderMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter minutes and seconds',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }

  // ── Save toggle ───────────────────────────────────────────────────────

  Widget _buildSaveToggle() {
    const amber = Color(0xFFF59E0B);
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
            color: _saveAsTemplate ? amber : AppColors.textMuted,
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

  // ── Saved pause rows ──────────────────────────────────────────────────

  Widget _buildSavedPauseRow(SpecialItem template) {
    const amber = Color(0xFFF59E0B);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onAdd(PauseScreenResult(template: template));
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
                Icons.pause_circle_outline_rounded,
                color: amber,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.displayTitle,
                      style: const TextStyle(
                        color: amber,
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
                        style: const TextStyle(
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

  // ── Footer ────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    const amber = Color(0xFFF59E0B);
    final isEnabled = _hasSelections;

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
            onTap: isEnabled
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onAdd(
                      PauseScreenResult(
                        purposes: _selectedPurposes.toList(),
                        customPurposes: _customPurposes,
                        durationSeconds: _hasDuration ? _durationSeconds : null,
                        saveAsTemplate: _saveAsTemplate,
                      ),
                    );
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isEnabled ? amber : amber.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: Text(
                'Add Pause',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isEnabled ? Colors.black87 : Colors.white38,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

// ============================================================================
// TITLE PILL SELECTOR
// Horizontally scrollable, single-select pill badge for contact title.
// Predefined options + "Custom" entry with inline TextField.
// ============================================================================

const List<String> _kPredefinedTitles = [
  'Booking Agent',
  'Sound',
  'Owner',
  'Manager',
];

class TitlePillSelector extends StatefulWidget {
  final String? selectedTitle;
  final ValueChanged<String?> onChanged;

  const TitlePillSelector({
    super.key,
    required this.selectedTitle,
    required this.onChanged,
  });

  @override
  State<TitlePillSelector> createState() => _TitlePillSelectorState();
}

class _TitlePillSelectorState extends State<TitlePillSelector> {
  bool _isCustomMode = false;
  late TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    // If selectedTitle is non-null and not in predefined list, it's custom
    final isCustomValue = widget.selectedTitle != null &&
        !_kPredefinedTitles.contains(widget.selectedTitle);
    _isCustomMode = isCustomValue;
    _customController = TextEditingController(
      text: isCustomValue ? widget.selectedTitle : '',
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _selectPredefined(String title) {
    setState(() {
      _isCustomMode = false;
      _customController.clear();
    });
    if (widget.selectedTitle == title) {
      widget.onChanged(null);
    } else {
      widget.onChanged(title);
    }
  }

  void _toggleCustom() {
    setState(() {
      _isCustomMode = !_isCustomMode;
      if (!_isCustomMode) {
        _customController.clear();
        widget.onChanged(null);
      }
    });
  }

  void _onCustomSubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      widget.onChanged(trimmed);
    } else {
      widget.onChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ..._kPredefinedTitles.map((title) {
                final isSelected =
                    !_isCustomMode && widget.selectedTitle == title;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _selectPredefined(title),
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      curve: AppCurves.ease,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // Custom pill
              GestureDetector(
                onTap: _toggleCustom,
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  curve: AppCurves.ease,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _isCustomMode ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    'Custom',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _isCustomMode ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isCustomMode) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customController,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: 'Enter custom title',
              hintStyle: TextStyle(color: context.colors.textMuted),
              filled: true,
              fillColor: context.colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: _onCustomSubmitted,
            onSubmitted: _onCustomSubmitted,
          ),
        ],
      ],
    );
  }
}

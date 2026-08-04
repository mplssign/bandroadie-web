import 'package:flutter/material.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/brand_colors.dart';

const _kMajorKeys = [
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B'
];

const _kMinorKeys = [
  'Cm',
  'C#m',
  'Dm',
  'Ebm',
  'Em',
  'Fm',
  'F#m',
  'Gm',
  'Abm',
  'Am',
  'Bbm',
  'Bm'
];

/// Shows a bottom sheet for selecting a musical key
///
/// Returns the selected key string, or null if cancelled
Future<String?> showKeyPickerBottomSheet(
  BuildContext context, {
  String? selectedKey,
}) async {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _KeyPickerBottomSheet(selectedKey: selectedKey),
  );
}

class _KeyPickerBottomSheet extends StatelessWidget {
  final String? selectedKey;

  const _KeyPickerBottomSheet({this.selectedKey});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: Spacing.space12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: Spacing.space16),

          // Title
          Text(
            'Select Key',
            style: AppTextStyles.headline.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: Spacing.space16),

          // Key list
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(
                    'None',
                    style: AppTextStyles.callout.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  trailing: (selectedKey == null || selectedKey!.isEmpty)
                      ? const Icon(
                          Icons.check,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(''),
                ),

                const SizedBox(height: Spacing.space8),

                // Major section
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.space16,
                    vertical: Spacing.space8,
                  ),
                  child: Text(
                    'Major',
                    style: AppTextStyles.footnote.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                ..._kMajorKeys.map((key) => _buildKeyTile(context, key)),

                const SizedBox(height: Spacing.space16),

                // Minor section
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.space16,
                    vertical: Spacing.space8,
                  ),
                  child: Text(
                    'Minor',
                    style: AppTextStyles.footnote.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                ..._kMinorKeys.map((key) => _buildKeyTile(context, key)),

                const SizedBox(height: Spacing.space16),
              ],
            ),
          ),

          // Cancel button
          Padding(
            padding: const EdgeInsets.all(Spacing.space16),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: Spacing.space16),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.button.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyTile(BuildContext context, String key) {
    final isSelected = key == selectedKey;

    return ListTile(
      title: Text(
        key,
        style: AppTextStyles.callout.copyWith(
          color: Colors.white,
        ),
      ),
      trailing: isSelected
          ? const Icon(
              Icons.check,
              color: AppColors.primary,
            )
          : null,
      onTap: () => Navigator.of(context).pop(isSelected ? '' : key),
    );
  }
}

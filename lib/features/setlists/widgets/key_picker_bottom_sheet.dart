import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../components/ui/app_button.dart';

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
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _KeyPickerBottomSheet(
      selectedKey: selectedKey,
    ),
  );
}

class _KeyPickerBottomSheet extends StatefulWidget {
  final String? selectedKey;

  const _KeyPickerBottomSheet({this.selectedKey});

  @override
  State<_KeyPickerBottomSheet> createState() => _KeyPickerBottomSheetState();
}

class _KeyPickerBottomSheetState extends State<_KeyPickerBottomSheet> {
  late String _pendingKey;
  late String _initialKey;
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};
  bool _didAutoScrollOnOpen = false;

  bool get _hasChanges => _pendingKey != _initialKey;

  @override
  void initState() {
    super.initState();
    _pendingKey = widget.selectedKey ?? '';
    _initialKey = widget.selectedKey ?? '';
  }

  void _selectKey(String key) {
    setState(() => _pendingKey = key);
  }

  void _handleSave() {
    Navigator.of(context).pop(_pendingKey);
  }

  void _handleCancel() {
    Navigator.of(context).pop(null);
  }

  GlobalKey _tileKeyFor(String key) {
    return _tileKeys.putIfAbsent(key, () => GlobalKey());
  }

  void _maybeCenterSelectedKeyOnOpen() {
    if (_didAutoScrollOnOpen || _pendingKey.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didAutoScrollOnOpen) {
        return;
      }

      final selectedTileContext = _tileKeys[_pendingKey]?.currentContext;
      if (selectedTileContext != null) {
        Scrollable.ensureVisible(
          selectedTileContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }

      _didAutoScrollOnOpen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.6, 0.95],
      builder: (context, scrollController) {
        _maybeCenterSelectedKeyOnOpen();
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Spacing.cardRadius),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDragHandle(context),
              _buildHeader(context),
              Divider(
                color: context.colors.border,
                height: 1,
                thickness: 1,
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    _buildSectionHeader(context, 'None'),
                    _buildKeyTile(context, ''),
                    _buildSectionHeader(context, 'Major'),
                    ..._kMajorKeys.map((key) => _buildKeyTile(context, key)),
                    _buildSectionHeader(context, 'Minor'),
                    ..._kMinorKeys.map((key) => _buildKeyTile(context, key)),
                    const SizedBox(height: Spacing.space16),
                  ],
                ),
              ),
              _buildFixedBottomActions(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragHandle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: Spacing.space12,
        bottom: Spacing.space8,
      ),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: context.colors.textMuted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space4,
        Spacing.pagePadding,
        Spacing.space12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Select Key', style: AppTextStyles.title3),
          GestureDetector(
            onTap: _handleCancel,
            child: Container(
              padding: const EdgeInsets.all(Spacing.space4),
              child: Icon(
                AppIcons.close,
                color: context.colors.textSecondary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space20,
        Spacing.pagePadding,
        Spacing.space8,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppFontSizes.body,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildKeyTile(BuildContext context, String key) {
    final isSelected = key == _pendingKey;
    final label = key.isEmpty ? 'None' : key;

    return Container(
      key: _tileKeyFor(key),
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.pagePadding,
        vertical: Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.16)
            : context.colors.surface,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(
          color: isSelected ? AppColors.primary : context.colors.border,
        ),
      ),
      child: ListTile(
        title: Text(
          label,
          style: AppTextStyles.callout.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        trailing: isSelected
            ? const Icon(
                Icons.check,
                color: AppColors.primary,
              )
            : null,
        onTap: () => _selectKey(key),
      ),
    );
  }

  Widget _buildFixedBottomActions(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(
            color: context.colors.border.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        top: 12,
        bottom: bottomSafe + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Save',
            onPressed: _hasChanges ? _handleSave : null,
            variant: AppButtonVariant.primary,
            backgroundColor: _hasChanges
                ? AppColors.primary
                : context.colors.border.withValues(alpha: 0.3),
            disabledBackgroundColor:
                context.colors.border.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(vertical: 16),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            fullWidth: true,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Cancel',
            onPressed: _handleCancel,
            variant: AppButtonVariant.text,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'package:bandroadie/components/ui/app_switch.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import 'package:bandroadie/shared/utils/snackbar_helper.dart';
import '../models/print_template.dart';
import '../models/setlist_item.dart';
import '../print_template_repository.dart';
import '../setlist_pdf_preview_screen.dart';

// ============================================================================
// PRINT OPTIONS BOTTOM SHEET
// Layout configuration with saved layouts, per-section font sizes, and
// preview navigation.
// ============================================================================

class PrintOptionsBottomSheet extends StatefulWidget {
  final String bandId;
  final String setlistName;
  final List<SetlistItem> items;
  final String? bandName;
  final String? gigDate;
  final String? venue;

  const PrintOptionsBottomSheet({
    super.key,
    required this.bandId,
    required this.setlistName,
    required this.items,
    this.bandName,
    this.gigDate,
    this.venue,
  });

  static Future<void> show(
    BuildContext context, {
    required String bandId,
    required String setlistName,
    required List<SetlistItem> items,
    String? bandName,
    String? gigDate,
    String? venue,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => PrintOptionsBottomSheet(
        bandId: bandId,
        setlistName: setlistName,
        items: items,
        bandName: bandName,
        gigDate: gigDate,
        venue: venue,
      ),
    );
  }

  @override
  State<PrintOptionsBottomSheet> createState() =>
      _PrintOptionsBottomSheetState();
}

class _PrintOptionsBottomSheetState extends State<PrintOptionsBottomSheet> {
  final _repo = PrintTemplateRepository();
  List<PrintTemplate> _templates = [];
  late PrintTemplate _current;
  String? _selectedTemplateId; // null = unsaved / default
  bool _isLoading = true;
  bool _isRemoveMode = false;

  @override
  void initState() {
    super.initState();
    _current = PrintTemplate.defaultTemplate(bandId: widget.bandId);
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final templates = await _repo.fetchTemplates(widget.bandId);
    final lastUsedId = await _repo.getLastUsedTemplateId(widget.bandId);

    if (!mounted) return;

    PrintTemplate selected =
        PrintTemplate.defaultTemplate(bandId: widget.bandId);
    String? selectedId;

    if (lastUsedId != null) {
      final match = templates.where((t) => t.id == lastUsedId).firstOrNull;
      if (match != null) {
        selected = match;
        selectedId = match.id;
      }
    }

    setState(() {
      _templates = templates;
      _current = selected;
      _selectedTemplateId = selectedId;
      _isLoading = false;
    });
  }

  void _selectTemplate(PrintTemplate template) {
    setState(() {
      _current = template;
      _selectedTemplateId = template.id;
    });
  }

  void _clearSelection() {
    setState(() {
      _current = PrintTemplate.defaultTemplate(bandId: widget.bandId);
      _selectedTemplateId = null;
    });
  }

  // ---------------------------------------------------------------------------
  // PREVIEW
  // ---------------------------------------------------------------------------

  Future<void> _handlePreview() async {
    if (_current.id != null) {
      await _repo.setLastUsed(widget.bandId, _current.id!);
    }
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SetlistPdfPreviewScreen(
            setlistName: widget.setlistName,
            items: widget.items,
            template: _current,
            bandName: widget.bandName,
            gigDate: widget.gigDate,
            venue: widget.venue,
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SAVE LAYOUT DIALOG
  // ---------------------------------------------------------------------------

  Future<void> _showSaveLayoutDialog() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: context.colors.surfaceElevated,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('Save layout',
                  style: AppTextStyles.title3
                      .copyWith(color: context.colors.textPrimary)),
              content: AppTextField(
                controller: controller,
                autofocus: true,
                hintText: 'Layout name',
                onChanged: (_) => setDialogState(() {}),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(ctx).pop(false),
                        variant: AppButtonVariant.outlined,
                        borderRadius:
                            BorderRadius.circular(Spacing.buttonRadius),
                        fullWidth: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Save',
                        onPressed: controller.text.trim().isEmpty
                            ? null
                            : () => Navigator.of(ctx).pop(true),
                        variant: AppButtonVariant.outlined,
                        borderRadius:
                            BorderRadius.circular(Spacing.buttonRadius),
                        fullWidth: true,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;

    final name = controller.text.trim();
    if (name.isEmpty) return;

    // Check if a layout with the same name already exists — overwrite
    final existing = _templates.where((t) => t.name == name).firstOrNull;

    try {
      PrintTemplate saved;
      if (existing != null) {
        saved = await _repo.updateTemplate(
          _current.copyWith(id: existing.id, name: name),
        );
      } else {
        saved = await _repo.createTemplate(
          widget.bandId,
          _current.copyWith(name: name),
        );
      }

      if (!mounted) return;

      // Reload templates from DB to guarantee the chip list is fresh
      final freshTemplates = await _repo.fetchTemplates(widget.bandId);
      if (!mounted) return;

      final match = freshTemplates.where((t) => t.id == saved.id).firstOrNull;
      setState(() {
        _templates = freshTemplates;
        if (match != null) {
          _current = match;
          _selectedTemplateId = match.id;
        }
      });

      if (mounted) {
        showSuccessSnackBar(context, message: 'Layout "$name" saved');
      }
    } catch (e) {
      debugPrint('[PrintOptions] Save layout error: $e');
      if (mounted) {
        showErrorSnackBar(context, message: 'Save failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Print Options',
                    style: AppTextStyles.title3
                        .copyWith(color: context.colors.textPrimary),
                  ),
                  const Spacer(),
                  AppIconButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                    color: context.colors.textSecondary,
                  ),
                ],
              ),
            ),

            // Saved layouts chip row
            if (!_isLoading) _buildSavedLayoutsRow(),

            Divider(color: context.colors.border, height: 1),

            // Scrollable options
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: AppProgressIndicator(color: AppColors.primary))
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      children: [
                        // 1. Song Name (always on, no toggle)
                        _buildSection(
                          label: 'Song Name',
                          fontSize: _current.baseFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(baseFontSize: v)),
                        ),

                        // Line Spacing
                        _buildLineSpacingSection(),

                        // 2. Song Numbers
                        _buildSection(
                          label: 'Song Numbers',
                          toggleValue: _current.showSongNumbers,
                          onToggleChanged: (v) => setState(() =>
                              _current = _current.copyWith(showSongNumbers: v)),
                          fontSize: _current.numberFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(numberFontSize: v)),
                        ),

                        // 3. Setlist Name
                        _buildSection(
                          label: 'Setlist Name',
                          toggleValue: _current.showHeader,
                          onToggleChanged: (v) => setState(() =>
                              _current = _current.copyWith(showHeader: v)),
                          fontSize: _current.headerFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(headerFontSize: v)),
                        ),

                        // 4. Band Name
                        _buildSection(
                          label: 'Band Name',
                          toggleValue: _current.showBandName,
                          onToggleChanged: (v) => setState(() =>
                              _current = _current.copyWith(showBandName: v)),
                          fontSize: _current.bandNameFontSize,
                          onFontSizeChanged: (v) => setState(() => _current =
                              _current.copyWith(bandNameFontSize: v)),
                        ),

                        // 5. Pauses
                        _buildSection(
                          label: 'Pauses',
                          toggleValue: _current.showPauses,
                          onToggleChanged: (v) => setState(() =>
                              _current = _current.copyWith(showPauses: v)),
                          fontSize: _current.pauseFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(pauseFontSize: v)),
                        ),

                        // 5. BPM
                        _buildSection(
                          label: 'BPM',
                          toggleValue: _current.showBpm,
                          onToggleChanged: (v) => setState(
                              () => _current = _current.copyWith(showBpm: v)),
                          fontSize: _current.bpmFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(bpmFontSize: v)),
                        ),

                        // Key
                        _buildSection(
                          label: 'Key',
                          toggleValue: _current.showKey,
                          onToggleChanged: (v) => setState(
                              () => _current = _current.copyWith(showKey: v)),
                          fontSize: _current.keyFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(keyFontSize: v)),
                        ),

                        // 5. Tuning
                        _buildSection(
                          label: 'Tuning',
                          toggleValue: _current.showTuning,
                          onToggleChanged: (v) => setState(() =>
                              _current = _current.copyWith(showTuning: v)),
                          fontSize: _current.tuningFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(tuningFontSize: v)),
                          extraWidget: _buildSubToggle(
                            label: 'Full width',
                            value: _current.tuningDisplay == 'grouped',
                            onChanged: (v) => setState(() => _current =
                                _current.copyWith(
                                    tuningDisplay: v ? 'grouped' : 'inline')),
                          ),
                        ),

                        // 6. Capo
                        _buildSection(
                          label: 'Capo',
                          toggleValue: _current.showCapo,
                          onToggleChanged: (v) => setState(
                              () => _current = _current.copyWith(showCapo: v)),
                          fontSize: _current.capoFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(capoFontSize: v)),
                        ),

                        // 7. Notes
                        _buildSection(
                          label: 'Notes',
                          toggleValue: _current.showNotes,
                          onToggleChanged: (v) => setState(
                              () => _current = _current.copyWith(showNotes: v)),
                          fontSize: _current.notesFontSize,
                          onFontSizeChanged: (v) => setState(() =>
                              _current = _current.copyWith(notesFontSize: v)),
                        ),

                        // Paper Size
                        _buildPaperSizeSection(),

                        const SizedBox(height: 24),
                      ],
                    ),
            ),

            // Bottom action bar
            _buildBottomBar(),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SAVED LAYOUTS ROW
  // ---------------------------------------------------------------------------

  Future<void> _handleDeleteTemplate(PrintTemplate template) async {
    if (template.id == null) return;

    try {
      await _repo.deleteTemplate(template.id!);
      if (!mounted) return;

      final freshTemplates = await _repo.fetchTemplates(widget.bandId);
      if (!mounted) return;

      setState(() {
        _templates = freshTemplates;
        if (_selectedTemplateId == template.id) {
          _selectedTemplateId = null;
          _current = PrintTemplate.defaultTemplate(bandId: widget.bandId);
        }
        if (_templates.isEmpty) {
          _isRemoveMode = false;
        }
      });
    } catch (e) {
      debugPrint('[PrintOptions] Delete layout error: $e');
      if (mounted) {
        showErrorSnackBar(context, message: 'Delete failed: $e');
      }
    }
  }

  Widget _buildSavedLayoutsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Saved Layouts',
                  style: AppTextStyles.calloutEmphasized
                      .copyWith(color: context.colors.textPrimary),
                ),
              ),
              if (_templates.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _isRemoveMode = !_isRemoveMode),
                  child: Text(
                    _isRemoveMode ? 'Done' : 'Remove',
                    style: AppTextStyles.footnote.copyWith(
                      color:
                          _isRemoveMode ? AppColors.primary : AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_templates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12),
            child: Text(
              'No saved layouts yet',
              style: AppTextStyles.footnote
                  .copyWith(color: context.colors.textMuted),
            ),
          )
        else ...[
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _templates.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final template = _templates[index];
                final isSelected = template.id == _selectedTemplateId;
                return GestureDetector(
                  onTap: () {
                    if (_isRemoveMode) {
                      _handleDeleteTemplate(template);
                    } else if (isSelected) {
                      _clearSelection();
                    } else {
                      _selectTemplate(template);
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isRemoveMode
                          ? AppColors.error.withValues(alpha: 0.1)
                          : isSelected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isRemoveMode
                            ? AppColors.error
                            : isSelected
                                ? AppColors.primary
                                : context.colors.borderStrong,
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            template.name,
                            style: AppTextStyles.footnote.copyWith(
                              color: _isRemoveMode
                                  ? AppColors.error
                                  : isSelected
                                      ? AppColors.primary
                                      : context.colors.textSecondary,
                              fontWeight: _isRemoveMode || isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          if (_isRemoveMode) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: AppColors.error,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // OPTION SECTION BUILDER
  // ---------------------------------------------------------------------------

  Widget _buildSection({
    required String label,
    bool? toggleValue,
    ValueChanged<bool>? onToggleChanged,
    required double fontSize,
    required ValueChanged<double> onFontSizeChanged,
    Widget? extraWidget,
  }) {
    return Column(
      children: [
        Divider(color: context.colors.border, height: 1),
        const SizedBox(height: 12),
        // Label + toggle row
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.calloutEmphasized
                    .copyWith(color: context.colors.textPrimary),
              ),
            ),
            if (toggleValue != null && onToggleChanged != null)
              AppSwitch(
                value: toggleValue,
                onChanged: onToggleChanged,
                activeTrackColor: AppColors.primary,
                useAdaptiveSwitch: true,
              ),
          ],
        ),
        if (extraWidget != null) ...[
          const SizedBox(height: 4),
          extraWidget,
        ],
        const SizedBox(height: 4),
        // Font size slider row
        Row(
          children: [
            Text(
              'Font size',
              style: AppTextStyles.footnote
                  .copyWith(color: context.colors.textSecondary),
            ),
            const SizedBox(width: 8),
            Text(
              '${fontSize.round()}px',
              style: AppTextStyles.footnote.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: context.colors.surfaceOverlay,
                  thumbColor: AppColors.primary,
                ),
                child: Slider(
                  value: fontSize.clamp(14.0, 36.0),
                  min: 14.0,
                  max: 36.0,
                  divisions: 22,
                  onChanged: onFontSizeChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSubToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.footnote
                .copyWith(color: context.colors.textSecondary),
          ),
        ),
        AppSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.primary,
          useAdaptiveSwitch: true,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // LINE SPACING SECTION
  // ---------------------------------------------------------------------------

  Widget _buildLineSpacingSection() {
    return Column(
      children: [
        Divider(color: context.colors.border, height: 1),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Line Spacing',
                style: AppTextStyles.calloutEmphasized
                    .copyWith(color: context.colors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Spacing',
              style: AppTextStyles.footnote
                  .copyWith(color: context.colors.textSecondary),
            ),
            const SizedBox(width: 8),
            Text(
              '${_current.lineSpacing.toStringAsFixed(1)}x',
              style: AppTextStyles.footnote.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: context.colors.surfaceOverlay,
                  thumbColor: AppColors.primary,
                ),
                child: Slider(
                  value: _current.lineSpacing.clamp(0.0, 3.0),
                  min: 0.0,
                  max: 3.0,
                  divisions: 30,
                  onChanged: (v) => setState(
                      () => _current = _current.copyWith(lineSpacing: v)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAPER SIZE SECTION
  // ---------------------------------------------------------------------------

  static const _paperSizes = [
    ('letter', 'Letter'),
    ('a4', 'A4'),
    ('legal', 'Legal'),
    ('tabloid', 'Tabloid'),
  ];

  Widget _buildPaperSizeSection() {
    return Column(
      children: [
        Divider(color: context.colors.border, height: 1),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Paper Size',
                style: AppTextStyles.calloutEmphasized
                    .copyWith(color: context.colors.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: _paperSizes.map((entry) {
            final (value, label) = entry;
            final isSelected = _current.paperSize == value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: entry != _paperSizes.last ? 8.0 : 0.0,
                ),
                child: GestureDetector(
                  onTap: () => setState(
                      () => _current = _current.copyWith(paperSize: value)),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : context.colors.borderStrong,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: AppTextStyles.footnote.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : context.colors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM ACTION BAR
  // ---------------------------------------------------------------------------

  Widget _buildBottomBar() {
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
      child: Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'Save layout',
              onPressed: _showSaveLayoutDialog,
              variant: AppButtonVariant.outlined,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              fullWidth: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppButton(
              label: 'Preview',
              onPressed: _handlePreview,
              variant: AppButtonVariant.primary,
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              fullWidth: true,
            ),
          ),
        ],
      ),
    );
  }
}

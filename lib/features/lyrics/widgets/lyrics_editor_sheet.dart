import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/features/lyrics/models/lyrics_data.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// LYRICS EDITOR BOTTOM SHEET
//
// Full-screen drawer for editing song lyrics with:
// • Single horizontally scrollable formatting toolbar
// • Circular rose-outlined font-size –/+ buttons
// • Bold toggle with rose active state
// • Color preset chips with colored dots (per-block or default)
// • Text selection → applies highlight to the containing block
// • Per-block text coloring in the editor via custom controller
// ============================================================================

/// Custom [TextEditingController] that renders each lyric block in its
/// assigned highlight accent color.  Blocks are separated by `\n\n`.
class _HighlightedLyricsController extends TextEditingController {
  _HighlightedLyricsController({super.text});

  /// Updated by the editor state whenever block highlights change.
  Map<int, LyricsHighlight> blockHighlights = {};

  /// The fallback highlight for blocks with no explicit override.
  LyricsHighlight activeHighlight = LyricsHighlight.none;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final fullText = text;
    if (fullText.isEmpty ||
        blockHighlights.isEmpty && activeHighlight == LyricsHighlight.none) {
      return TextSpan(text: fullText, style: style);
    }

    // Split on single newlines — each line is a colorable block.
    final lines = fullText.split('\n');
    final spans = <TextSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final highlight = blockHighlights[i] ?? activeHighlight;
      final lineStyle = highlight != LyricsHighlight.none
          ? style?.copyWith(color: Color(highlight.accentColorValue))
          : style;
      spans.add(TextSpan(text: lines[i], style: lineStyle));

      // Add newline separator between lines (not after last)
      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: style));
      }
    }

    return TextSpan(children: spans, style: style);
  }
}

/// Shows a full-screen lyrics editor and returns the [LyricsData] on save.
Future<LyricsData?> showLyricsEditor(
  BuildContext context, {
  LyricsData? initialData,
}) {
  return showModalBottomSheet<LyricsData>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LyricsEditorSheet(initialData: initialData),
  );
}

class _LyricsEditorSheet extends StatefulWidget {
  final LyricsData? initialData;
  const _LyricsEditorSheet({this.initialData});

  @override
  State<_LyricsEditorSheet> createState() => _LyricsEditorSheetState();
}

class _LyricsEditorSheetState extends State<_LyricsEditorSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;

  late final _HighlightedLyricsController _textController;
  late final FocusNode _focusNode;

  // ── Formatting state ──────────────────────────────────────────────────────
  double _fontSize = 22.0;
  LyricsHighlight _activeHighlight = LyricsHighlight.none;

  /// Per-line highlight overrides.  Key = line index (0-based).
  /// Lines are separated by single `\n` characters in the editor text.
  final Map<int, LyricsHighlight> _blockHighlights = {};

  /// Snapshot of the editor text used to detect line insertions / deletions
  /// so that [_blockHighlights] indices stay in sync with the actual lines.
  String _prevText = '';

  // ── Constants ─────────────────────────────────────────────────────────────
  static const double _minFont = 10.0;
  static const double _maxFont = 32.0;
  static const double _fontStep = 2.0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    final data = widget.initialData;
    if (data != null && data.isNotEmpty) {
      _textController = _HighlightedLyricsController(text: data.plainText);
      // Treat the old default (16.0) as the new default (22.0)
      _fontSize = data.defaultFontSize == 16.0 ? 22.0 : data.defaultFontSize;
      // Pre-populate per-line highlights from existing block data.
      // plainText joins blocks with '\n\n'.  When split by '\n' that
      // separator produces exactly ONE blank line between blocks.
      int lineIdx = 0;
      for (var i = 0; i < data.blocks.length; i++) {
        final block = data.blocks[i];
        final lineCount = '\n'.allMatches(block.text).length + 1;
        if (block.highlight != LyricsHighlight.none) {
          for (int l = 0; l < lineCount; l++) {
            _blockHighlights[lineIdx + l] = block.highlight;
          }
        }
        lineIdx += lineCount;
        // The '\n\n' separator between blocks creates 1 blank line when
        // the text is split by '\n', so advance by 1.
        if (i < data.blocks.length - 1) {
          lineIdx += 1;
        }
      }
    } else {
      _textController = _HighlightedLyricsController();
    }

    _focusNode = FocusNode();
    _prevText = _textController.text;
    _syncControllerHighlights();
    _textController.addListener(_onControllerChanged);
    _animCtrl.forward();
  }

  /// Track the previous selection to avoid unnecessary rebuilds.
  TextSelection _prevSelection = const TextSelection.collapsed(offset: -1);

  /// Unified listener for text + selection changes.
  void _onControllerChanged() {
    // 1. Keep highlight indices in sync when lines are added / removed.
    _adjustHighlightsForLineChanges();

    // 2. Rebuild UI when caret moves so chips reflect current line highlight.
    final sel = _textController.selection;
    if (sel != _prevSelection) {
      _prevSelection = sel;
      setState(() {});
    }
  }

  /// Detect line insertions / deletions and shift [_blockHighlights] entries
  /// so that colours stay anchored to the correct lines.
  void _adjustHighlightsForLineChanges() {
    final newText = _textController.text;
    if (newText == _prevText) return;

    final oldLines = _prevText.split('\n');
    final newLines = newText.split('\n');
    final lineDiff = newLines.length - oldLines.length;

    if (lineDiff != 0) {
      // Find matching prefix (lines identical from the start).
      int prefixLen = 0;
      final minPfx =
          oldLines.length < newLines.length ? oldLines.length : newLines.length;
      while (prefixLen < minPfx && oldLines[prefixLen] == newLines[prefixLen]) {
        prefixLen++;
      }

      // Find matching suffix (lines identical from the end).
      int oldEnd = oldLines.length;
      int newEnd = newLines.length;
      while (oldEnd > prefixLen &&
          newEnd > prefixLen &&
          oldLines[oldEnd - 1] == newLines[newEnd - 1]) {
        oldEnd--;
        newEnd--;
      }

      final oldCount = oldEnd - prefixLen; // lines removed
      final newCount = newEnd - prefixLen; // lines inserted
      final shift = newCount - oldCount;

      // For pure insertions inside a highlighted region, inherit the
      // colour of the line immediately before the insertion point.
      LyricsHighlight? inheritHighlight;
      if (oldCount == 0 && newCount > 0 && prefixLen > 0) {
        inheritHighlight = _blockHighlights[prefixLen - 1];
      }

      final updated = <int, LyricsHighlight>{};
      for (final entry in _blockHighlights.entries) {
        if (entry.key < prefixLen) {
          // Before changed region → keep.
          updated[entry.key] = entry.value;
        } else if (entry.key >= prefixLen + oldCount) {
          // After changed region → shift.
          updated[entry.key + shift] = entry.value;
        }
        // In the removed range → drop.
      }

      // Apply inherited highlight to newly inserted lines.
      if (inheritHighlight != null &&
          inheritHighlight != LyricsHighlight.none) {
        for (int i = prefixLen; i < prefixLen + newCount; i++) {
          updated.putIfAbsent(i, () => inheritHighlight!);
        }
      }

      _blockHighlights
        ..clear()
        ..addAll(updated);
      _syncControllerHighlights();
    }

    _prevText = newText;
  }

  @override
  void dispose() {
    _textController.removeListener(_onControllerChanged);
    _animCtrl.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the 0-based line index that contains [offset].
  /// Each line (separated by `\n`) is its own colorable block.
  int _blockIndexAtOffset(int offset) {
    final text = _textController.text;
    final clamped = offset.clamp(0, text.length);
    int lineIdx = 0;
    for (int i = 0; i < clamped; i++) {
      if (text[i] == '\n') lineIdx++;
    }
    return lineIdx;
  }

  /// Called when a color-preset chip is tapped.
  ///
  /// If the cursor is inside the text → apply the highlight to every line
  /// the selection spans (works for both collapsed cursor and range selection).
  /// If no cursor → set as the active default for new text.
  /// Tapping the already-active chip toggles it off (→ none).
  void _onHighlightTapped(LyricsHighlight h) {
    final sel = _textController.selection;
    final cursorInText =
        sel.isValid && sel.baseOffset >= 0 && _textController.text.isNotEmpty;

    setState(() {
      if (cursorInText) {
        final startIdx = _blockIndexAtOffset(sel.start);
        final endIdx = _blockIndexAtOffset(sel.end);

        // Check if ALL lines in range already have this highlight (toggle off)
        bool allMatch = true;
        for (int i = startIdx; i <= endIdx; i++) {
          if (_blockHighlights[i] != h) {
            allMatch = false;
            break;
          }
        }

        for (int i = startIdx; i <= endIdx; i++) {
          if (allMatch) {
            _blockHighlights.remove(i);
          } else {
            _blockHighlights[i] = h;
          }
        }
      } else {
        _activeHighlight = (_activeHighlight == h) ? LyricsHighlight.none : h;
      }
      _syncControllerHighlights();
    });
  }

  /// Push the current highlight state into the controller so
  /// [buildTextSpan] renders the correct colors.
  void _syncControllerHighlights() {
    _textController.blockHighlights = Map.of(_blockHighlights);
    _textController.activeHighlight = _activeHighlight;
  }

  void _handleSave() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(const LyricsData(blocks: []));
      return;
    }

    // Each line is its own block (matches per-line coloring in the editor).
    // Consecutive lines with the same highlight are merged into one block
    // so the saved data stays compact.
    final lines = text.split('\n');
    final blocks = <LyricsBlock>[];

    for (var i = 0; i < lines.length; i++) {
      final lineText = lines[i];
      final highlight = _blockHighlights[i] ?? _activeHighlight;

      // Merge with previous block if same highlight and previous isn't empty
      if (blocks.isNotEmpty && blocks.last.highlight == highlight) {
        final prev = blocks.removeLast();
        blocks.add(
          LyricsBlock(
            text: '${prev.text}\n$lineText',
            highlight: highlight,
            fontSize: _fontSize,
            isBold: true,
          ),
        );
      } else {
        blocks.add(
          LyricsBlock(
            text: lineText,
            highlight: highlight,
            fontSize: _fontSize,
            isBold: true,
          ),
        );
      }
    }

    // Remove blocks that are only whitespace
    blocks.removeWhere((b) => b.text.trim().isEmpty);

    Navigator.of(context).pop(
      LyricsData(
        blocks: blocks,
        defaultFontSize: _fontSize,
        defaultBold: true,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    return SlideTransition(
      position: _slideAnim,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildFormattingToolbar(),
            Divider(color: context.colors.border, height: 1),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: keyboardHeight),
                child: _buildTextArea(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Row(
        children: [
          // Cancel
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Edit Lyrics',
            style: AppTextStyles.body.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Save
          TextButton(
            onPressed: _handleSave,
            child: Text(
              'Save',
              style: AppTextStyles.body.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Formatting Toolbar ────────────────────────────────────────────────────
  Widget _buildFormattingToolbar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _buildFontSizeControl(),
            const SizedBox(width: 10),
            // Vertical divider
            Container(width: 1, height: 28, color: context.colors.border),
            const SizedBox(width: 10),
            ..._buildColorPresets(),
            const SizedBox(width: 10),
            // Vertical divider
            Container(width: 1, height: 28, color: context.colors.border),
            const SizedBox(width: 10),
            _buildKeyboardDismissButton(),
          ],
        ),
      ),
    );
  }

  // ── Font Size Control ─────────────────────────────────────────────────────
  /// Circular rose-outlined –/+ buttons around a centered font size number.
  Widget _buildFontSizeControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minus button
        _circleButton(
          icon: AppIcons.remove,
          onTap: _fontSize > _minFont
              ? () => setState(
                    () => _fontSize = (_fontSize - _fontStep).clamp(
                      _minFont,
                      _maxFont,
                    ),
                  )
              : null,
        ),
        // Current size
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            _fontSize.toInt().toString(),
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: AppFontSizes.caption,
            ),
          ),
        ),
        // Plus button
        _circleButton(
          icon: AppIcons.add,
          onTap: _fontSize < _maxFont
              ? () => setState(
                    () => _fontSize = (_fontSize + _fontStep).clamp(
                      _minFont,
                      _maxFont,
                    ),
                  )
              : null,
        ),
      ],
    );
  }

  /// Small circular button with a rose outline.
  Widget _circleButton({required IconData icon, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.6)
                : context.colors.border,
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.primary : context.colors.textDisabled,
        ),
      ),
    );
  }

  // ── Color Presets ─────────────────────────────────────────────────────────
  /// Builds the list of highlight-preset chips (excluding 'none').
  ///
  /// A chip is "active" when:
  ///  • It matches the block highlight at the cursor/selection position, OR
  ///  • It matches `_activeHighlight` when no cursor is in the text.
  List<Widget> _buildColorPresets() {
    // Determine which highlight is relevant at the current cursor position
    LyricsHighlight? cursorHighlight;
    final sel = _textController.selection;
    if (sel.isValid && sel.baseOffset >= 0) {
      final idx = _blockIndexAtOffset(sel.start);
      cursorHighlight = _blockHighlights[idx];
    }
    final effectiveHighlight = cursorHighlight ?? _activeHighlight;

    final presets = LyricsHighlight.values.where(
      (h) => h != LyricsHighlight.none,
    );
    return presets.map((h) {
      final isActive = effectiveHighlight == h;
      final accentColor = Color(h.accentColorValue);

      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => _onHighlightTapped(h),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? accentColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Spacing.chipRadius),
              border: Border.all(
                color: isActive ? accentColor : context.colors.border,
                width: isActive ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Colored dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  h.label,
                  style: AppTextStyles.footnote.copyWith(
                    color:
                        isActive ? accentColor : context.colors.textSecondary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    fontSize: AppFontSizes.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  // ── Keyboard Dismiss Button ───────────────────────────────────────────────
  /// Small button to dismiss the keyboard and see more lyrics content.
  Widget _buildKeyboardDismissButton() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_hide,
              size: 20,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              'Done',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Text Area ─────────────────────────────────────────────────────────────
  Widget _buildTextArea() {
    return Padding(
      padding: const EdgeInsets.all(Spacing.pagePadding),
      child: TextField(
        controller: _textController,
        focusNode: _focusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: _fontSize,
          fontWeight: FontWeight.w700,
          height: 1.6,
        ),
        decoration: InputDecoration(
          hintText:
              'Paste or type your lyrics here…\n\nSeparate sections with a blank line.',
          hintStyle: TextStyle(
            color: context.colors.textMuted,
            fontSize: _fontSize,
            height: 1.6,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        cursorColor: AppColors.primary,
      ),
    );
  }
}

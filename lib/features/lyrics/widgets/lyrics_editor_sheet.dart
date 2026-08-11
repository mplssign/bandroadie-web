import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

// ============================================================================
// LYRICS EDITOR BOTTOM SHEET
//
// Full-screen drawer for editing song lyrics in plain-text ChordPro format.
// • Plain-text editor (no formatting toolbar)
// • ChordPro syntax help button
// • Add chords using [ChordName] syntax, e.g., [G]Hello [C]world
// ============================================================================

/// Shows a full-screen lyrics editor and returns the plain-text lyrics on save.
Future<String?> showLyricsEditor(
  BuildContext context, {
  String? initialData,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LyricsEditorSheet(initialData: initialData),
  );
}

class _LyricsEditorSheet extends StatefulWidget {
  final String? initialData;
  const _LyricsEditorSheet({this.initialData});

  @override
  State<_LyricsEditorSheet> createState() => _LyricsEditorSheetState();
}

class _LyricsEditorSheetState extends State<_LyricsEditorSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;

  late final TextEditingController _textController;
  late final FocusNode _focusNode;

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

    _textController = TextEditingController(text: widget.initialData ?? '');
    _focusNode = FocusNode();
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _handleSave() {
    final text = _textController.text.trim();
    Navigator.of(context).pop(text.isEmpty ? null : text);
  }

  void _showChordProHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ChordPro Format'),
        content: const Text(
          'Add chords by typing [Am] before a word.\n\n'
          'Example:\n'
          '[G]Hello [C]world\n\n'
          'Chords will appear above the lyrics when viewing.',
        ),
        actions: [
          TextButton(
            child: const Text('Got it'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _buildHeader(),
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
          const SizedBox(width: 8),
          // Help icon
          IconButton(
            icon: const Icon(Icons.info_outline),
            iconSize: 20,
            color: context.colors.textSecondary,
            onPressed: _showChordProHelp,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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
          fontSize: 18,
          fontWeight: FontWeight.w500,
          height: 1.6,
        ),
        decoration: InputDecoration(
          hintText:
              'Paste or type your lyrics here…\n\nAdd chords using [Am] before a word.',
          hintStyle: TextStyle(
            color: context.colors.textMuted,
            fontSize: 18,
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

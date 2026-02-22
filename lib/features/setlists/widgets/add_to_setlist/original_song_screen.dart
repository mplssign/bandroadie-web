import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';

// ============================================================================
// ORIGINAL SONG SCREEN
// Screen 2 of the Add to Setlist flow — manual entry for original songs.
//
// Each entry group has:
//   1. Song Name (required)
//   2. Artist / Band Name (required, auto-filled with active band name)
//
// Features:
//   - "+ Add another" to add more groups with slide+fade animation
//   - Trash icon to remove groups
//   - Inline validation (shake + red highlight)
//   - "Add song" / "Add songs" submit button
//   - Loading state with spinner
// ============================================================================

/// Represents a single song entry in the form.
class _SongEntry {
  final TextEditingController titleController;
  final TextEditingController artistController;
  final FocusNode titleFocusNode;
  final FocusNode artistFocusNode;
  final GlobalKey<_SongEntryGroupState> groupKey;
  bool hasValidationError;

  _SongEntry({required String defaultArtist})
      : titleController = TextEditingController(),
        artistController = TextEditingController(text: defaultArtist),
        titleFocusNode = FocusNode(),
        artistFocusNode = FocusNode(),
        groupKey = GlobalKey<_SongEntryGroupState>(),
        hasValidationError = false;

  void dispose() {
    titleController.dispose();
    artistController.dispose();
    titleFocusNode.dispose();
    artistFocusNode.dispose();
  }

  bool get isValid =>
      titleController.text.trim().isNotEmpty &&
      artistController.text.trim().isNotEmpty;
}

/// Callback when original songs are submitted.
/// [songs] is a list of (title, artist) pairs.
typedef OnOriginalSongsSubmitted = Future<int> Function(
  List<({String title, String artist})> songs,
);

class OriginalSongScreen extends StatefulWidget {
  final String defaultArtist;
  final OnOriginalSongsSubmitted onSubmit;
  final VoidCallback onBack;
  final VoidCallback? onClose;

  const OriginalSongScreen({
    super.key,
    required this.defaultArtist,
    required this.onSubmit,
    required this.onBack,
    this.onClose,
  });

  @override
  State<OriginalSongScreen> createState() => _OriginalSongScreenState();
}

class _OriginalSongScreenState extends State<OriginalSongScreen>
    with SingleTickerProviderStateMixin {
  final List<_SongEntry> _entries = [];
  bool _isSubmitting = false;

  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Start with one entry
    _entries.add(_SongEntry(defaultArtist: widget.defaultArtist));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
        // Focus the first title field
        _entries.first.titleFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _addEntry() {
    setState(() {
      _entries.add(_SongEntry(defaultArtist: widget.defaultArtist));
    });
    // Focus the new title field after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entries.isNotEmpty) {
        _entries.last.titleFocusNode.requestFocus();
      }
    });
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() {
      _entries[index].dispose();
      _entries.removeAt(index);
    });
  }

  bool _validateAll() {
    var allValid = true;
    for (final entry in _entries) {
      final titleEmpty = entry.titleController.text.trim().isEmpty;
      final artistEmpty = entry.artistController.text.trim().isEmpty;
      if (titleEmpty || artistEmpty) {
        entry.hasValidationError = true;
        entry.groupKey.currentState?.shake();
        allValid = false;
      } else {
        entry.hasValidationError = false;
      }
    }
    setState(() {});
    return allValid;
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    if (!_validateAll()) return;

    setState(() {
      _isSubmitting = true;
    });

    final songs = _entries
        .map(
          (e) => (
            title: e.titleController.text.trim(),
            artist: e.artistController.text.trim(),
          ),
        )
        .toList();

    final addedCount = await widget.onSubmit(songs);

    if (!mounted) return;

    if (addedCount > 0) {
      // Close the entire overlay
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  String get _submitLabel {
    final count = _entries.length;
    return count == 1 ? 'Add song' : 'Add songs';
  }

  bool get _hasValidEntry => _entries.any((e) => e.isValid);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Scrollable form area
        Expanded(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.pagePadding,
                Spacing.space8,
                Spacing.pagePadding,
                Spacing.space24,
              ),
              children: [
                // Subtitle
                FadeTransition(
                  opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _entranceController,
                      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.space24),
                    child: Text(
                      'Add original songs or hard to find covers',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),

                // Song entry groups
                ..._buildEntryGroups(),

                // + Add another button
                FadeTransition(
                  opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _entranceController,
                      curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: Spacing.space8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: _isSubmitting ? null : _addEntry,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.space8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                size: 20,
                                color: _isSubmitting
                                    ? AppColors.textMuted
                                    : AppColors.accent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Add another',
                                style: AppTextStyles.body.copyWith(
                                  color: _isSubmitting
                                      ? AppColors.textMuted
                                      : AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom action button
        _buildSubmitButton(),
      ],
    );
  }

  List<Widget> _buildEntryGroups() {
    final groups = <Widget>[];
    for (var i = 0; i < _entries.length; i++) {
      groups.add(
        _AnimatedEntryWrapper(
          key: ValueKey('entry-$i-${_entries[i].hashCode}'),
          child: _SongEntryGroup(
            key: _entries[i].groupKey,
            entry: _entries[i],
            index: i,
            showRemove: _entries.length > 1,
            isSubmitting: _isSubmitting,
            onRemove: () => _removeEntry(i),
            onFieldChanged: () => setState(() {}),
          ),
        ),
      );
    }
    return groups;
  }

  Widget _buildSubmitButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space12,
        Spacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom + Spacing.space16,
      ),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        border: Border(
          top: BorderSide(
            color: AppColors.borderMuted.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: GestureDetector(
                onTap: _isSubmitting || !_hasValidEntry ? null : _handleSubmit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _isSubmitting || !_hasValidEntry
                        ? AppColors.accent.withValues(alpha: 0.4)
                        : AppColors.accent,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  ),
                  alignment: Alignment.center,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _submitLabel,
                          style: AppTextStyles.button.copyWith(
                            color:
                                _hasValidEntry ? Colors.white : Colors.white60,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: widget.onClose ?? () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ANIMATED ENTRY WRAPPER
// Wraps each song entry group with insert/remove animations.
// ============================================================================

class _AnimatedEntryWrapper extends StatefulWidget {
  final Widget child;

  const _AnimatedEntryWrapper({super.key, required this.child});

  @override
  State<_AnimatedEntryWrapper> createState() => _AnimatedEntryWrapperState();
}

class _AnimatedEntryWrapperState extends State<_AnimatedEntryWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

// ============================================================================
// SONG ENTRY GROUP
// A single card with Song Name + Artist fields and optional remove button.
// Supports shake animation for validation errors.
// ============================================================================

class _SongEntryGroup extends StatefulWidget {
  final _SongEntry entry;
  final int index;
  final bool showRemove;
  final bool isSubmitting;
  final VoidCallback onRemove;
  final VoidCallback? onFieldChanged;

  const _SongEntryGroup({
    super.key,
    required this.entry,
    required this.index,
    required this.showRemove,
    required this.isSubmitting,
    required this.onRemove,
    this.onFieldChanged,
  });

  @override
  State<_SongEntryGroup> createState() => _SongEntryGroupState();
}

class _SongEntryGroupState extends State<_SongEntryGroup>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  /// Trigger shake animation (called externally via GlobalKey).
  void shake() {
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.entry.hasValidationError;
    final titleEmpty = widget.entry.titleController.text.trim().isEmpty;
    final artistEmpty = widget.entry.artistController.text.trim().isEmpty;

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.space16),
        padding: const EdgeInsets.all(Spacing.space16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          border: Border.all(
            color: hasError
                ? AppColors.accent.withValues(alpha: 0.6)
                : AppColors.borderMuted,
            width: hasError ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: song number + remove
            Row(
              children: [
                Text(
                  'Song ${widget.index + 1}',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (widget.showRemove && !widget.isSubmitting)
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: Spacing.space12),

            // Song Name field
            _buildField(
              label: 'Song Name',
              controller: widget.entry.titleController,
              focusNode: widget.entry.titleFocusNode,
              hasError: hasError && titleEmpty,
              enabled: !widget.isSubmitting,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => widget.entry.artistFocusNode.requestFocus(),
              onChanged: (_) {
                if (widget.entry.hasValidationError) {
                  setState(() {
                    widget.entry.hasValidationError = false;
                  });
                }
                widget.onFieldChanged?.call();
              },
            ),

            const SizedBox(height: Spacing.space12),

            // Artist field
            _buildField(
              label: 'Artist / Band Name',
              controller: widget.entry.artistController,
              focusNode: widget.entry.artistFocusNode,
              hasError: hasError && artistEmpty,
              enabled: !widget.isSubmitting,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (widget.entry.hasValidationError) {
                  setState(() {
                    widget.entry.hasValidationError = false;
                  });
                }
                widget.onFieldChanged?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool hasError,
    required bool enabled,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: hasError ? AppColors.accent : AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            style: AppTextStyles.body.copyWith(
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: label == 'Song Name'
                  ? 'Enter song name'
                  : 'Enter artist name',
              hintStyle: AppTextStyles.body.copyWith(
                color: AppColors.textMuted,
                fontSize: 15,
              ),
              filled: true,
              fillColor: AppColors.scaffoldBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  SongCardLayout.inputBorderRadius,
                ),
                borderSide: BorderSide(
                  color: hasError
                      ? AppColors.accent
                      : SongCardLayout.inputBorderColor,
                  width: hasError ? 1.5 : SongCardLayout.inputBorderWidth,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  SongCardLayout.inputBorderRadius,
                ),
                borderSide: BorderSide(
                  color: hasError
                      ? AppColors.accent
                      : SongCardLayout.inputBorderColor,
                  width: hasError ? 1.5 : SongCardLayout.inputBorderWidth,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  SongCardLayout.inputBorderRadius,
                ),
                borderSide: BorderSide(
                  color: hasError ? AppColors.accent : AppColors.accent,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

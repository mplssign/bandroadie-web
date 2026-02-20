import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/utils/snackbar_helper.dart';
import '../../setlist_repository.dart';

// ============================================================================
// ORIGINAL SONG SCREEN
// Manual creation of original songs written by the band.
//
// FEATURES:
// - Song Name + Artist/Band Name fields per entry
// - Artist auto-filled with active band name
// - "+ Add another" to add multiple songs
// - Remove (trash) per entry group
// - Inline validation (shake + red highlight)
// - Reuses existing upsertExternalSong + addSong logic
// ============================================================================

class OriginalSongScreen extends ConsumerStatefulWidget {
  final String bandId;
  final String setlistId;
  final String bandName;
  final Future<AddSongResult> Function(
    String songId,
    String title,
    String artist,
  )
  onSongAdded;
  final VoidCallback onClose;

  const OriginalSongScreen({
    super.key,
    required this.bandId,
    required this.setlistId,
    required this.bandName,
    required this.onSongAdded,
    required this.onClose,
  });

  @override
  ConsumerState<OriginalSongScreen> createState() => _OriginalSongScreenState();
}

/// Data for a single original song entry
class _SongEntry {
  final TextEditingController titleController;
  final TextEditingController artistController;
  final FocusNode titleFocus;
  final FocusNode artistFocus;
  final GlobalKey<_SongEntryFieldsState> fieldKey;
  bool showTitleError;
  bool showArtistError;

  _SongEntry({required String bandName})
    : titleController = TextEditingController(),
      artistController = TextEditingController(text: bandName),
      titleFocus = FocusNode(),
      artistFocus = FocusNode(),
      fieldKey = GlobalKey<_SongEntryFieldsState>(),
      showTitleError = false,
      showArtistError = false;

  void dispose() {
    titleController.dispose();
    artistController.dispose();
    titleFocus.dispose();
    artistFocus.dispose();
  }

  bool get isValid =>
      titleController.text.trim().isNotEmpty &&
      artistController.text.trim().isNotEmpty;
}

class _OriginalSongScreenState extends ConsumerState<OriginalSongScreen>
    with TickerProviderStateMixin {
  final List<_SongEntry> _entries = [];
  bool _isSubmitting = false;
  Timer? _loadingDelayTimer;
  bool _showSpinner = false;

  // Entrance animations
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    // Start with one entry
    _entries.add(_SongEntry(bandName: widget.bandName));

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward();
      // Focus the first title field
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _entries.isNotEmpty) {
          _entries[0].titleFocus.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    _entranceController.dispose();
    _loadingDelayTimer?.cancel();
    super.dispose();
  }

  void _addEntry() {
    setState(() {
      _entries.add(_SongEntry(bandName: widget.bandName));
    });
    // Focus the new title field after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entries.isNotEmpty) {
        _entries.last.titleFocus.requestFocus();
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

  bool _validate() {
    bool allValid = true;
    for (final entry in _entries) {
      final titleEmpty = entry.titleController.text.trim().isEmpty;
      final artistEmpty = entry.artistController.text.trim().isEmpty;

      setState(() {
        entry.showTitleError = titleEmpty;
        entry.showArtistError = artistEmpty;
      });

      if (titleEmpty || artistEmpty) {
        allValid = false;
        // Trigger shake animation
        entry.fieldKey.currentState?.shake();
      }
    }
    return allValid;
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    if (!_validate()) return;

    setState(() {
      _isSubmitting = true;
      _showSpinner = false;
    });

    // Show spinner after 1 second delay
    _loadingDelayTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _isSubmitting) {
        setState(() => _showSpinner = true);
      }
    });

    try {
      final repo = ref.read(setlistRepositoryProvider);
      int successCount = 0;

      for (final entry in _entries) {
        final title = entry.titleController.text.trim();
        final artist = entry.artistController.text.trim();

        // Upsert to catalog (reusing existing logic)
        final songId = await repo.upsertExternalSong(
          bandId: widget.bandId,
          title: title,
          artist: artist,
        );

        if (songId == null) continue;

        // Add to setlist
        final result = await widget.onSongAdded(songId, title, artist);
        if (result.success) successCount++;
      }

      _loadingDelayTimer?.cancel();

      if (mounted) {
        if (successCount > 0) {
          final word = successCount == 1 ? 'song' : 'songs';
          showAppSnackBar(
            context,
            message: 'Added $successCount $word to setlist',
          );
          widget.onClose();
        } else {
          setState(() {
            _isSubmitting = false;
            _showSpinner = false;
          });
          showErrorSnackBar(
            context,
            message: 'Failed to add songs. Please try again.',
          );
        }
      }
    } catch (e) {
      _loadingDelayTimer?.cancel();
      debugPrint('[OriginalSong] Submit error: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _showSpinner = false;
        });
        showErrorSnackBar(context, message: 'Failed to add songs: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final validEntries = _entries.where((e) => e.isValid).length;
    final hasValidEntries = validEntries > 0;
    final buttonLabel = validEntries <= 1
        ? 'Add song'
        : 'Add $validEntries songs';

    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
      ),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  Spacing.space16,
                  Spacing.space16,
                  Spacing.space16,
                  keyboardHeight > 0 ? keyboardHeight : Spacing.space16,
                ),
                physics: const BouncingScrollPhysics(),
                children: [
                  // Song entry groups
                  ...List.generate(_entries.length, (index) {
                    return _SongEntryFields(
                      key: _entries[index].fieldKey,
                      entry: _entries[index],
                      index: index,
                      canRemove: _entries.length > 1,
                      onRemove: () => _removeEntry(index),
                      onChanged: () => setState(() {}),
                    );
                  }),

                  // "+ Add another" button
                  const SizedBox(height: Spacing.space8),
                  _AddAnotherButton(onTap: _addEntry),
                ],
              ),
            ),
          ),

          // Bottom action bar
          Container(
            padding: const EdgeInsets.all(Spacing.space16),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.borderMuted, width: 1),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                _SubmitButton(
                  label: buttonLabel,
                  isEnabled: hasValidEntries && !_isSubmitting,
                  isLoading: _showSpinner,
                  onTap: _handleSubmit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SONG ENTRY FIELDS
// A single editable song entry group with title + artist fields.
// ============================================================================

class _SongEntryFields extends StatefulWidget {
  final _SongEntry entry;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _SongEntryFields({
    super.key,
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_SongEntryFields> createState() => _SongEntryFieldsState();
}

class _SongEntryFieldsState extends State<_SongEntryFields>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Expansion animation
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
        );

    // Animate expansion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isExpanded = true);
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void shake() {
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: _isExpanded ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: AnimatedBuilder(
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
              border: Border.all(color: AppColors.borderMuted, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with index and remove button
                Row(
                  children: [
                    Text(
                      'Song ${widget.index + 1}',
                      style: AppTextStyles.footnote.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (widget.canRemove)
                      GestureDetector(
                        onTap: widget.onRemove,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: Spacing.space12),

                // Song Name
                _InputField(
                  controller: widget.entry.titleController,
                  focusNode: widget.entry.titleFocus,
                  label: 'Song Name',
                  hint: 'Enter song name',
                  showError: widget.entry.showTitleError,
                  errorText: 'Song name is required',
                  onChanged: (_) {
                    if (widget.entry.showTitleError) {
                      setState(() => widget.entry.showTitleError = false);
                    }
                    widget.onChanged();
                  },
                ),

                const SizedBox(height: Spacing.space12),

                // Artist / Band Name
                _InputField(
                  controller: widget.entry.artistController,
                  focusNode: widget.entry.artistFocus,
                  label: 'Artist / Band Name',
                  hint: 'Enter artist name',
                  showError: widget.entry.showArtistError,
                  errorText: 'Artist is required',
                  onChanged: (_) {
                    if (widget.entry.showArtistError) {
                      setState(() => widget.entry.showArtistError = false);
                    }
                    widget.onChanged();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// INPUT FIELD
// Styled text field with error highlighting.
// ============================================================================

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final bool showError;
  final String errorText;
  final ValueChanged<String> onChanged;

  const _InputField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.showError,
    required this.errorText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: showError ? AppColors.error : AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(
              color: showError ? AppColors.error : AppColors.borderMuted,
              width: showError ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
        // Error text
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: showError
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    errorText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ============================================================================
// ADD ANOTHER BUTTON
// ============================================================================

class _AddAnotherButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddAnotherButton({required this.onTap});

  @override
  State<_AddAnotherButton> createState() => _AddAnotherButtonState();
}

class _AddAnotherButtonState extends State<_AddAnotherButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: Spacing.space14),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.5),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'Add another',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.accent,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SUBMIT BUTTON
// ============================================================================

class _SubmitButton extends StatefulWidget {
  final String label;
  final bool isEnabled;
  final bool isLoading;
  final VoidCallback onTap;

  const _SubmitButton({
    required this.label,
    required this.isEnabled,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isEnabled && !widget.isLoading;

    return GestureDetector(
      onTapDown: isActive ? (_) => _pressController.forward() : null,
      onTapUp: isActive ? (_) => _pressController.reverse() : null,
      onTapCancel: isActive ? () => _pressController.reverse() : null,
      onTap: isActive ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accent
                : AppColors.accent.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

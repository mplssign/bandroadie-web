import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../models/bulk_song_row.dart';
import '../services/bulk_song_parser.dart';
import '../setlist_repository.dart';
import '../tuning/tuning_helpers.dart';

// ============================================================================
// BULK ADD SONGS OVERLAY
// Full-screen modal overlay for bulk-pasting songs from a spreadsheet.
//
// FEATURES:
// - Multi-line input area for pasting spreadsheet data
// - Live parsed row preview with validation status
// - Error badges for invalid rows
// - Add Songs button (disabled until valid rows exist)
// - Matches Song Lookup overlay style
//
// DESIGN: Matches existing overlay pattern + BandRoadie dark theme
// ============================================================================

/// Shows the bulk add songs overlay as a full-screen modal.
///
/// [bandId] - The band to add songs to
/// [setlistId] - The setlist to add songs to
/// [onComplete] - Callback when songs are successfully added
///   - addedCount: number of songs added
///   - setlistSongIds: IDs for undo support (only target setlist, not Catalog)
Future<void> showBulkAddSongsOverlay({
  required BuildContext context,
  required String bandId,
  required String setlistId,
  required void Function(int addedCount, List<String> setlistSongIds)
  onComplete,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return BulkAddSongsOverlay(
        bandId: bandId,
        setlistId: setlistId,
        onComplete: onComplete,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInQuart,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class BulkAddSongsOverlay extends ConsumerStatefulWidget {
  final String bandId;
  final String setlistId;
  final void Function(int addedCount, List<String> setlistSongIds) onComplete;

  const BulkAddSongsOverlay({
    super.key,
    required this.bandId,
    required this.setlistId,
    required this.onComplete,
  });

  @override
  ConsumerState<BulkAddSongsOverlay> createState() =>
      _BulkAddSongsOverlayState();
}

/// Maximum number of rows allowed in a single paste
const int _kMaxRows = 500;

class _BulkAddSongsOverlayState extends ConsumerState<BulkAddSongsOverlay>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  BulkSongParseResult _parseResult = const BulkSongParseResult(
    allRows: [],
    validRows: [],
    invalidRows: [],
    duplicatesRemoved: 0,
  );

  bool _isSubmitting = false;
  bool _rowLimitExceeded = false;
  Timer? _debounceTimer;

  // Animation for preview rows
  late AnimationController _previewAnimController;

  @override
  void initState() {
    super.initState();
    _previewAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Auto-focus input field after dialog animates in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _inputFocus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    _previewAnimController.dispose();
    super.dispose();
  }

  void _onInputChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _parseInput(value);
    });
  }

  Future<void> _parseInput(String input) async {
    // Count lines first to check limit (quick check)
    final lineCount = input
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;
    final exceedsLimit = lineCount > _kMaxRows;

    // For large pastes, parse async to avoid blocking UI
    BulkSongParseResult result;
    if (lineCount > 100) {
      // Parse asynchronously for large inputs
      result = await Future.microtask(
        () => BulkSongParser.instance.parse(input, maxRows: _kMaxRows),
      );
    } else {
      result = BulkSongParser.instance.parse(input, maxRows: _kMaxRows);
    }

    debugPrint(
      '[BulkAddOverlay] Parsed ${result.validRows.length} valid, ${result.invalidRows.length} invalid rows',
    );

    if (!mounted) return;

    setState(() {
      _parseResult = result;
      _rowLimitExceeded = exceedsLimit;
    });

    // Animate preview rows (limit animation to first 50 for performance)
    _previewAnimController.reset();
    _previewAnimController.forward();
  }

  Future<void> _handleAddSongs() async {
    if (_isSubmitting || !_parseResult.hasValidRows) return;

    debugPrint('[BulkAddOverlay] Starting add songs...');
    debugPrint('[BulkAddOverlay] bandId: ${widget.bandId}');
    debugPrint('[BulkAddOverlay] setlistId: ${widget.setlistId}');
    debugPrint(
      '[BulkAddOverlay] validRows count: ${_parseResult.validRows.length}',
    );

    setState(() {
      _isSubmitting = true;
    });

    try {
      final repository = ref.read(setlistRepositoryProvider);
      debugPrint('[BulkAddOverlay] Calling repository.bulkAddSongs...');
      final result = await repository.bulkAddSongs(
        bandId: widget.bandId,
        setlistId: widget.setlistId,
        rows: _parseResult.validRows,
      );

      debugPrint(
        '[BulkAddOverlay] Result: addedCount=${result.addedCount}, setlistSongIds=${result.setlistSongIds.length}',
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onComplete(result.addedCount, result.setlistSongIds);
      }
    } catch (e, stack) {
      debugPrint('[BulkAddOverlay] Error: $e');
      debugPrint('[BulkAddOverlay] Stack: $stack');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        String errorMessage = 'Failed to add songs.';
        if (e is SetlistQueryError) {
          errorMessage = 'Failed to add songs: ${e.message}';
        }

        showErrorSnackBar(context, message: errorMessage);
      }
    }
  }

  /// Dismiss the keyboard
  void _dismissKeyboard() {
    _inputFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // Get keyboard height to add bottom padding for scrolling
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        // Don't apply bottom safe area when keyboard is showing
        bottom: keyboardHeight == 0,
        child: Container(
          margin: EdgeInsets.fromLTRB(
            Spacing.space16,
            Spacing.space16,
            Spacing.space16,
            keyboardHeight > 0 ? 0 : Spacing.space16,
          ),
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: AppColors.borderMuted, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBody()),
                // Keyboard toolbar when keyboard is showing
                if (keyboardHeight > 0) _buildKeyboardToolbar(),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderMuted, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.arrow_back_ios_rounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          const SizedBox(width: Spacing.space8),

          // Title
          Expanded(
            child: Text(
              'Bulk Add Songs',
              style: AppTextStyles.title3.copyWith(fontSize: 18),
            ),
          ),

          // Close button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.close_rounded,
                size: 24,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Keyboard toolbar with a Done button to dismiss keyboard
  Widget _buildKeyboardToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border: Border(top: BorderSide(color: AppColors.borderMuted, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _dismissKeyboard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: 14,
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

  Widget _buildBody() {
    return GestureDetector(
      // Dismiss keyboard when tapping outside the text field
      onTap: _dismissKeyboard,
      child: SingleChildScrollView(
        // Allow scrolling even when content fits, so user can scroll to Update button
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(Spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Copy/Paste section header
            Text(
              'COPY/PASTE:',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: Spacing.space4),

            // Copy/Paste instructions
            Text(
              'The columns in your spreadsheet should be in this order:',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),

            Text(
              'ARTIST, SONG (Optional: BPM, TUNING)',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: Spacing.space12),

            // Manual entry section header
            Text(
              'MANUALLY ENTER:',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: Spacing.space4),

            // Manual entry instructions
            Text(
              'Enter song info by typing ARTIST, SONG, BPM, TUNING (separated by commas)',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: Spacing.space16),

            // Row limit error
            if (_rowLimitExceeded)
              Container(
                margin: const EdgeInsets.only(bottom: Spacing.space12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  border: Border.all(color: AppColors.error, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Maximum $_kMaxRows rows allowed. Only the first $_kMaxRows rows will be processed.',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Input area
            _buildInputArea(),

            const SizedBox(height: Spacing.space20),

            // Preview section
            if (_parseResult.totalRows > 0) ...[
              _buildPreviewHeader(),
              const SizedBox(height: Spacing.space12),
              _buildPreviewList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: AppColors.borderMuted, width: 1),
      ),
      child: TextField(
        controller: _inputController,
        focusNode: _inputFocus,
        onChanged: _onInputChanged,
        textCapitalization: TextCapitalization.words,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        maxLines: null,
        minLines: 8,
        style: const TextStyle(
          fontSize: 14,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: 'Example: The Beatles, Come Together, 82, Standard',
          hintStyle: TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w400,
            color: AppColors.textMuted.withValues(alpha: 0.6),
            height: 1.5,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(Spacing.space16),
        ),
      ),
    );
  }

  Widget _buildPreviewHeader() {
    final validCount = _parseResult.validRows.length;
    final invalidCount = _parseResult.invalidRows.length;
    final dupeCount = _parseResult.duplicatesRemoved;
    final warningCount = _parseResult.validRows
        .where((r) => r.hasWarning)
        .length;

    // Build summary parts
    final parts = <String>[];

    // Primary count: songs detected
    final songLabel = validCount == 1 ? 'song' : 'songs';
    parts.add('$validCount $songLabel detected');

    // Error count
    if (invalidCount > 0) {
      final errorLabel = invalidCount == 1 ? 'error' : 'errors';
      parts.add('$invalidCount $errorLabel');
    }

    // Dupes removed
    if (dupeCount > 0) {
      final dupeLabel = dupeCount == 1 ? 'dupe removed' : 'dupes removed';
      parts.add('$dupeCount $dupeLabel');
    }

    // Warnings
    if (warningCount > 0) {
      final warnLabel = warningCount == 1 ? 'warning' : 'warnings';
      parts.add('$warningCount $warnLabel');
    }

    final summaryText = parts.join(' • ');

    // Determine color based on status
    final hasErrors = invalidCount > 0;
    final textColor = hasErrors ? AppColors.warning : AppColors.textSecondary;

    return Row(
      children: [
        // Status icon
        Icon(
          hasErrors ? Icons.warning_amber_rounded : Icons.check_circle_outline,
          size: 18,
          color: hasErrors ? AppColors.warning : AppColors.success,
        ),
        const SizedBox(width: 8),
        // Summary text
        Expanded(
          child: Text(
            summaryText,
            style: AppTextStyles.label.copyWith(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewList() {
    return AnimatedBuilder(
      animation: _previewAnimController,
      builder: (context, child) {
        return Column(
          children: List.generate(_parseResult.allRows.length, (index) {
            // Staggered animation
            final delay = (index * 0.05).clamp(0.0, 0.5);
            final itemAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: _previewAnimController,
                curve: Interval(
                  delay,
                  (delay + 0.3).clamp(0.0, 1.0),
                  curve: Curves.easeOut,
                ),
              ),
            );

            return FadeTransition(
              opacity: itemAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(itemAnimation),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.space8),
                  child: _buildPreviewRow(_parseResult.allRows[index]),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildPreviewRow(BulkSongRow row) {
    final isValid = row.isValid;
    final borderColor = isValid ? AppColors.borderMuted : AppColors.error;
    final bgColor = isValid
        ? const Color(0xFF2A2A2A)
        : AppColors.error.withValues(alpha: 0.1);

    // Get tuning badge color
    final tuningColor = row.tuning != null
        ? tuningBadgeColor(row.tuning)
        : const Color(0xFF2563EB);
    final tuningTextColor = tuningBadgeTextColor(tuningColor);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Song title (bold)
              Expanded(
                child: Text(
                  row.title.isEmpty ? '(No title)' : row.title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isValid ? AppColors.textPrimary : AppColors.error,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // BPM badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  row.formattedBpm,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Tuning badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tuningColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  row.formattedTuning,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tuningTextColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Artist row
          Row(
            children: [
              Expanded(
                child: Text(
                  row.artist.isEmpty ? '(No artist)' : row.artist,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Error badge (if invalid)
              if (!isValid && row.errorMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    row.errorMessage!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),

              // Warning badge (if valid but has warning)
              if (isValid && row.hasWarning && row.warningMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    row.warningMessage!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final hasValidRows = _parseResult.hasValidRows;
    final validCount = _parseResult.validRows.length;

    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderMuted, width: 1)),
      ),
      child: Row(
        children: [
          // Cancel link
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const Spacer(),

          // Add Songs button
          _AddSongsButton(
            onTap: hasValidRows && !_isSubmitting ? _handleAddSongs : null,
            isLoading: _isSubmitting,
            label: hasValidRows ? 'Add $validCount Songs' : 'Add Songs',
          ),
        ],
      ),
    );
  }
}

/// Add Songs button with scale animation
class _AddSongsButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isLoading;
  final String label;

  const _AddSongsButton({
    this.onTap,
    this.isLoading = false,
    required this.label,
  });

  @override
  State<_AddSongsButton> createState() => _AddSongsButtonState();
}

class _AddSongsButtonState extends State<_AddSongsButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null) _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) => _controller.reverse();
  void _handleTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null && !widget.isLoading;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isEnabled
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
                      color: isEnabled ? Colors.white : Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

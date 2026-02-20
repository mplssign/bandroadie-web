import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/utils/snackbar_helper.dart';
import '../../models/bulk_song_row.dart';
import '../../services/bulk_song_parser.dart';
import '../../setlist_repository.dart';

// ============================================================================
// BULK ENTRY SCREEN – TABLE-BASED
//
// Structured table with columns: Artist, Song, BPM, Tuning.
// Pasting from a spreadsheet distributes tab-separated values across
// columns and rows automatically.
//
// Reuses BulkSongParser for validation + SetlistRepository for persistence.
// ============================================================================

/// Maximum number of rows allowed in a single paste.
const int _kMaxBulkRows = 500;

/// Number of empty rows shown when the table first appears.
const int _kInitialRows = 1;

/// Minimum trailing empty rows kept at the bottom so the user always
/// has somewhere to type or paste.
const int _kMinTrailingEmpty = 1;

// ────────────────────────────────────────────────────────────────────────────
// EDITABLE ROW MODEL
// ────────────────────────────────────────────────────────────────────────────

/// Holds the controllers and focus nodes for one table row.
class _EditableRow {
  /// [0] = Artist, [1] = Song, [2] = BPM, [3] = Tuning
  final List<TextEditingController> controllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> focusNodes = List.generate(4, (_) => FocusNode());

  String get artist => controllers[0].text.trim();
  String get song => controllers[1].text.trim();
  String get bpm => controllers[2].text.trim();
  String get tuning => controllers[3].text.trim();

  bool get isEmpty =>
      artist.isEmpty && song.isEmpty && bpm.isEmpty && tuning.isEmpty;

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────
// BULK ENTRY SCREEN WIDGET
// ────────────────────────────────────────────────────────────────────────────

class BulkEntryScreen extends ConsumerStatefulWidget {
  final String bandId;
  final String setlistId;
  final void Function(int addedCount, List<String> setlistSongIds) onComplete;
  final VoidCallback onClose;

  const BulkEntryScreen({
    super.key,
    required this.bandId,
    required this.setlistId,
    required this.onComplete,
    required this.onClose,
  });

  @override
  ConsumerState<BulkEntryScreen> createState() => _BulkEntryScreenState();
}

class _BulkEntryScreenState extends ConsumerState<BulkEntryScreen>
    with SingleTickerProviderStateMixin {
  final List<_EditableRow> _rows = [];

  BulkSongParseResult _parseResult = const BulkSongParseResult(
    allRows: [],
    validRows: [],
    invalidRows: [],
    duplicatesRemoved: 0,
  );

  bool _isSubmitting = false;
  bool _rowLimitExceeded = false;
  Timer? _debounceTimer;

  // Entrance animation
  late AnimationController _entranceController;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _addEmptyRows(_kInitialRows);

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _headerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _rows.isNotEmpty) {
          _rows[0].focusNodes[0].requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (final row in _rows) {
      row.dispose();
    }
    _entranceController.dispose();
    super.dispose();
  }

  // ── Row management ────────────────────────────────────────────────────

  void _addEmptyRows(int count) {
    for (var i = 0; i < count; i++) {
      _rows.add(_EditableRow());
    }
  }

  /// Ensure at least [_kMinTrailingEmpty] empty rows at the bottom.
  void _ensureTrailingEmptyRows() {
    int emptyAtEnd = 0;
    for (int i = _rows.length - 1; i >= 0; i--) {
      if (_rows[i].isEmpty) {
        emptyAtEnd++;
      } else {
        break;
      }
    }
    if (emptyAtEnd < _kMinTrailingEmpty) {
      setState(() => _addEmptyRows(_kMinTrailingEmpty - emptyAtEnd));
    }
  }

  // ── Cell change / paste handling ──────────────────────────────────────

  void _onCellChanged(int rowIndex, int colIndex, String value) {
    // Tabs or newlines in a single-line field → spreadsheet paste.
    if (value.contains('\t') || value.contains('\n') || value.contains('\r')) {
      _handleBulkPaste(rowIndex, colIndex, value);
      return;
    }
    _scheduleParse();
    _ensureTrailingEmptyRows();
  }

  /// Distribute pasted spreadsheet data across the table starting at
  /// [startRow], [startCol].
  void _handleBulkPaste(int startRow, int startCol, String rawPaste) {
    // Clear the cell that absorbed the paste.
    _rows[startRow].controllers[startCol].text = '';

    // Normalise line endings.
    final text = rawPaste.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n');

    int currentRow = startRow;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (currentRow >= _kMaxBulkRows) break;

      // Parse columns – tabs first, then commas.
      List<String> cols;
      if (line.contains('\t')) {
        cols = line.split('\t');
      } else if (line.contains(',')) {
        cols = line.split(',');
      } else {
        cols = [line];
      }

      // Grow the table when needed.
      while (currentRow >= _rows.length) {
        _rows.add(_EditableRow());
      }

      // Fill columns starting from startCol.
      int col = startCol;
      for (final cell in cols) {
        if (col >= 4) break;
        _rows[currentRow].controllers[col].text = cell.trim();
        col++;
      }

      currentRow++;
    }

    setState(() {});
    _ensureTrailingEmptyRows();
    _scheduleParse();
  }

  /// Intercept paste from clipboard so multi-line / tab-delimited content
  /// is handled before the platform strips newlines for maxLines:1 fields.
  Future<void> _handlePaste(int rowIndex, int colIndex) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final text = data.text!;
    if (text.contains('\t') || text.contains('\n') || text.contains('\r')) {
      _handleBulkPaste(rowIndex, colIndex, text);
    } else {
      // Single value – let the default paste happen by inserting manually.
      final controller = _rows[rowIndex].controllers[colIndex];
      controller.text = text.trim();
      _scheduleParse();
      _ensureTrailingEmptyRows();
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────

  void _scheduleParse() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), _parseFromTable);
  }

  /// Re-serialise table rows as tab-delimited text and feed the existing
  /// [BulkSongParser] so all validation logic is reused.
  void _parseFromTable() {
    final buffer = StringBuffer();
    int nonEmptyCount = 0;

    for (final row in _rows) {
      if (row.isEmpty) continue;
      nonEmptyCount++;
      buffer.writeln('${row.artist}\t${row.song}\t${row.bpm}\t${row.tuning}');
    }

    final exceedsLimit = nonEmptyCount > _kMaxBulkRows;
    final result = BulkSongParser.instance.parse(
      buffer.toString(),
      maxRows: _kMaxBulkRows,
    );

    if (!mounted) return;
    setState(() {
      _parseResult = result;
      _rowLimitExceeded = exceedsLimit;
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────

  Future<void> _handleAddSongs() async {
    if (_isSubmitting || !_parseResult.hasValidRows) return;

    setState(() => _isSubmitting = true);

    try {
      final repository = ref.read(setlistRepositoryProvider);
      final result = await repository.bulkAddSongs(
        bandId: widget.bandId,
        setlistId: widget.setlistId,
        rows: _parseResult.validRows,
      );

      if (mounted) {
        widget.onClose();
        widget.onComplete(result.addedCount, result.setlistSongIds);
      }
    } catch (e, stack) {
      debugPrint('[BulkEntry] Error: $e');
      debugPrint('[BulkEntry] Stack: $stack');
      if (mounted) {
        setState(() => _isSubmitting = false);

        String errorMessage = 'Failed to add songs.';
        if (e is SetlistQueryError) {
          errorMessage = 'Failed to add songs: ${e.message}';
        }
        showErrorSnackBar(context, message: errorMessage);
      }
    }
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final hasValidRows = _parseResult.hasValidRows;
    final validCount = _parseResult.validRows.length;

    return Column(
      children: [
        // Helper text
        FadeTransition(
          opacity: _headerFade,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.space16,
              Spacing.space12,
              Spacing.space16,
              0,
            ),
            child: Text(
              'Paste from a spreadsheet or type directly into the table. '
              'Artist and Song are required; BPM and Tuning are optional.',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ),

        const SizedBox(height: Spacing.space12),

        // Row-limit warning
        _buildRowLimitWarning(),

        // ── Table ──────────────────────────────────────────────────
        Expanded(
          child: GestureDetector(
            onTap: _dismissKeyboard,
            child: _buildTable(keyboardHeight),
          ),
        ),

        // Summary strip
        if (_parseResult.totalRows > 0) _buildSummary(),

        // Keyboard dismiss bar
        if (keyboardHeight > 0) _buildKeyboardToolbar(),

        // Footer action bar
        _buildFooter(hasValidRows, validCount),
      ],
    );
  }

  // ── Row-limit warning ─────────────────────────────────────────────────

  Widget _buildRowLimitWarning() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _rowLimitExceeded
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
              child: Container(
                margin: const EdgeInsets.only(bottom: Spacing.space8),
                padding: const EdgeInsets.all(10),
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
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Max $_kMaxBulkRows rows. Only the first '
                        '$_kMaxBulkRows will be processed.',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────

  Widget _buildTable(double keyboardHeight) {
    return Column(
      children: [
        // Fixed column headers
        _buildHeaderRow(),
        const Divider(height: 1, color: AppColors.borderMuted, thickness: 1),

        // Scrollable data rows
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(
              bottom: keyboardHeight > 0 ? keyboardHeight : Spacing.space16,
            ),
            itemCount: _rows.length,
            itemBuilder: (context, index) => _buildDataRow(index),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow() {
    const headers = ['Artist', 'Song', 'BPM', 'Tuning'];

    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space12,
        vertical: Spacing.space8,
      ),
      child: Row(
        children: List.generate(headers.length, (i) {
          final label = Text(
            headers[i],
            style: AppTextStyles.label.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          );
          // Artist & Song flex, BPM & Tuning fixed width
          if (i < 2) return Expanded(flex: 3, child: label);
          if (i == 2) return SizedBox(width: 56, child: label);
          return SizedBox(width: 78, child: label);
        }),
      ),
    );
  }

  Widget _buildDataRow(int rowIndex) {
    final row = _rows[rowIndex];
    final isPopulated = row.artist.isNotEmpty || row.song.isNotEmpty;

    // Match against parsed results to show inline validation colour.
    BulkSongRow? parsedRow;
    if (isPopulated) {
      final key = '${row.artist.toLowerCase()}|${row.song.toLowerCase()}';
      for (final pr in _parseResult.allRows) {
        if (pr.dedupeKey == key) {
          parsedRow = pr;
          break;
        }
      }
    }

    final hasError = parsedRow != null && !parsedRow.isValid;
    final hasWarning = parsedRow != null && parsedRow.hasWarning;

    Color borderColor = const Color(0xFF222222);
    if (hasError) borderColor = AppColors.error.withValues(alpha: 0.4);
    if (hasWarning) borderColor = AppColors.warning.withValues(alpha: 0.4);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space12),
      child: Row(
        children: [
          _buildCell(rowIndex, 0, flex: 3),
          _buildCell(rowIndex, 1, flex: 3),
          _buildCell(rowIndex, 2, width: 56),
          _buildCell(rowIndex, 3, width: 78),
        ],
      ),
    );
  }

  Widget _buildCell(
    int rowIndex,
    int colIndex, {
    int flex = 0,
    double width = 0,
  }) {
    final controller = _rows[rowIndex].controllers[colIndex];
    final focusNode = _rows[rowIndex].focusNodes[colIndex];

    final cell = Container(
      decoration: BoxDecoration(
        border: Border(
          right: colIndex < 3
              ? const BorderSide(color: Color(0xFF222222), width: 1)
              : BorderSide.none,
        ),
      ),
      child: Actions(
        actions: <Type, Action<Intent>>{
          PasteTextIntent: CallbackAction<PasteTextIntent>(
            onInvoke: (_) {
              _handlePaste(rowIndex, colIndex);
              return null;
            },
          ),
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (v) => _onCellChanged(rowIndex, colIndex, v),
          textCapitalization: colIndex < 2
              ? TextCapitalization.words
              : TextCapitalization.none,
          keyboardType: colIndex == 2
              ? TextInputType.number
              : TextInputType.text,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          decoration: InputDecoration(
            hintText: _cellHint(colIndex),
            hintStyle: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted.withValues(alpha: 0.35),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 10,
            ),
            isDense: true,
          ),
        ),
      ),
    );

    if (flex > 0) return Expanded(flex: flex, child: cell);
    return SizedBox(width: width, child: cell);
  }

  String _cellHint(int col) {
    switch (col) {
      case 0:
        return 'Artist';
      case 1:
        return 'Song';
      case 2:
        return 'BPM';
      case 3:
        return 'Tuning';
      default:
        return '';
    }
  }

  // ── Summary strip ─────────────────────────────────────────────────────

  Widget _buildSummary() {
    final validCount = _parseResult.validRows.length;
    final invalidCount = _parseResult.invalidRows.length;
    final dupeCount = _parseResult.duplicatesRemoved;
    final warningCount = _parseResult.validRows
        .where((r) => r.hasWarning)
        .length;

    final parts = <String>[];
    parts.add('$validCount ${validCount == 1 ? 'song' : 'songs'} ready');
    if (invalidCount > 0) {
      parts.add('$invalidCount ${invalidCount == 1 ? 'error' : 'errors'}');
    }
    if (dupeCount > 0) {
      parts.add('$dupeCount ${dupeCount == 1 ? 'dupe' : 'dupes'} removed');
    }
    if (warningCount > 0) {
      parts.add('$warningCount ${warningCount == 1 ? 'warning' : 'warnings'}');
    }

    final hasErrors = invalidCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space8,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderMuted, width: 1)),
      ),
      child: Row(
        children: [
          Icon(
            hasErrors
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            size: 16,
            color: hasErrors ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: AppTextStyles.label.copyWith(
                color: hasErrors ? AppColors.warning : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Keyboard toolbar ──────────────────────────────────────────────────

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

  // ── Footer ────────────────────────────────────────────────────────────

  Widget _buildFooter(bool hasValidRows, int validCount) {
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
          _BulkSubmitButton(
            onTap: hasValidRows && !_isSubmitting ? _handleAddSongs : null,
            isLoading: _isSubmitting,
            label: hasValidRows ? 'Add $validCount songs' : 'Add songs',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BULK SUBMIT BUTTON
// ============================================================================

class _BulkSubmitButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isLoading;
  final String label;

  const _BulkSubmitButton({
    this.onTap,
    this.isLoading = false,
    required this.label,
  });

  @override
  State<_BulkSubmitButton> createState() => _BulkSubmitButtonState();
}

class _BulkSubmitButtonState extends State<_BulkSubmitButton>
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

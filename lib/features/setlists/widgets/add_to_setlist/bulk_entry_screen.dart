import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../models/bulk_song_row.dart';
import '../../services/bulk_song_parser.dart';

// ============================================================================
// BULK ENTRY SCREEN
// Screen 3 of the Add to Setlist flow — paste or type many songs at once.
//
// Structured editable table with columns: Artist | Song | BPM | Tuning
//
// Supports:
//   - Manual cell editing
//   - Spreadsheet paste (TSV) with automatic column mapping
//   - Dynamic row add / delete
//   - Validation: Artist + Song required, BPM numeric-only
//   - Submits rows as BulkSongRow objects (unchanged repository contract)
// ============================================================================

/// Callback when bulk songs are submitted.
typedef OnBulkSongsSubmitted = Future<BulkEntryResult> Function(
  List<BulkSongRow> validRows,
);

/// Lightweight result object returned by the submission callback.
class BulkEntryResult {
  final int addedCount;
  final List<String> setlistSongIds;

  const BulkEntryResult({
    required this.addedCount,
    required this.setlistSongIds,
  });
}

// -------------------------------------------------------
// Row data model (internal)
// -------------------------------------------------------

class _RowData {
  final TextEditingController artist;
  final TextEditingController song;
  final TextEditingController bpm;
  final TextEditingController tuning;
  final FocusNode artistFocus;
  final FocusNode songFocus;
  final FocusNode bpmFocus;
  final FocusNode tuningFocus;

  _RowData()
      : artist = TextEditingController(),
        song = TextEditingController(),
        bpm = TextEditingController(),
        tuning = TextEditingController(),
        artistFocus = FocusNode(),
        songFocus = FocusNode(),
        bpmFocus = FocusNode(),
        tuningFocus = FocusNode();

  void dispose() {
    artist.dispose();
    song.dispose();
    bpm.dispose();
    tuning.dispose();
    artistFocus.dispose();
    songFocus.dispose();
    bpmFocus.dispose();
    tuningFocus.dispose();
  }

  bool get isEmpty =>
      artist.text.trim().isEmpty &&
      song.text.trim().isEmpty &&
      bpm.text.trim().isEmpty &&
      tuning.text.trim().isEmpty;

  bool get hasRequiredFields =>
      artist.text.trim().isNotEmpty && song.text.trim().isNotEmpty;
}

// -------------------------------------------------------
// Constants
// -------------------------------------------------------

const int _kInitialRows = 5;
const int _kMaxRows = 500;

const int _kFlexArtist = 4;
const int _kFlexSong = 4;
const int _kFlexBpm = 2;
const int _kFlexTuning = 3;
const double _kDeleteWidth = 36;
const double _kCellHeight = 42;

// -------------------------------------------------------
// BulkEntryScreen widget
// -------------------------------------------------------

class BulkEntryScreen extends StatefulWidget {
  final OnBulkSongsSubmitted onSubmit;
  final VoidCallback onBack;
  final VoidCallback? onClose;

  const BulkEntryScreen({
    super.key,
    required this.onSubmit,
    required this.onBack,
    this.onClose,
  });

  @override
  State<BulkEntryScreen> createState() => _BulkEntryScreenState();
}

class _BulkEntryScreenState extends State<BulkEntryScreen> {
  final List<_RowData> _rows = [];
  bool _isSubmitting = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _csvController = TextEditingController();

  int _focusedRowIndex = 0;
  bool _isLoadingSongs = false;
  String? _ingestionSummary;

  // -------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _kInitialRows; i++) {
      _rows.add(_createRow());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _rows.isNotEmpty) {
          _rows[0].artistFocus.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _scrollController.dispose();
    _csvController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------
  // Row management
  // -------------------------------------------------------

  _RowData _createRow() {
    final row = _RowData();
    void trackFocus() {
      final idx = _rows.indexOf(row);
      if (idx >= 0) _focusedRowIndex = idx;
    }

    row.artistFocus.addListener(trackFocus);
    row.songFocus.addListener(trackFocus);
    row.bpmFocus.addListener(trackFocus);
    row.tuningFocus.addListener(trackFocus);
    return row;
  }

  void _addRow() {
    if (_rows.length >= _kMaxRows) return;
    setState(() {
      _rows.add(_createRow());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      if (_focusedRowIndex >= _rows.length) {
        _focusedRowIndex = _rows.length - 1;
      }
    });
  }

  // -------------------------------------------------------
  // CSV Ingestion
  // -------------------------------------------------------

  void _handleCsvIngestion() {
    if (_isLoadingSongs) return;

    final text = _csvController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoadingSongs = true);

    final parseResult = BulkSongParser.instance.parse(
      text,
      maxRows: _kMaxRows,
    );

    _populateTableFromParseResult(parseResult);

    // Clear the text field — table is now the source of truth.
    _csvController.clear();

    // Build advisory summary.
    final validCount = parseResult.validRows.length;
    final skippedCount = parseResult.invalidRows.length;
    final dupeCount = parseResult.duplicatesRemoved;
    final parts = <String>[];
    parts.add('Loaded $validCount song${validCount == 1 ? '' : 's'}');
    if (skippedCount > 0) {
      parts.add('$skippedCount skipped');
    }
    if (dupeCount > 0) {
      parts.add('$dupeCount duplicate${dupeCount == 1 ? '' : 's'} removed');
    }

    setState(() {
      _ingestionSummary = validCount > 0 ? parts.join(', ') : 'No valid songs found';
      _isLoadingSongs = false;
    });
  }

  void _populateTableFromParseResult(BulkSongParseResult parseResult) {
    // 1. Release focus before disposing rows.
    FocusManager.instance.primaryFocus?.unfocus();
    _focusedRowIndex = 0;

    // 2. Dispose all existing rows.
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();

    // 3. Create new rows from valid parsed data.
    for (final parsed in parseResult.validRows) {
      final row = _createRow();
      row.artist.text = parsed.artist;
      row.song.text = parsed.title;
      row.bpm.text = parsed.bpm?.toString() ?? '';
      row.tuning.text = parsed.tuningLabel ?? parsed.tuning ?? '';
      _rows.add(row);
    }

    // 4. Ensure at least one empty row.
    if (_rows.isEmpty) {
      _rows.add(_createRow());
    }
  }

  // -------------------------------------------------------
  // Submission
  // -------------------------------------------------------

  int get _validRowCount => _rows.where((r) => r.hasRequiredFields).length;

  Future<void> _handleSubmit() async {
    if (_isSubmitting || _validRowCount == 0) return;

    setState(() => _isSubmitting = true);

    try {
      final buffer = StringBuffer();
      for (final r in _rows) {
        if (r.isEmpty) continue;
        buffer.writeln(
          '${r.artist.text.trim()}\t'
          '${r.song.text.trim()}\t'
          '${r.bpm.text.trim()}\t'
          '${r.tuning.text.trim()}',
        );
      }

      final parseResult = BulkSongParser.instance.parse(
        buffer.toString(),
        maxRows: _kMaxRows,
      );

      if (!parseResult.hasValidRows) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }

      final result = await widget.onSubmit(parseResult.validRows);

      if (mounted && result.addedCount > 0) {
        Navigator.of(context).pop();
      } else if (mounted) {
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      debugPrint('[BulkEntryScreen] Submit error: $e');
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  // -------------------------------------------------------
  // Build
  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final validCount = _validRowCount;
    final hasValid = validCount > 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.space16,
            Spacing.space12,
            Spacing.space16,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _csvController,
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText:
                      'Paste CSV or tab-delimited data here…\n'
                      'Artist, Song, BPM, Tuning\n'
                      'e.g.: Aerosmith, Eat The Rich, 123, Standard',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.borderMuted,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.borderMuted,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.space8),
              SizedBox(
                height: 40,
                child: GestureDetector(
                  onTap: _isLoadingSongs ? null : _handleCsvIngestion,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isLoadingSongs
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.accent,
                      borderRadius:
                          BorderRadius.circular(Spacing.buttonRadius),
                    ),
                    alignment: Alignment.center,
                    child: _isLoadingSongs
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Load Songs',
                            style: AppTextStyles.button.copyWith(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ),
              if (_ingestionSummary != null) ...[
                const SizedBox(height: Spacing.space8),
                Text(
                  _ingestionSummary!,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.space12),
        _buildColumnHeaders(),
        Expanded(
          child: GestureDetector(
            onTap: _dismissKeyboard,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: Spacing.space8),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: _rows.length,
              itemBuilder: (context, index) => _buildRow(index),
            ),
          ),
        ),
        _buildAddRowButton(),
        if (keyboardHeight > 0) _buildKeyboardToolbar(),
        _buildFooter(hasValid, validCount),
      ],
    );
  }

  // -------------------------------------------------------
  // Column headers
  // -------------------------------------------------------

  Widget _buildColumnHeaders() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderMuted, width: 1),
        ),
      ),
      child: Row(
        children: [
          _headerCell('Artist', _kFlexArtist),
          _headerCell('Song', _kFlexSong),
          _headerCell('BPM', _kFlexBpm),
          _headerCell('Tuning', _kFlexTuning),
          const SizedBox(width: _kDeleteWidth),
        ],
      ),
    );
  }

  Widget _headerCell(String label, int flex) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // Table row
  // -------------------------------------------------------

  Widget _buildRow(int index) {
    final row = _rows[index];
    final isEven = index.isEven;

    return Container(
      decoration: BoxDecoration(
        color:
            isEven ? Colors.transparent : Colors.white.withValues(alpha: 0.02),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
      child: Row(
        children: [
          _tableCell(
            controller: row.artist,
            focusNode: row.artistFocus,
            flex: _kFlexArtist,
            hint: 'Artist',
            rowIndex: index,
            textCapitalization: TextCapitalization.words,
          ),
          _tableCell(
            controller: row.song,
            focusNode: row.songFocus,
            flex: _kFlexSong,
            hint: 'Song',
            rowIndex: index,
            textCapitalization: TextCapitalization.words,
          ),
          _tableCell(
            controller: row.bpm,
            focusNode: row.bpmFocus,
            flex: _kFlexBpm,
            hint: '-',
            rowIndex: index,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _tableCell(
            controller: row.tuning,
            focusNode: row.tuningFocus,
            flex: _kFlexTuning,
            hint: '-',
            rowIndex: index,
            textCapitalization: TextCapitalization.words,
          ),
          SizedBox(
            width: _kDeleteWidth,
            height: _kCellHeight,
            child: _rows.length > 1
                ? GestureDetector(
                    onTap: () => _removeRow(index),
                    behavior: HitTestBehavior.opaque,
                    child: const Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // Table cell
  // -------------------------------------------------------

  Widget _tableCell({
    required TextEditingController controller,
    required FocusNode focusNode,
    required int flex,
    required String hint,
    required int rowIndex,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Expanded(
      flex: flex,
      child: SizedBox(
        height: _kCellHeight,
        child: _TableTextField(
          controller: controller,
          focusNode: focusNode,
          hint: hint,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // Add row button
  // -------------------------------------------------------

  Widget _buildAddRowButton() {
    return GestureDetector(
      onTap: _addRow,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.borderMuted, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Add Row',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // Keyboard toolbar
  // -------------------------------------------------------

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

  // -------------------------------------------------------
  // Footer
  // -------------------------------------------------------

  String get _submitLabel {
    final count = _validRowCount;
    if (count == 0) return 'Add Songs';
    return count == 1 ? 'Add 1 Song' : 'Add $count Songs';
  }

  bool get _hasValidSongData => _rows.any((r) => r.hasRequiredFields);

  Widget _buildFooter(bool hasValid, int validCount) {
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
                onTap:
                    _isSubmitting || !_hasValidSongData ? null : _handleSubmit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _isSubmitting || !_hasValidSongData
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
                            color: _hasValidSongData
                                ? Colors.white
                                : Colors.white60,
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
// _TableTextField
//
// Simple text field for table cells. No paste interception — CSV ingestion
// is handled by the dedicated multiline text field above the table.
// ============================================================================

class _TableTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  const _TableTextField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.keyboardType,
    this.inputFormatters,
    required this.textCapitalization,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textMuted.withValues(alpha: 0.4),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        border: InputBorder.none,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
    );
  }
}

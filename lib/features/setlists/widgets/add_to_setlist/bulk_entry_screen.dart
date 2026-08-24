import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../../app/services/supabase_client.dart';
import '../../models/bulk_song_row.dart';
import '../../services/bulk_song_parser.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import '../../../songs/services/inline_song_enrichment_service.dart';
import '../../../songs/widgets/enrichment_confirm_dialog.dart';

// ============================================================================
// BULK ENTRY SCREEN
// Screen 3 of the Add to Setlist flow — paste or type many songs at once.
//
// Structured editable table with columns: Artist | Song | BPM | Tuning | Key
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
  final TextEditingController key;
  final FocusNode artistFocus;
  final FocusNode songFocus;
  final FocusNode bpmFocus;
  final FocusNode tuningFocus;
  final FocusNode keyFocus;

  _RowData()
      : artist = TextEditingController(),
        song = TextEditingController(),
        bpm = TextEditingController(),
        tuning = TextEditingController(),
        key = TextEditingController(),
        artistFocus = FocusNode(),
        songFocus = FocusNode(),
        bpmFocus = FocusNode(),
        tuningFocus = FocusNode(),
        keyFocus = FocusNode();

  void dispose() {
    artist.dispose();
    song.dispose();
    bpm.dispose();
    tuning.dispose();
    key.dispose();
    artistFocus.dispose();
    songFocus.dispose();
    bpmFocus.dispose();
    tuningFocus.dispose();
    keyFocus.dispose();
  }

  bool get isEmpty =>
      artist.text.trim().isEmpty &&
      song.text.trim().isEmpty &&
      bpm.text.trim().isEmpty &&
      tuning.text.trim().isEmpty &&
      key.text.trim().isEmpty;

  bool get hasRequiredFields =>
      artist.text.trim().isNotEmpty && song.text.trim().isNotEmpty;
}

// -------------------------------------------------------
// Constants
// -------------------------------------------------------

const int _kInitialRows = 5;
const int _kMaxRows = 500;

const int _kFlexArtist = 5; // 25%
const int _kFlexSong = 5; // 25%
const int _kFlexBpm = 3; // 15%
const int _kFlexTuning = 4; // 20%
const int _kFlexKey = 3; // 15%
const double _kDeleteWidth = 16;
const double _kCellHeight = 42;

// -------------------------------------------------------
// BulkEntryScreen widget
// -------------------------------------------------------

class BulkEntryScreen extends StatefulWidget {
  final OnBulkSongsSubmitted onSubmit;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final String bandId;
  final InlineSongEnrichmentService enrichmentService;

  const BulkEntryScreen({
    super.key,
    required this.onSubmit,
    required this.onBack,
    this.onClose,
    required this.bandId,
    required this.enrichmentService,
  });

  @override
  State<BulkEntryScreen> createState() => _BulkEntryScreenState();
}

class _BulkEntryScreenState extends State<BulkEntryScreen> {
  final List<_RowData> _rows = [];
  bool _isSubmitting = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _csvController = TextEditingController();
  final FocusNode _csvFocusNode = FocusNode();

  int _focusedRowIndex = 0;
  bool _isLoadingSongs = false;
  String? _ingestionSummary;
  bool _hasLoadedSongs = false;
  bool _isPasteFieldFocused = false;

  // -------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _kInitialRows; i++) {
      _rows.add(_createRow());
    }
    _csvFocusNode.addListener(_handleCsvFocusChange);
  }

  void _handleCsvFocusChange() {
    if (!mounted) return;
    setState(() {
      _isPasteFieldFocused = _csvFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _scrollController.dispose();
    _csvController.dispose();
    _csvFocusNode.dispose();
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
    row.keyFocus.addListener(trackFocus);
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

    // Empty text: clear table and hide it.
    if (text.isEmpty) {
      if (_hasLoadedSongs) {
        FocusManager.instance.primaryFocus?.unfocus();
        _focusedRowIndex = 0;
        for (final r in _rows) {
          r.dispose();
        }
        _rows.clear();
        for (var i = 0; i < _kInitialRows; i++) {
          _rows.add(_createRow());
        }
        setState(() {
          _hasLoadedSongs = false;
          _ingestionSummary = null;
        });
      }
      return;
    }

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
      _hasLoadedSongs = true;
      _ingestionSummary =
          validCount > 0 ? parts.join(', ') : 'No valid songs found';
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
      row.key.text = parsed.musicalKey ?? '';
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

  /// Check if a song exists in the band's catalog
  Future<bool> _songExists(String title, String artist) async {
    try {
      final result = await supabase
          .from('songs')
          .select('id')
          .eq('band_id', widget.bandId)
          .ilike('title', title.trim())
          .ilike('artist', artist.trim())
          .limit(1);
      return (result as List).isNotEmpty;
    } catch (e) {
      debugPrint('[BulkEntryScreen] Error checking song existence: $e');
      return false; // Assume new on error to allow enrichment
    }
  }

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
          '${r.tuning.text.trim()}\t'
          '${r.key.text.trim()}',
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

      // Apply Ask enrichment behavior (hardcoded)
      final enrichedRows = <BulkSongRow>[];

      for (final row in parseResult.validRows) {
        // Check if song exists
        final exists = await _songExists(row.title, row.artist);

        if (exists) {
          // Existing song - use row as-is
          enrichedRows.add(row);
          continue;
        }

        // New song - always show confirmation dialog (Ask behavior)
        if (!mounted) return;
        final shouldEnrich = await showEnrichmentConfirmDialog(
          context,
          title: row.title,
          artist: row.artist,
          enrichmentService: widget.enrichmentService,
        );

        if (shouldEnrich == null) {
          // User cancelled - abort entire submission
          if (mounted) setState(() => _isSubmitting = false);
          return;
        }

        if (shouldEnrich) {
          // Enrich the song
          final enrichmentResult = await widget.enrichmentService.enrichSong(
            title: row.title,
            artist: row.artist,
          );

          enrichedRows.add(BulkSongRow(
            artist: row.artist,
            title: row.title,
            bpm: enrichmentResult.bpm ?? row.bpm,
            tuning: row.tuning,
            tuningLabel: row.tuningLabel,
            musicalKey: enrichmentResult.musicalKey ?? row.musicalKey,
          ));
        } else {
          // Skip enrichment
          enrichedRows.add(row);
        }
      }

      final result = await widget.onSubmit(enrichedRows);

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
    final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;
    final showExpandedPasteField = !_hasLoadedSongs || _isPasteFieldFocused;
    final validCount = _validRowCount;
    final hasValid = validCount > 0;

    final pasteUiBlock = Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.space16,
        showFullPasteUi ? Spacing.space12 : Spacing.space4,
        Spacing.space16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showFullPasteUi) ...[
            const Text(
              'Paste songs from a spreadsheet, then tap Load Songs.',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppFontSizes.body,
              ),
            ),
            const SizedBox(height: Spacing.space12),
            Container(
              padding: const EdgeInsets.all(Spacing.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Column order:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSizes.subhead,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  const Text(
                    'Artist, Song, BPM, Tuning, Key',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSizes.body,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  Text(
                    '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: AppFontSizes.subhead,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  const Text(
                    'Required columns: Artist, Song',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSizes.body,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  const Text(
                    'Optional columns: BPM, Tuning, Key',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppFontSizes.body,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.space16),
          ],
          AppTextField(
            key: const ValueKey('bulk-entry-csv-field'),
            controller: _csvController,
            focusNode: _csvFocusNode,
            maxLines: 5,
            minLines: showExpandedPasteField ? 3 : 1,
            style: TextStyle(
              fontSize: AppFontSizes.caption,
              color: context.colors.textPrimary,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              isDense: !showExpandedPasteField,
              hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
              hintStyle: TextStyle(
                fontSize: AppFontSizes.caption,
                color: context.colors.textMuted.withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              contentPadding: showExpandedPasteField
                  ? const EdgeInsets.all(12)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.colors.border,
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.colors.border,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppColors.primary,
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
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
                alignment: Alignment.center,
                child: _isLoadingSongs
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: AppProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Load Songs',
                        style: AppTextStyles.button.copyWith(
                          color: Colors.white,
                          fontSize: AppFontSizes.subhead,
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
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.caption,
              ),
            ),
          ],
        ],
      ),
    );

    return Column(
      children: [
        Flexible(
          flex: keyboardHeight > 0 ? 1 : 0,
          child: SingleChildScrollView(
            physics: keyboardHeight > 0
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: pasteUiBlock,
          ),
        ),
        if (_hasLoadedSongs && !showExpandedPasteField) ...[
          const SizedBox(height: Spacing.space12),
          _buildColumnHeaders(),
          Expanded(
            child: GestureDetector(
              onTap: _dismissKeyboard,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: Spacing.space8),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _rows.length,
                itemBuilder: (context, index) => _buildRow(index),
              ),
            ),
          ),
          _buildAddRowButton(),
        ] else
          const Expanded(child: SizedBox.shrink()),
        if (keyboardHeight > 0) _buildKeyboardToolbar(),
        if ((_hasLoadedSongs && !showExpandedPasteField) || keyboardHeight == 0)
          _buildFooter(hasValid, validCount),
      ],
    );
  }

  // -------------------------------------------------------
  // Column headers
  // -------------------------------------------------------

  Widget _buildColumnHeaders() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          _headerCell('Artist', _kFlexArtist),
          _headerCell('Song', _kFlexSong),
          _headerCell('BPM', _kFlexBpm),
          _headerCell('Tuning', _kFlexTuning),
          _headerCell('Key', _kFlexKey),
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
            color: context.colors.textSecondary,
            fontSize: AppFontSizes.caption,
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
        border: Border(
          bottom: BorderSide(color: context.colors.surfaceElevated, width: 1),
        ),
      ),
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
          _tableCell(
            controller: row.key,
            focusNode: row.keyFocus,
            flex: _kFlexKey,
            hint: '-',
            rowIndex: index,
          ),
          SizedBox(
            width: _kDeleteWidth,
            height: _kCellHeight,
            child: _rows.length > 1
                ? GestureDetector(
                    onTap: () => _removeRow(index),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Icon(
                        AppIcons.close,
                        size: 16,
                        color: context.colors.textMuted,
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
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.colors.border, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.add,
              size: 18,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Add Row',
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.subhead,
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
      key: const ValueKey('bulk-entry-keyboard-toolbar'),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space8,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        border: Border(
          top: BorderSide(color: context.colors.border, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _dismissKeyboard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: AppFontSizes.subhead,
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
      key: const ValueKey('bulk-entry-footer'),
      padding: EdgeInsets.fromLTRB(
        Spacing.pagePadding,
        Spacing.space12,
        Spacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom + Spacing.space16,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
        border: Border(
          top: BorderSide(
            color: context.colors.border.withValues(alpha: 0.3),
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
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  ),
                  alignment: Alignment.center,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: AppProgressIndicator(
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
                            fontSize: AppFontSizes.body,
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
                    color: context.colors.textSecondary,
                    fontSize: AppFontSizes.body,
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
    return AppTextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: TextStyle(
        fontSize: AppFontSizes.caption,
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: AppFontSizes.caption,
          color: context.colors.textMuted.withValues(alpha: 0.4),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        border: InputBorder.none,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.transparent),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}

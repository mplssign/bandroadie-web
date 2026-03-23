class PrintTemplate {
  final String? id;
  final String bandId;
  final String name;
  final String tuningDisplay; // 'grouped' | 'inline'
  final bool showTuning;
  final bool showCapo;
  final bool showBpm;
  final bool showNotes;
  final bool showPauses;
  final bool showSongNumbers;
  final bool showHeader;
  final bool showBandName;
  final bool showPageNumbers;
  final double baseFontSize; // 14.0 – 36.0 (song title)
  final double numberFontSize; // 14.0 – 36.0
  final double headerFontSize; // 14.0 – 36.0
  final double bandNameFontSize; // 14.0 – 36.0
  final double bpmFontSize; // 14.0 – 36.0
  final double tuningFontSize; // 14.0 – 36.0
  final double capoFontSize; // 14.0 – 36.0
  final double notesFontSize; // 14.0 – 36.0
  final double pauseFontSize; // 14.0 – 36.0
  final double lineSpacing; // 0.0 – 3.0 multiplier
  final String paperSize; // 'letter' | 'a4' | 'legal' | 'tabloid'
  final int columnCount; // 1 | 2
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const double _minFont = 14.0;
  static const double _maxFont = 36.0;

  const PrintTemplate({
    this.id,
    required this.bandId,
    required this.name,
    this.tuningDisplay = 'grouped',
    this.showTuning = true,
    this.showCapo = true,
    this.showBpm = true,
    this.showNotes = false,
    this.showPauses = true,
    this.showSongNumbers = true,
    this.showHeader = true,
    this.showBandName = true,
    this.showPageNumbers = true,
    this.baseFontSize = 18.0,
    this.numberFontSize = 18.0,
    this.headerFontSize = 28.0,
    this.bandNameFontSize = 16.0,
    this.bpmFontSize = 16.0,
    this.tuningFontSize = 14.0,
    this.capoFontSize = 14.0,
    this.notesFontSize = 14.0,
    this.pauseFontSize = 16.0,
    this.lineSpacing = 1.0,
    this.paperSize = 'letter',
    this.columnCount = 1,
    this.createdAt,
    this.updatedAt,
  });

  /// Default template matching current hardcoded behavior.
  static PrintTemplate defaultTemplate({required String bandId}) {
    return PrintTemplate(
      bandId: bandId,
      name: 'Default',
    );
  }

  factory PrintTemplate.fromSupabase(Map<String, dynamic> json) {
    double clampFont(String key, double fallback) =>
        ((json[key] as num?)?.toDouble() ?? fallback).clamp(_minFont, _maxFont);

    return PrintTemplate(
      id: json['id'] as String?,
      bandId: json['band_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      tuningDisplay: json['tuning_display'] as String? ?? 'grouped',
      showTuning: json['show_tuning'] as bool? ?? true,
      showCapo: json['show_capo'] as bool? ?? true,
      showBpm: json['show_bpm'] as bool? ?? true,
      showNotes: json['show_notes'] as bool? ?? false,
      showPauses: json['show_pauses'] as bool? ?? true,
      showSongNumbers: json['show_song_numbers'] as bool? ?? true,
      showHeader: json['show_header'] as bool? ?? true,
      showBandName: json['show_band_name'] as bool? ?? true,
      showPageNumbers: json['show_page_numbers'] as bool? ?? true,
      baseFontSize: clampFont('base_font_size', 18.0),
      numberFontSize: clampFont('number_font_size', 18.0),
      headerFontSize: clampFont('header_font_size', 28.0),
      bandNameFontSize: clampFont('band_name_font_size', 16.0),
      bpmFontSize: clampFont('bpm_font_size', 16.0),
      tuningFontSize: clampFont('tuning_font_size', 14.0),
      capoFontSize: clampFont('capo_font_size', 14.0),
      notesFontSize: clampFont('notes_font_size', 14.0),
      pauseFontSize: clampFont('pause_font_size', 16.0),
      lineSpacing:
          ((json['line_spacing'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 3.0),
      paperSize: json['paper_size'] as String? ?? 'letter',
      columnCount: json['column_count'] as int? ?? 1,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'band_id': bandId,
      'name': name,
      'tuning_display': tuningDisplay,
      'show_tuning': showTuning,
      'show_capo': showCapo,
      'show_bpm': showBpm,
      'show_notes': showNotes,
      'show_pauses': showPauses,
      'show_song_numbers': showSongNumbers,
      'show_header': showHeader,
      'show_band_name': showBandName,
      'show_page_numbers': showPageNumbers,
      'base_font_size': baseFontSize.clamp(_minFont, _maxFont),
      'number_font_size': numberFontSize.clamp(_minFont, _maxFont),
      'header_font_size': headerFontSize.clamp(_minFont, _maxFont),
      'band_name_font_size': bandNameFontSize.clamp(_minFont, _maxFont),
      'bpm_font_size': bpmFontSize.clamp(_minFont, _maxFont),
      'tuning_font_size': tuningFontSize.clamp(_minFont, _maxFont),
      'capo_font_size': capoFontSize.clamp(_minFont, _maxFont),
      'notes_font_size': notesFontSize.clamp(_minFont, _maxFont),
      'pause_font_size': pauseFontSize.clamp(_minFont, _maxFont),
      'line_spacing': lineSpacing.clamp(0.0, 3.0),
      'paper_size': paperSize,
      'column_count': columnCount,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name,
      'tuning_display': tuningDisplay,
      'show_tuning': showTuning,
      'show_capo': showCapo,
      'show_bpm': showBpm,
      'show_notes': showNotes,
      'show_pauses': showPauses,
      'show_song_numbers': showSongNumbers,
      'show_header': showHeader,
      'show_band_name': showBandName,
      'show_page_numbers': showPageNumbers,
      'base_font_size': baseFontSize.clamp(_minFont, _maxFont),
      'number_font_size': numberFontSize.clamp(_minFont, _maxFont),
      'header_font_size': headerFontSize.clamp(_minFont, _maxFont),
      'band_name_font_size': bandNameFontSize.clamp(_minFont, _maxFont),
      'bpm_font_size': bpmFontSize.clamp(_minFont, _maxFont),
      'tuning_font_size': tuningFontSize.clamp(_minFont, _maxFont),
      'capo_font_size': capoFontSize.clamp(_minFont, _maxFont),
      'notes_font_size': notesFontSize.clamp(_minFont, _maxFont),
      'pause_font_size': pauseFontSize.clamp(_minFont, _maxFont),
      'line_spacing': lineSpacing.clamp(0.0, 3.0),
      'paper_size': paperSize,
      'column_count': columnCount,
    };
  }

  PrintTemplate copyWith({
    String? id,
    String? bandId,
    String? name,
    String? tuningDisplay,
    bool? showTuning,
    bool? showCapo,
    bool? showBpm,
    bool? showNotes,
    bool? showPauses,
    bool? showSongNumbers,
    bool? showHeader,
    bool? showBandName,
    bool? showPageNumbers,
    double? baseFontSize,
    double? numberFontSize,
    double? headerFontSize,
    double? bandNameFontSize,
    double? bpmFontSize,
    double? tuningFontSize,
    double? capoFontSize,
    double? notesFontSize,
    double? pauseFontSize,
    double? lineSpacing,
    String? paperSize,
    int? columnCount,
  }) {
    return PrintTemplate(
      id: id ?? this.id,
      bandId: bandId ?? this.bandId,
      name: name ?? this.name,
      tuningDisplay: tuningDisplay ?? this.tuningDisplay,
      showTuning: showTuning ?? this.showTuning,
      showCapo: showCapo ?? this.showCapo,
      showBpm: showBpm ?? this.showBpm,
      showNotes: showNotes ?? this.showNotes,
      showPauses: showPauses ?? this.showPauses,
      showSongNumbers: showSongNumbers ?? this.showSongNumbers,
      showHeader: showHeader ?? this.showHeader,
      showBandName: showBandName ?? this.showBandName,
      showPageNumbers: showPageNumbers ?? this.showPageNumbers,
      baseFontSize:
          (baseFontSize ?? this.baseFontSize).clamp(_minFont, _maxFont),
      numberFontSize:
          (numberFontSize ?? this.numberFontSize).clamp(_minFont, _maxFont),
      headerFontSize:
          (headerFontSize ?? this.headerFontSize).clamp(_minFont, _maxFont),
      bandNameFontSize:
          (bandNameFontSize ?? this.bandNameFontSize).clamp(_minFont, _maxFont),
      bpmFontSize: (bpmFontSize ?? this.bpmFontSize).clamp(_minFont, _maxFont),
      tuningFontSize:
          (tuningFontSize ?? this.tuningFontSize).clamp(_minFont, _maxFont),
      capoFontSize:
          (capoFontSize ?? this.capoFontSize).clamp(_minFont, _maxFont),
      notesFontSize:
          (notesFontSize ?? this.notesFontSize).clamp(_minFont, _maxFont),
      pauseFontSize:
          (pauseFontSize ?? this.pauseFontSize).clamp(_minFont, _maxFont),
      lineSpacing: (lineSpacing ?? this.lineSpacing).clamp(0.0, 3.0),
      paperSize: paperSize ?? this.paperSize,
      columnCount: columnCount ?? this.columnCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PrintTemplate) return false;
    return id == other.id &&
        bandId == other.bandId &&
        name == other.name &&
        tuningDisplay == other.tuningDisplay &&
        showTuning == other.showTuning &&
        showCapo == other.showCapo &&
        showBpm == other.showBpm &&
        showNotes == other.showNotes &&
        showPauses == other.showPauses &&
        showSongNumbers == other.showSongNumbers &&
        showHeader == other.showHeader &&
        showBandName == other.showBandName &&
        showPageNumbers == other.showPageNumbers &&
        baseFontSize == other.baseFontSize &&
        numberFontSize == other.numberFontSize &&
        headerFontSize == other.headerFontSize &&
        bandNameFontSize == other.bandNameFontSize &&
        bpmFontSize == other.bpmFontSize &&
        tuningFontSize == other.tuningFontSize &&
        capoFontSize == other.capoFontSize &&
        notesFontSize == other.notesFontSize &&
        pauseFontSize == other.pauseFontSize &&
        lineSpacing == other.lineSpacing &&
        paperSize == other.paperSize &&
        columnCount == other.columnCount;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        bandId,
        name,
        tuningDisplay,
        showTuning,
        showCapo,
        showBpm,
        showNotes,
        showSongNumbers,
        showHeader,
        showPageNumbers,
        baseFontSize,
        numberFontSize,
        headerFontSize,
        bandNameFontSize,
        bpmFontSize,
        tuningFontSize,
        capoFontSize,
        notesFontSize,
        pauseFontSize,
        lineSpacing,
        paperSize,
        columnCount,
      ]);

  @override
  String toString() => 'PrintTemplate(id: $id, name: $name)';
}

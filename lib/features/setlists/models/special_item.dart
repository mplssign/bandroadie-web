import 'setlist_item_type.dart';

/// Predefined pause purposes available for selection.
class PausePurposes {
  PausePurposes._();

  static const List<String> predefined = [
    'Guitar Change',
    'Band Intro',
    'Crowd Interaction',
    'Tuning Break',
    'Instrument Swap',
    'Acoustic Transition',
    'Story / Song Intro',
    'Guest Appearance',
    'Pause for Encore',
    'Tempo Reset',
    'Guitar Solo',
    'Drum Solo',
    'Keys Solo',
    'Bass Solo',
    'Medley Transition',
  ];
}

/// Model for a reusable set break or pause template.
/// Maps to public.setlist_special_items table.
///
/// These are NOT songs and do NOT belong in the band catalog.
/// They represent reusable templates that can be added to any setlist.
class SpecialItem {
  final String id;
  final String bandId;
  final SetlistItemType type;

  /// Duration in minutes (used for set_break, 5-min increments)
  final int? durationMinutes;

  /// Duration in seconds (used for pause, optional freeform)
  final int? durationSeconds;

  /// Selected predefined purposes (for pause type)
  final List<String> purposes;

  /// User-defined custom purposes (for pause type)
  final List<String> customPurposes;

  /// Whether this item is saved as a reusable template
  final bool isSavedTemplate;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SpecialItem({
    required this.id,
    required this.bandId,
    required this.type,
    this.durationMinutes,
    this.durationSeconds,
    this.purposes = const [],
    this.customPurposes = const [],
    this.isSavedTemplate = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Get the effective duration in seconds for runtime calculations.
  ///
  /// - Set Break: always has duration (durationMinutes * 60)
  /// - Pause: only if durationSeconds is provided and > 0
  int get effectiveDurationSeconds {
    if (type == SetlistItemType.setBreak && durationMinutes != null) {
      return durationMinutes! * 60;
    }
    if (type == SetlistItemType.pause && durationSeconds != null) {
      return durationSeconds!;
    }
    return 0;
  }

  /// Whether this item contributes to runtime.
  /// Set breaks always do. Pauses only if they have a duration.
  bool get contributesToRuntime {
    if (type == SetlistItemType.setBreak) return true;
    if (type == SetlistItemType.pause) {
      return durationSeconds != null && durationSeconds! > 0;
    }
    return false;
  }

  /// Display title for the item.
  ///
  /// Set Break: "SET BREAK – 20 mins"
  /// Pause: purposes joined by " - " (e.g., "GUITAR CHANGE - TUNING BREAK")
  String get displayTitle {
    if (type == SetlistItemType.setBreak) {
      final mins = durationMinutes ?? 0;
      return 'SET BREAK – $mins mins';
    }

    // Pause: combine purposes
    final allPurposes = [...purposes, ...customPurposes];
    if (allPurposes.isEmpty) return 'PAUSE';
    return allPurposes.map((p) => p.toUpperCase()).join(' - ');
  }

  /// Formatted duration for display below the title.
  /// Only shown for pauses with duration.
  /// Returns null if no duration to display.
  String? get formattedSubDuration {
    if (type == SetlistItemType.pause &&
        durationSeconds != null &&
        durationSeconds! > 0) {
      final mins = durationSeconds! ~/ 60;
      final secs = durationSeconds! % 60;
      return '($mins:${secs.toString().padLeft(2, '0')})';
    }
    return null;
  }

  /// Factory constructor from Supabase response
  factory SpecialItem.fromSupabase(Map<String, dynamic> json) {
    return SpecialItem(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      type: SetlistItemType.fromString(json['type'] as String?),
      durationMinutes: json['duration_minutes'] as int?,
      durationSeconds: json['duration_seconds'] as int?,
      purposes: _parseTextArray(json['purposes']),
      customPurposes: _parseTextArray(json['custom_purposes']),
      isSavedTemplate: json['is_saved_template'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  /// Convert to Supabase insert/update map
  Map<String, dynamic> toSupabase() {
    return {
      'band_id': bandId,
      'type': type.toDbString(),
      'duration_minutes': durationMinutes,
      'duration_seconds': durationSeconds,
      'purposes': purposes.isEmpty ? null : purposes,
      'custom_purposes': customPurposes.isEmpty ? null : customPurposes,
      'is_saved_template': isSavedTemplate,
    };
  }

  SpecialItem copyWith({
    String? id,
    String? bandId,
    SetlistItemType? type,
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool? isSavedTemplate,
    bool clearDurationMinutes = false,
    bool clearDurationSeconds = false,
  }) {
    return SpecialItem(
      id: id ?? this.id,
      bandId: bandId ?? this.bandId,
      type: type ?? this.type,
      durationMinutes: clearDurationMinutes
          ? null
          : (durationMinutes ?? this.durationMinutes),
      durationSeconds: clearDurationSeconds
          ? null
          : (durationSeconds ?? this.durationSeconds),
      purposes: purposes ?? this.purposes,
      customPurposes: customPurposes ?? this.customPurposes,
      isSavedTemplate: isSavedTemplate ?? this.isSavedTemplate,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Parse a PostgreSQL text array from dynamic value
  static List<String> _parseTextArray(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }
}

// ============================================================================
// SPECIAL ITEM MODEL
// Represents a reusable Set Break or Pause template stored in
// setlist_special_items. These are NOT songs and NOT in the catalog.
// ============================================================================

import 'setlist_item_type.dart';

class SpecialItem {
  final String id;
  final String bandId;
  final SetlistItemType type;
  final int? durationMinutes; // for set_break
  final int? durationSeconds; // for pause
  final List<String> purposes;
  final List<String> customPurposes;
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

  /// Total duration in seconds for runtime calculations.
  /// Set Break: duration_minutes * 60.
  /// Pause: duration_seconds (or 0 if null / informational only).
  int get totalDurationSeconds {
    if (type == SetlistItemType.setBreak) {
      return (durationMinutes ?? 0) * 60;
    }
    return durationSeconds ?? 0;
  }

  /// Whether this item contributes to setlist runtime.
  /// Set breaks always contribute; pauses only if they have a duration.
  bool get contributesToRuntime {
    if (type == SetlistItemType.setBreak) return true;
    return durationSeconds != null && durationSeconds! > 0;
  }

  /// Human-readable label for display.
  String get displayLabel {
    if (type == SetlistItemType.setBreak) {
      final mins = durationMinutes ?? 0;
      return 'Set Break${mins > 0 ? ' • ${mins}m' : ''}';
    }
    final allPurposes = [...purposes, ...customPurposes];
    if (allPurposes.isNotEmpty) {
      return allPurposes.join(', ');
    }
    return 'Pause${durationSeconds != null ? ' • ${_formatSeconds(durationSeconds!)}' : ''}';
  }

  String _formatSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Parse from Supabase row.
  factory SpecialItem.fromSupabase(Map<String, dynamic> json) {
    return SpecialItem(
      id: json['id'] as String,
      bandId: json['band_id'] as String? ?? '',
      type: SetlistItemType.fromDb(json['type'] as String?),
      durationMinutes: json['duration_minutes'] as int?,
      durationSeconds: json['duration_seconds'] as int?,
      purposes: _toStringList(json['purposes']),
      customPurposes: _toStringList(json['custom_purposes']),
      isSavedTemplate: json['is_saved_template'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  SpecialItem copyWith({
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool? isSavedTemplate,
  }) {
    return SpecialItem(
      id: id,
      bandId: bandId,
      type: type,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      purposes: purposes ?? this.purposes,
      customPurposes: customPurposes ?? this.customPurposes,
      isSavedTemplate: isSavedTemplate ?? this.isSavedTemplate,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

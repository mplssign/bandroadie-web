import 'package:flutter/foundation.dart';

/// Apply-to mode for One Calendar feature
enum ApplyToMode {
  allBands('all_bands'),
  selectedBands('selected_bands');

  const ApplyToMode(this.value);
  final String value;

  static ApplyToMode fromString(String value) {
    return ApplyToMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => ApplyToMode.allBands,
    );
  }
}

/// User preferences for One Calendar feature
/// Allows users to share block-out dates across multiple bands
@immutable
class OneCalendarPreferences {
  final String id;
  final String userId;
  final bool oneCalendarEnabled;
  final ApplyToMode applyToMode;
  final List<String> selectedBandIds;
  final bool autoBlockConflictsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OneCalendarPreferences({
    required this.id,
    required this.userId,
    required this.oneCalendarEnabled,
    required this.applyToMode,
    required this.selectedBandIds,
    required this.autoBlockConflictsEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create from Supabase JSON
  factory OneCalendarPreferences.fromJson(Map<String, dynamic> json) {
    return OneCalendarPreferences(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      oneCalendarEnabled: json['one_calendar_enabled'] as bool,
      applyToMode: ApplyToMode.fromString(json['apply_to_mode'] as String),
      selectedBandIds: (json['selected_band_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      autoBlockConflictsEnabled: json['auto_block_conflicts_enabled'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to Supabase JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'one_calendar_enabled': oneCalendarEnabled,
      'apply_to_mode': applyToMode.value,
      'selected_band_ids': selectedBandIds,
      'auto_block_conflicts_enabled': autoBlockConflictsEnabled,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  OneCalendarPreferences copyWith({
    String? id,
    String? userId,
    bool? oneCalendarEnabled,
    ApplyToMode? applyToMode,
    List<String>? selectedBandIds,
    bool? autoBlockConflictsEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OneCalendarPreferences(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      oneCalendarEnabled: oneCalendarEnabled ?? this.oneCalendarEnabled,
      applyToMode: applyToMode ?? this.applyToMode,
      selectedBandIds: selectedBandIds ?? this.selectedBandIds,
      autoBlockConflictsEnabled:
          autoBlockConflictsEnabled ?? this.autoBlockConflictsEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is OneCalendarPreferences &&
        other.id == id &&
        other.userId == userId &&
        other.oneCalendarEnabled == oneCalendarEnabled &&
        other.applyToMode == applyToMode &&
        listEquals(other.selectedBandIds, selectedBandIds) &&
        other.autoBlockConflictsEnabled == autoBlockConflictsEnabled &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      userId,
      oneCalendarEnabled,
      applyToMode,
      Object.hashAll(selectedBandIds),
      autoBlockConflictsEnabled,
      createdAt,
      updatedAt,
    );
  }
}

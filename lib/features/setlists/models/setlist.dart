import '../../../app/constants/app_constants.dart';
import 'setlist_song.dart';

// ============================================================================
// SAFE PARSING HELPERS
// These functions ensure no crashes when parsing potentially malformed data
// ============================================================================

/// Safely convert dynamic value to String, returning null if not possible
String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

/// Safely convert dynamic value to int, with fallback
int _asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// Safely convert dynamic value to bool, with fallback
bool _asBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) {
    final lower = v.toLowerCase();
    return lower == 'true' || lower == '1' || lower == 'yes';
  }
  return fallback;
}

/// Safely parse dynamic value to DateTime, returning null if not possible
DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Setlist model for displaying setlist data.
/// Maps to public.setlists table in Supabase.
class Setlist {
  final String id;
  final String name;
  final int songCount;
  final Duration totalDuration;
  final DateTime? lastUpdated;
  final String? bandId;
  final List<SetlistSong> songs;
  final bool isCatalog;

  const Setlist({
    required this.id,
    required this.name,
    required this.songCount,
    required this.totalDuration,
    this.lastUpdated,
    this.bandId,
    this.songs = const [],
    this.isCatalog = false,
  });

  /// Create from Supabase query result
  /// Expected structure:
  /// {
  ///   id: uuid,
  ///   name: string,
  ///   band_id: uuid,
  ///   total_duration: int?,
  ///   is_catalog: bool?,
  ///   created_at: string,
  ///   updated_at: string,
  ///   song_count: int (from subquery or join)
  /// }
  ///
  /// This factory is resilient to type mismatches and null values.
  /// It will never throw - instead it uses safe defaults.
  factory Setlist.fromSupabase(Map<String, dynamic> json) {
    // song_count comes from a subquery COUNT(*) - handle int, double, String
    final songCount = _asInt(json['song_count']);

    // total_duration is in seconds - handle int, double, String, null
    // Support both snake_case and camelCase keys
    final totalSeconds = _asInt(
      json['total_duration'] ?? json['totalDuration'],
    );

    // Parse updated_at for lastUpdated - handle null, invalid strings
    final lastUpdated = _asDateTime(json['updated_at'] ?? json['updatedAt']);

    // is_catalog is a boolean column in the database
    // Fall back to name comparison for backwards compatibility during migration
    // Use shared constant for detection
    final name = _asString(json['name']) ?? 'Untitled';
    final isCatalogByName = isCatalogName(name);
    final isCatalog = _asBool(
      json['is_catalog'] ?? json['isCatalog'],
      fallback: isCatalogByName,
    );

    // id is required but we provide a fallback to prevent crashes
    final id =
        _asString(json['id']) ??
        'unknown-${DateTime.now().millisecondsSinceEpoch}';

    return Setlist(
      id: id,
      name: name,
      bandId: _asString(json['band_id'] ?? json['bandId']),
      songCount: songCount,
      totalDuration: Duration(seconds: totalSeconds),
      lastUpdated: lastUpdated,
      isCatalog: isCatalog,
    );
  }

  /// Format duration as "Xh XXm" matching Figma spec
  String get formattedDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  /// Format song count with proper pluralization
  String get formattedSongCount {
    return '$songCount ${songCount == 1 ? 'song' : 'songs'}';
  }
}

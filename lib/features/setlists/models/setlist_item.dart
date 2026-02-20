import 'setlist_item_type.dart';
import 'setlist_song.dart';
import 'special_item.dart';

/// A unified item in a setlist that can be either a song, set break, or pause.
///
/// This is the display model used by the UI. It wraps either a [SetlistSong]
/// or a [SpecialItem] with a shared position and item type.
///
/// The underlying data comes from the `setlist_songs` table which now supports
/// mixed item types via `item_type`, `song_id`, and `special_item_id` columns.
class SetlistItem {
  /// The setlist_songs row ID (for deletion and reordering)
  final String setlistSongId;

  /// The type of this item
  final SetlistItemType itemType;

  /// Position in the setlist (0-indexed)
  final int position;

  /// The song data (only set when itemType == song)
  final SetlistSong? song;

  /// The special item data (only set when itemType is setBreak or pause)
  final SpecialItem? specialItem;

  const SetlistItem({
    required this.setlistSongId,
    required this.itemType,
    required this.position,
    this.song,
    this.specialItem,
  });

  /// Whether this is a song
  bool get isSong => itemType == SetlistItemType.song;

  /// Whether this is a set break
  bool get isSetBreak => itemType == SetlistItemType.setBreak;

  /// Whether this is a pause
  bool get isPause => itemType == SetlistItemType.pause;

  /// Whether this is a special item (break or pause)
  bool get isSpecial => itemType.isSpecial;

  /// Duration in seconds for runtime calculation.
  /// - Songs: use song.durationSeconds
  /// - Set Breaks: always contribute (durationMinutes * 60)
  /// - Pauses: only if durationSeconds is set
  int get durationSeconds {
    if (isSong && song != null) return song!.durationSeconds;
    if (isSpecial && specialItem != null) {
      return specialItem!.effectiveDurationSeconds;
    }
    return 0;
  }

  /// Whether this item contributes to runtime calculation
  bool get contributesToRuntime {
    if (isSong) return true;
    if (isSpecial && specialItem != null) {
      return specialItem!.contributesToRuntime;
    }
    return false;
  }

  /// Display title
  String get displayTitle {
    if (isSong && song != null) return song!.title;
    if (isSpecial && specialItem != null) return specialItem!.displayTitle;
    return '';
  }

  /// Unique key for list rendering (combines type + ID to avoid collisions)
  String get uniqueKey {
    if (isSong && song != null) return 'song_${song!.id}';
    if (isSpecial && specialItem != null) {
      return 'special_${specialItem!.id}_$setlistSongId';
    }
    return 'unknown_$setlistSongId';
  }

  /// The ID used for the item itself (song ID or special item ID)
  String get itemId {
    if (isSong && song != null) return song!.id;
    if (isSpecial && specialItem != null) return specialItem!.id;
    return setlistSongId;
  }

  SetlistItem copyWith({
    String? setlistSongId,
    SetlistItemType? itemType,
    int? position,
    SetlistSong? song,
    SpecialItem? specialItem,
  }) {
    return SetlistItem(
      setlistSongId: setlistSongId ?? this.setlistSongId,
      itemType: itemType ?? this.itemType,
      position: position ?? this.position,
      song: song ?? this.song,
      specialItem: specialItem ?? this.specialItem,
    );
  }

  /// Create a SetlistItem from a setlist_songs row with joined data.
  ///
  /// The query must select:
  ///   setlist_songs(id, item_type, position, song_id, special_item_id,
  ///     songs!left(...), setlist_special_items!left(...))
  factory SetlistItem.fromSupabase(Map<String, dynamic> json) {
    final itemTypeStr = json['item_type'] as String? ?? 'song';
    final itemType = SetlistItemType.fromString(itemTypeStr);

    SetlistSong? song;
    SpecialItem? specialItem;

    if (itemType == SetlistItemType.song && json['songs'] != null) {
      song = SetlistSong.fromSupabase(json);
    } else if (itemType.isSpecial && json['setlist_special_items'] != null) {
      specialItem = SpecialItem.fromSupabase(
        json['setlist_special_items'] as Map<String, dynamic>,
      );
    }

    return SetlistItem(
      setlistSongId: json['id'] as String,
      itemType: itemType,
      position: json['position'] as int? ?? 0,
      song: song,
      specialItem: specialItem,
    );
  }
}

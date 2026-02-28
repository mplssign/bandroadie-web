// ============================================================================
// SETLIST ITEM MODEL
// A unified item in a setlist's ordered list. Can be a song, set break,
// or pause. Used for rendering the mixed list in setlist detail.
// ============================================================================

import 'setlist_item_type.dart';
import 'setlist_song.dart';
import 'special_item.dart';

class SetlistItem {
  /// The setlist_songs row ID.
  final String id;
  final SetlistItemType type;
  final int position;

  /// Non-null only when type == song.
  final SetlistSong? song;

  /// Non-null only when type == set_break or pause.
  final SpecialItem? specialItem;

  const SetlistItem({
    required this.id,
    required this.type,
    required this.position,
    this.song,
    this.specialItem,
  });

  // ── Type helpers ──
  bool get isSong => type == SetlistItemType.song;
  bool get isSetBreak => type == SetlistItemType.setBreak;
  bool get isPause => type == SetlistItemType.pause;
  bool get isSpecial => !isSong;

  // ── Duration helpers ──

  /// Duration in seconds for this item.
  int get durationSeconds {
    if (isSong) return song?.durationSeconds ?? 0;
    return specialItem?.totalDurationSeconds ?? 0;
  }

  /// Whether this item contributes to setlist runtime.
  bool get contributesToRuntime {
    if (isSong) return true;
    return specialItem?.contributesToRuntime ?? false;
  }

  /// Unique key for list rendering. Combines type + id to avoid collisions.
  String get listKey => '${type.dbValue}-$id';

  SetlistItem copyWith({int? position, SetlistSong? song}) {
    return SetlistItem(
      id: id,
      type: type,
      position: position ?? this.position,
      song: song ?? this.song,
      specialItem: specialItem,
    );
  }
}

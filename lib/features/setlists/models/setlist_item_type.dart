/// Enum for setlist item types.
/// Determines whether a setlist entry is a song, set break, or pause.
enum SetlistItemType {
  song,
  setBreak,
  pause;

  /// Convert from database string value
  static SetlistItemType fromString(String? value) {
    switch (value) {
      case 'set_break':
        return SetlistItemType.setBreak;
      case 'pause':
        return SetlistItemType.pause;
      case 'song':
      default:
        return SetlistItemType.song;
    }
  }

  /// Convert to database string value
  String toDbString() {
    switch (this) {
      case SetlistItemType.song:
        return 'song';
      case SetlistItemType.setBreak:
        return 'set_break';
      case SetlistItemType.pause:
        return 'pause';
    }
  }

  /// Human-readable display name
  String get displayName {
    switch (this) {
      case SetlistItemType.song:
        return 'Song';
      case SetlistItemType.setBreak:
        return 'Set Break';
      case SetlistItemType.pause:
        return 'Pause';
    }
  }

  /// Whether this type is a special item (not a song)
  bool get isSpecial => this != SetlistItemType.song;
}

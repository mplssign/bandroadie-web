// ============================================================================
// SETLIST ITEM TYPE
// Discriminator for items in a setlist: songs, set breaks, and pauses.
// ============================================================================

enum SetlistItemType {
  song('song', 'Song'),
  setBreak('set_break', 'Set Break'),
  pause('pause', 'Pause');

  final String dbValue;
  final String displayName;

  const SetlistItemType(this.dbValue, this.displayName);

  /// Parse from database string value.
  static SetlistItemType fromDb(String? value) {
    switch (value) {
      case 'set_break':
        return SetlistItemType.setBreak;
      case 'pause':
        return SetlistItemType.pause;
      default:
        return SetlistItemType.song;
    }
  }
}

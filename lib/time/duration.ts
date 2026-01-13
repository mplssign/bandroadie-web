/**
 * Duration parsing and formatting utilities for setlist calculations
 * Handles various input formats and normalizes to seconds for accurate totals
 */

/**
 * Parse various duration formats into seconds
 * Priority: setlist_songs.duration_seconds > parse(duration_text) > songs.duration_seconds > 0
 * 
 * Supported formats:
 * - "M:SS" (e.g., "3:45" -> 225 seconds)
 * - "H:MM:SS" (e.g., "1:02:03" -> 3723 seconds) 
 * - "3m 5s" style (e.g., "3m 10s" -> 190 seconds)
 * - String numbers (e.g., "180" -> 180 seconds)
 * - Numbers (e.g., 180 -> 180 seconds)
 * - Whitespace/dash placeholders (e.g., "—", "", "   " -> 0)
 * - Invalid/null/undefined -> 0
 */
export function parseDurationToSeconds(input: unknown): number {
  if (typeof input === 'number') {
    return Math.max(0, Math.floor(input));
  }

  if (typeof input !== 'string') {
    return 0;
  }

  // Clean input: trim, collapse whitespace
  const cleaned = input.trim().replace(/\s+/g, ' ');
  
  // Handle empty, dash, or placeholder values
  if (!cleaned || cleaned === '—' || cleaned === '-' || cleaned === 'TBD') {
    return 0;
  }

  // Parse time format "H:MM:SS", "M:SS", or variations with spaces (check this FIRST)
  const timeMatch = cleaned.match(/^(\d+)\s*:\s*(\d+)(?:\s*:\s*(\d+))?$/);
  if (timeMatch) {
    const part1 = parseInt(timeMatch[1], 10);
    const part2 = parseInt(timeMatch[2], 10);
    const part3 = timeMatch[3] ? parseInt(timeMatch[3], 10) : 0;

    if (timeMatch[3]) {
      // H:MM:SS format
      return Math.max(0, part1 * 3600 + part2 * 60 + part3);
    } else {
      // M:SS format
      return Math.max(0, part1 * 60 + part2);
    }
  }

  // Parse "Xm Ys" format (e.g., "3m 10s", "2m", "45s")
  const minuteSecondMatch = cleaned.match(/^(?:(\d+)m\s*)?(?:(\d+)s)?$/i);
  if (minuteSecondMatch && (minuteSecondMatch[1] || minuteSecondMatch[2])) {
    const minutes = parseInt(minuteSecondMatch[1] || '0', 10);
    const seconds = parseInt(minuteSecondMatch[2] || '0', 10); 
    return Math.max(0, minutes * 60 + seconds);
  }

  // Try to parse as pure number (e.g., "180") - must be digits only
  if (/^\d+(\.\d+)?$/.test(cleaned)) {
    const asNumber = parseFloat(cleaned);
    if (!isNaN(asNumber) && asNumber >= 0) {
      return Math.floor(asNumber);
    }
  }

  // Handle edge cases like "bpm 120" or other text - extract first number
  const numberInText = cleaned.match(/(\d+)/);
  if (numberInText) {
    const extracted = parseInt(numberInText[1], 10);
    if (!isNaN(extracted) && extracted > 0) {
      // Only use if it seems like a reasonable duration (not BPM)
      if (extracted <= 3600) { // Max 1 hour as raw seconds
        return extracted;
      }
    }
  }

  // Default to 0 for unparseable input
  return 0;
}

/**
 * Format seconds into human-readable duration
 * Returns "H:MM:SS" if >= 3600 seconds, else "M:SS"
 * No leading zero hours, but leading zero minutes/seconds as needed
 * 
 * Examples:
 * - 65 -> "1:05"
 * - 3723 -> "1:02:03" 
 * - 0 -> "0:00"
 * - 7265 -> "2:01:05"
 */
export function formatSecondsHuman(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  
  if (seconds === 0) {
    return '0:00';
  }

  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainingSeconds = seconds % 60;

  if (hours > 0) {
    // H:MM:SS format (no leading zero on hours)
    return `${hours}:${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
  } else {
    // M:SS format (no leading zero on minutes)
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }
}

/**
 * Calculate total duration for a setlist from its songs
 * Handles priority: setlist_songs.duration_seconds > parse(duration_text) > songs.duration_seconds
 * Ensures unique counting by setlist_songs.id to avoid double-counting from joins
 */
export interface SetlistSongDuration {
  id: string; // setlist_songs.id for uniqueness
  duration_seconds?: number | null;
  duration_text?: string | null;
  songs?: {
    duration_seconds?: number | null;
  } | null;
}

export function calculateSetlistTotal(songs: SetlistSongDuration[]): number {
  // Use a Map to ensure unique counting by setlist_songs.id
  const uniqueSongs = new Map<string, SetlistSongDuration>();
  
  for (const song of songs) {
    if (song.id) {
      uniqueSongs.set(song.id, song);
    }
  }

  let totalSeconds = 0;

  uniqueSongs.forEach((song) => {
    // Priority order: setlist_songs.duration_seconds > parse(duration_text) > songs.duration_seconds > 0
    let songDuration = 0;

    if (typeof song.duration_seconds === 'number' && song.duration_seconds > 0) {
      songDuration = song.duration_seconds;
    } else if (song.duration_text) {
      songDuration = parseDurationToSeconds(song.duration_text);
    } else if (song.songs?.duration_seconds && song.songs.duration_seconds > 0) {
      songDuration = song.songs.duration_seconds;
    }

    totalSeconds += songDuration;
  });

  return totalSeconds;
}

/**
 * Format seconds into a concise summary for UI display
 * Rounds to nearest minute for brevity
 * Returns "TBD" for zero duration
 * 
 * Examples:
 * - 0 -> "TBD"
 * - 65 -> "1m" 
 * - 3723 -> "1h 02m"
 * - 7265 -> "2h 01m"
 */
export function formatDurationSummary(seconds: number): string {
  if (seconds === 0) return 'TBD';
  
  // Round to nearest minute
  const totalMinutes = Math.round(seconds / 60);
  const hours = Math.floor(totalMinutes / 60);
  const remainingMinutes = totalMinutes % 60;

  if (hours > 0) {
    return `${hours}h ${remainingMinutes.toString().padStart(2, '0')}m`;
  }
  return `${totalMinutes}m`;
}
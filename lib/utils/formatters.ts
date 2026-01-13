export function formatPhoneNumber(value: string): string {
  const phone = value.replace(/\D/g, '');
  const match = phone.match(/^(\d{0,3})(\d{0,3})(\d{0,4})$/);

  if (!match) return value;

  const [, area, prefix, line] = match;

  if (line) {
    return `(${area}) ${prefix}-${line}`;
  } else if (prefix) {
    return `(${area}) ${prefix}`;
  } else if (area) {
    return `(${area}`;
  }

  return '';
}

export function capitalizeWords(str: string): string {
  return str.replace(/\b\w/g, (char) => char.toUpperCase());
}

export function getInitials(name: string): string {
  const words = name.trim().split(/\s+/);
  if (words.length === 1) {
    return words[0].substring(0, 2).toUpperCase();
  }
  return words
    .map((word) => word[0])
    .join('')
    .toUpperCase()
    .substring(0, 3);
}

export function formatDate(date: string | Date): string {
  const d = new Date(date);
  return new Intl.DateTimeFormat('en-US', {
    weekday: 'long',
    month: 'short',
    day: 'numeric',
  }).format(d);
}

export function formatTime(date: string | Date): string {
  // Handle time-only strings like "19:00" or "14:30"
  if (typeof date === 'string' && /^\d{1,2}:\d{2}(:\d{2})?$/.test(date)) {
    // Parse time string (HH:MM or HH:MM:SS)
    const [hours, minutes] = date.split(':').map(Number);
    const d = new Date();
    d.setHours(hours, minutes, 0, 0);
    return new Intl.DateTimeFormat('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
    }).format(d);
  }

  const d = new Date(date);
  if (isNaN(d.getTime())) {
    return 'Time TBD';
  }

  return new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(d);
}

export function formatTimeRange(start: string | Date, end: string | Date): string {
  if (!start || !end) return 'Time TBD';
  return `${formatTime(start)} – ${formatTime(end)}`;
}

/**
 * Format duration in seconds to HH:MM:SS or MM:SS format
 * Returns H:MM:SS if >= 1 hour else MM:SS
 */
export function formatDuration(totalSeconds: number): string {
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
    // MM:SS format (no leading zero on minutes)
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }
}

interface ShareSong {
  title: string;
  artist?: string;
  tuning?: string;
  durationSec?: number;
  bpm?: number;
}

interface ShareSetlist {
  name: string;
  songs: ShareSong[];
}

/**
 * Build formatted text for sharing a setlist
 * Format:
 * Setlist: <name>
 * Songs: <count> • Total Duration: <HH:MM:SS or MM:SS>
 * 
 * <Song Title>
 * <Artist/Band>
 * Tuning: <tuning or "standard"> • <MM:SS> • <BPM> BPM
 */
export function buildShareText(setlist: ShareSetlist): string {
  const songCount = setlist.songs.length;
  
  // Calculate total duration from songs that have durationSec
  const totalDuration = setlist.songs.reduce((sum, song) => {
    return sum + (song.durationSec || 0);
  }, 0);
  
  // Build header with two blank lines after
  const header = `Setlist: ${setlist.name}
Songs: ${songCount} • Total Duration: ${formatDuration(totalDuration)}


`;
  
  // Build song blocks
  const songBlocks = setlist.songs.map(song => {
    const tuning = song.tuning || 'standard';
    const duration = song.durationSec ? formatDuration(song.durationSec) : '0:00';
    const bpm = song.bpm ? `${song.bpm} BPM` : '— BPM';
    
    // Song block: title, artist (or blank line), tuning line
    const lines = [
      song.title,
      song.artist || '', // artist line or blank
      `Tuning: ${tuning} • ${duration} • ${bpm}`
    ];
    
    return lines.join('\n');
  });
  
  // Join everything with blank lines between song blocks
  const result = header + songBlocks.join('\n\n');
  
  // Trim trailing spaces and remove any extra blank lines at the end
  return result.replace(/\s+$/, '');
}

import { createClient } from './client';
import { calculateSetlistTotal, SetlistSongDuration } from '@/lib/time/duration';

export interface SetlistWithTotal {
  id: string;
  name: string;
  total_duration: number; // Database value (may be incorrect)
  calculated_duration: number; // Correctly calculated value
  created_at: string;
  updated_at: string;
  song_count: number;
}

export interface DetailedSetlistSong extends SetlistSongDuration {
  id: string;
  position: number;
  bmp?: number;
  tuning?: string;
  duration_seconds?: number | null;
  songs?: {
    id: string;
    title: string;
    artist: string;
    bmp?: number;
    tuning?: string;
    duration_seconds?: number | null;
  } | null;
}

/**
 * Fetch setlists with correctly calculated durations using client-side parsing
 * This bypasses the database trigger limitations and ensures accurate totals
 */
export async function getSetlistsWithTotals(bandId: string): Promise<SetlistWithTotal[]> {
  const supabase = createClient();

  const { data: setlists, error } = await supabase
    .from('setlists')
    .select(`
      id,
      name,
      total_duration,
      created_at,
      updated_at,
      setlist_songs (
        id,
        duration_seconds,
        songs (
          duration_seconds
        )
      )
    `)
    .eq('band_id', bandId)
    .order('created_at', { ascending: false });

  if (error) {
    console.error('Error fetching setlists with totals:', error);
    throw new Error('Failed to fetch setlists');
  }

  if (!setlists) return [];

  return setlists.map((setlist) => {
    const songs: SetlistSongDuration[] = setlist.setlist_songs?.map((song: any) => ({
      id: song.id,
      duration_seconds: song.duration_seconds,
      duration_text: null, // No duration_text field in current schema
      songs: song.songs
    })) || [];

    const calculated_duration = calculateSetlistTotal(songs);
    const song_count = setlist.setlist_songs?.length || 0;

    return {
      id: setlist.id,
      name: setlist.name,
      total_duration: setlist.total_duration || 0,
      calculated_duration,
      created_at: setlist.created_at,
      updated_at: setlist.updated_at,
      song_count
    };
  });
}

/**
 * Fetch detailed setlist data with correctly calculated duration
 * For use in setlist detail pages where song-level data is needed
 */
export async function getDetailedSetlistWithTotal(setlistId: string, bandId: string) {
  const supabase = createClient();

  const { data: setlist, error } = await supabase
    .from('setlists')
    .select(`
      id,
      name,
      total_duration,
      created_at,
      updated_at,
      setlist_songs (
        id,
        position,
        bpm,
        tuning,
        duration_seconds,
        songs!inner (
          id,
          title,
          artist,
          bpm,
          tuning,
          duration_seconds
        )
      )
    `)
    .eq('id', setlistId)
    .eq('band_id', bandId)
    .single();

  if (error) {
    console.error('Error fetching detailed setlist:', error);
    throw new Error('Failed to fetch setlist details');
  }

  if (!setlist) return null;

  const songs: DetailedSetlistSong[] = setlist.setlist_songs?.map((song: any) => ({
    id: song.id,
    position: song.position,
    bpm: song.bpm,
    tuning: song.tuning,
    duration_seconds: song.duration_seconds,
    duration_text: null, // No duration_text field in current schema
    songs: song.songs
  })) || [];

  // Sort by position
  songs.sort((a, b) => a.position - b.position);

  const calculated_duration = calculateSetlistTotal(songs);

  return {
    id: setlist.id,
    name: setlist.name,
    total_duration: setlist.total_duration || 0,
    calculated_duration,
    created_at: setlist.created_at,
    updated_at: setlist.updated_at,
    songs
  };
}

/**
 * Update database total_duration with correctly calculated value
 * Call this after song changes to sync the database with the correct calculation
 */
export async function syncSetlistDuration(setlistId: string): Promise<boolean> {
  const supabase = createClient();

  try {
    // Fetch song data for calculation
    const { data: setlistSongs, error: fetchError } = await supabase
      .from('setlist_songs')
      .select(`
        id,
        duration_seconds,
        songs (
          duration_seconds
        )
      `)
      .eq('setlist_id', setlistId);

    if (fetchError || !setlistSongs) {
      console.error('Error fetching setlist songs for sync:', fetchError);
      return false;
    }

    // Calculate correct total  
    const songs: SetlistSongDuration[] = setlistSongs.map((song: any) => ({
      id: song.id,
      duration_seconds: song.duration_seconds,
      duration_text: null, // No duration_text field in current schema
      songs: song.songs
    }));

    const calculated_duration = calculateSetlistTotal(songs);

    // Update database
    const { error: updateError } = await supabase
      .from('setlists')
      .update({ 
        total_duration: calculated_duration,
        updated_at: new Date().toISOString()
      })
      .eq('id', setlistId);

    if (updateError) {
      console.error('Error updating setlist duration:', updateError);
      return false;
    }

    return true;
  } catch (error) {
    console.error('Exception in syncSetlistDuration:', error);
    return false;
  }
}
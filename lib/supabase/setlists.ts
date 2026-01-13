import { createClient } from './client';

export interface SetlistOption {
  id: string;
  name: string;
}

/**
 * Fetch all setlists for a band, excluding the current one
 */
export async function listSetlists(bandId: string, excludeSetlistId?: string): Promise<SetlistOption[]> {
  const supabase = createClient();

  let query = supabase
    .from('setlists')
    .select('id, name')
    .eq('band_id', bandId)
    .order('name');

  if (excludeSetlistId) {
    query = query.neq('id', excludeSetlistId);
  }

  const { data, error } = await query;

  if (error) {
    console.error('Error fetching setlists:', error);
    throw new Error('Failed to fetch setlists');
  }

  return data || [];
}

/**
 * Copy a song from one setlist to another
 */
export async function copySongToSetlist(
  songId: string,
  fromSetlistId: string,
  toSetlistId: string
): Promise<void> {
  const supabase = createClient();

  try {
    // First, get the song data from the source setlist
    const { data: sourceSetlistSong, error: fetchError } = await supabase
      .from('setlist_songs')
      .select(`
        song_id,
        bpm,
        tuning,
        duration_seconds,
        songs!inner (
          title,
          artist
        )
      `)
      .eq('id', songId)
      .eq('setlist_id', fromSetlistId)
      .single();

    if (fetchError) {
      console.error('Error fetching source song:', fetchError);
      throw new Error('Failed to fetch song details');
    }

    if (!sourceSetlistSong) {
      throw new Error('Song not found in source setlist');
    }

    // Get the next position in the target setlist
    const { data: maxPositionData, error: positionError } = await supabase
      .from('setlist_songs')
      .select('position')
      .eq('setlist_id', toSetlistId)
      .order('position', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (positionError) {
      console.error('Error getting max position:', positionError);
      throw new Error('Failed to determine position for new song');
    }

    const nextPosition = (maxPositionData?.position || 0) + 1;

    // Insert the song into the target setlist
    const { error: insertError } = await supabase
      .from('setlist_songs')
      .insert({
        setlist_id: toSetlistId,
        song_id: sourceSetlistSong.song_id,
        position: nextPosition,
        bpm: sourceSetlistSong.bpm,
        tuning: sourceSetlistSong.tuning,
        duration_seconds: sourceSetlistSong.duration_seconds,
      });

    if (insertError) {
      console.error('Error copying song to setlist:', insertError);
      // Check if it's a duplicate song error
      if (insertError.code === '23505' && insertError.message?.includes('setlist_songs_setlist_id_song_id_key')) {
        const songs = sourceSetlistSong.songs as { title?: string; artist?: string } | { title?: string; artist?: string }[];
        const songTitle = Array.isArray(songs) ? songs[0]?.title : songs?.title;
        throw new Error(`"${songTitle || 'Song'}" is already in the target setlist`);
      }
      throw new Error('Failed to copy song to setlist');
    }
  } catch (error) {
    // Re-throw our custom errors, wrap others
    if (error instanceof Error) {
      throw error;
    }
    throw new Error('Failed to copy song');
  }
}

/**
 * Get setlist name by ID
 */
export async function getSetlistById(setlistId: string): Promise<SetlistOption | null> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from('setlists')
    .select('id, name')
    .eq('id', setlistId)
    .single();

  if (error) {
    console.error('Error fetching setlist:', error);
    return null;
  }

  return data;
}

/**
 * Delete result interface for comprehensive error reporting
 */
export interface DeleteResult {
  success: boolean;
  error?: {
    message: string;
    code?: string;
    status: number;
    isRLSIssue?: boolean;
  };
}

/**
 * Delete a setlist with comprehensive error handling and RLS validation
 */
export async function deleteSetlist(setlistId: string): Promise<DeleteResult> {
  const supabase = createClient();

  try {
    // Pre-check: Verify setlist exists and user has access
    const { data: existingSetlist, error: checkError } = await supabase
      .from('setlists')
      .select('id, name, band_id')
      .eq('id', setlistId)
      .maybeSingle();

    if (checkError) {
      console.error('Pre-check error:', checkError);
      return {
        success: false,
        error: {
          message: `Pre-check failed: ${checkError.message}`,
          code: checkError.code,
          status: 500,
          isRLSIssue: checkError.code === 'PGRST116' || checkError.code === '42501'
        }
      };
    }

    if (!existingSetlist) {
      return {
        success: false,
        error: {
          message: 'Setlist not found or you do not have permission to delete it',
          code: 'NOT_FOUND',
          status: 404,
          isRLSIssue: true
        }
      };
    }

    // Delete the setlist - CASCADE will handle setlist_songs automatically
    const { error: deleteError, status } = await supabase
      .from('setlists')
      .delete()
      .eq('id', setlistId);

    if (deleteError) {
      console.error('Delete setlist error:', deleteError);
      const statusCode = status || 500;
      const isRLSIssue = statusCode === 401 || statusCode === 403 || statusCode === 404 ||
                         deleteError.code === 'PGRST116' || deleteError.code === '42501';
      
      // Provide specific error messages based on common failure cases
      let message = deleteError.message || 'Failed to delete setlist';
      if (isRLSIssue) {
        message = "You don't have permission to delete this setlist";
      } else if (deleteError.code === '23503') {
        message = 'Cannot delete setlist - it may be referenced by other records';
      }
      
      return {
        success: false,
        error: {
          message,
          code: deleteError.code || 'DELETE_FAILED',
          status: statusCode,
          isRLSIssue
        }
      };
    }

    return { success: true };
  } catch (error) {
    console.error('Exception in deleteSetlist:', error);
    return {
      success: false,
      error: {
        message: error instanceof Error ? error.message : 'Unknown error occurred',
        code: 'EXCEPTION',
        status: 500
      }
    };
  }
}

/**
 * Update setlist song tuning with error handling
 */
export async function updateSetlistSongTuning(setlistSongId: string, tuning: string): Promise<void> {
  if (!setlistSongId) {
    throw new Error('MISSING_ID');
  }

  const supabase = createClient();

  const { error, status } = await supabase
    .from('setlist_songs')
    .update({ tuning })
    .eq('id', setlistSongId);

  if (error) {
    console.error('Error updating setlist song tuning:', error);
    throw new Error(`UPDATE_TUNING_FAILED:${status}:${error.code}:${error.message}`);
  }
}

/**
 * Delete a song from a setlist with comprehensive error handling
 */
export async function deleteSetlistSong(
  setlistSongId: string,
  expectedSetlistId: string
): Promise<DeleteResult> {
  const supabase = createClient();

  try {
    // Pre-check: Verify ownership and get current row
    const { data: existingRow, error: checkError } = await supabase
      .from('setlist_songs')
      .select('id, setlist_id')
      .eq('id', setlistSongId)
      .maybeSingle();

    if (checkError) {
      console.error('Pre-check error:', checkError);
      return {
        success: false,
        error: {
          message: `Pre-check failed: ${checkError.message}`,
          code: checkError.code,
          status: 500,
          isRLSIssue: checkError.code === 'PGRST116' || checkError.code === '42501'
        }
      };
    }

    if (!existingRow) {
      return {
        success: false,
        error: {
          message: 'Setlist song not found',
          code: 'NOT_FOUND',
          status: 404
        }
      };
    }

    // Verify setlist ownership
    if (existingRow.setlist_id !== expectedSetlistId) {
      return {
        success: false,
        error: {
          message: 'Setlist mismatch - unauthorized access',
          code: 'SETLIST_MISMATCH',
          status: 403
        }
      };
    }

    // Delete the row - DO NOT use .single() after DELETE
    const { error: deleteError, status } = await supabase
      .from('setlist_songs')
      .delete()
      .eq('id', setlistSongId);

    if (deleteError) {
      console.error('Delete error:', deleteError);
      const statusCode = status || 500;
      const isRLSIssue = statusCode === 401 || statusCode === 403 || statusCode === 404 ||
                         deleteError.code === 'PGRST116' || deleteError.code === '42501';
      
      return {
        success: false,
        error: {
          message: deleteError.message || 'Failed to delete setlist song',
          code: deleteError.code || 'DELETE_FAILED',
          status: statusCode,
          isRLSIssue
        }
      };
    }

    return { success: true };
  } catch (error) {
    console.error('Exception in deleteSetlistSong:', error);
    return {
      success: false,
      error: {
        message: error instanceof Error ? error.message : 'Unknown error',
        code: 'EXCEPTION',
        status: 500
      }
    };
  }
}
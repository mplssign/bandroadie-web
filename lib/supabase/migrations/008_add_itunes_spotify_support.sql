-- Migration: Add iTunes and Spotify support to songs table
-- Add album artwork and iTunes/Spotify IDs

-- Add new columns to songs table
ALTER TABLE songs 
ADD COLUMN album_artwork TEXT,
ADD COLUMN itunes_id TEXT,
ADD COLUMN spotify_id TEXT;

-- Remove old MusicBrainz column since we're switching to iTunes/Spotify
ALTER TABLE songs DROP COLUMN IF EXISTS musicbrainz_id;
ALTER TABLE songs DROP COLUMN IF EXISTS deezer_id;

-- Add index for iTunes ID for faster lookups
CREATE INDEX IF NOT EXISTS idx_songs_itunes_id ON songs(itunes_id);

-- Add index for Spotify ID for faster lookups  
CREATE INDEX IF NOT EXISTS idx_songs_spotify_id ON songs(spotify_id);

-- Update the unique constraint to still use title + artist
-- (This should already exist from previous migrations)
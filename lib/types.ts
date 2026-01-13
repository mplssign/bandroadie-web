export interface User {
  id: string;
  email: string;
  first_name?: string;
  last_name?: string;
  phone?: string;
  address?: string;
  city?: string;
  zip?: string;
  birthday?: string;
  roles?: string[];
  created_at: string;
  updated_at: string;
  profile_completed: boolean;
}

export interface Band {
  id: string;
  name: string;
  image_url?: string;
  created_by: string;
  created_at: string;
  updated_at: string;
}

export interface BandMember {
  id: string;
  band_id: string;
  user_id: string;
  joined_at: string;
  is_active: boolean;
  user?: User;
  band?: Band;
}

export interface Invite {
  id: string;
  band_id: string;
  email: string;
  invited_by: string;
  status: 'pending' | 'sent' | 'accepted' | 'expired' | 'error';
  token: string;
  created_at: string;
  expires_at: string;
}

export interface Rehearsal {
  id: string;
  band_id: string;
  name: string;
  location: string;
  start_time: string;
  end_time: string;
  notes?: string;
  created_at: string;
  updated_at: string;
}

export interface Gig {
  id: string;
  band_id: string;
  name: string;
  venue: string;
  city: string;
  date: string;
  start_time: string;
  end_time?: string;
  setlist_id?: string;
  is_potential: boolean;
  optional_member_ids?: string[] | null;
  member_responses?: GigMemberResponse[] | null;
  notes?: string;
  created_at: string;
  updated_at: string;
}

export interface GigMemberResponse {
  id?: string;
  gig_id?: string;
  band_member_id: string;
  response: 'yes' | 'no';
  responded_at?: string;
  band_members?: {
    id: string;
    user_id: string;
    users?: {
      id: string;
      first_name?: string | null;
      last_name?: string | null;
    } | null;
  } | null;
}

export interface Setlist {
  id: string;
  band_id: string;
  name: string;
  is_catalog?: boolean;
  setlist_type?: 'regular' | 'catalog';
  songs: Song[];
  created_at: string;
  updated_at: string;
}

export interface Song {
  id: string;
  title: string;
  artist?: string;
  duration?: number;
  notes?: string;
  order: number;
}

// Tuning types for guitar tunings (ordered by popularity)
export type TuningType = 'standard' | 'half_step' | 'drop_d' | 'full_step' | 'drop_c' | 'drop_b' | 'dadgad' | 'open_g' | 'open_d' | 'open_e';

// Tuning constants for native select
export const STANDARD = 'standard' as const;
export const DROP_D = 'drop_d' as const;
export const HALF_STEP = 'half_step' as const;
export const FULL_STEP = 'full_step' as const;

// Tuning options for dropdowns
export const TUNING_OPTIONS = [
  { value: STANDARD, label: 'Standard' },
  { value: DROP_D, label: 'Drop D' },
  { value: HALF_STEP, label: 'Half-Step' },
  { value: FULL_STEP, label: 'Full-Step' },
  { value: 'drop_c' as const, label: 'Drop C' },
  { value: 'drop_b' as const, label: 'Drop B' },
  { value: 'dadgad' as const, label: 'DADGAD' },
  { value: 'open_g' as const, label: 'Open G' },
  { value: 'open_d' as const, label: 'Open D' },
  { value: 'open_e' as const, label: 'Open E' },
] as const;

// Music song interface for search results
export interface MusicSong {
  id: string;
  title: string;
  artist: string;
  bpm?: number;
  tuning?: TuningType;
  duration_seconds?: number;
  album_artwork?: string;
  is_live?: boolean;
}

// Setlist song interface for junction table
export interface SetlistSong {
  id: string;
  setlist_id?: string;
  song_id: string;
  position: number;
  bpm?: number;
  tuning?: TuningType;
  duration_seconds?: number;
  songs?: {
    id: string;
    title: string;
    artist?: string;
    bpm?: number;
    tuning?: TuningType;
    duration_seconds?: number;
    is_live?: boolean;
    album_artwork?: string;
  };
}

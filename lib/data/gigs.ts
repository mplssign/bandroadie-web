/**
 * Unified gig data fetching utilities for Calendar and Dashboard consistency
 */

import { createClient } from '@/lib/supabase/client';

export interface GigData {
  id: string;
  name: string;
  date: string; // YYYY-MM-DD format
  start_time?: string;
  end_time?: string;
  location?: string;
  band_id: string;
  is_potential: boolean;
  event_type: string;
  setlist_id?: string | null;
  setlist_name?: string | null;
  optional_member_ids?: string[] | null;
  member_responses?: any[] | null;
  setlists?: {
    id: string;
    name: string;
  } | null;
}

export interface GigFilters {
  bandId: string;
  includePotential?: boolean;
  onlyPotential?: boolean; // NEW: Filter to ONLY potential gigs
  windowDays?: number; // Number of days in the future to include (null = all future)
  includeAll?: boolean; // For Calendar view - includes past events too
}

/**
 * Get current date in YYYY-MM-DD format using proper UTC handling
 */
export function getTodayUTC(): string {
  const now = new Date();
  // Use UTC to avoid timezone issues
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Unified gig fetcher that both Calendar and Dashboard can use
 */
export async function fetchBandGigs(filters: GigFilters): Promise<{
  data: GigData[] | null;
  error: any;
}> {
  const supabase = createClient();
  const {
    bandId,
    includePotential = true,
    onlyPotential = false,
    windowDays,
    includeAll = false,
  } = filters;

  let query = supabase
    .from('gigs')
    .select(
      `
      *,
      setlists (
        id,
        name
      )
    `,
    )
    .eq('band_id', bandId);

  // Apply date filtering only if not including all events (Calendar needs all)
  if (!includeAll) {
    const todayUTC = getTodayUTC();
    query = query.gte('date', todayUTC);

    // Apply window limit if specified
    if (windowDays && windowDays > 0) {
      const futureDate = new Date();
      futureDate.setUTCDate(futureDate.getUTCDate() + windowDays);
      const futureDateStr = `${futureDate.getUTCFullYear()}-${String(futureDate.getUTCMonth() + 1).padStart(2, '0')}-${String(futureDate.getUTCDate()).padStart(2, '0')}`;
      query = query.lte('date', futureDateStr);
    }
  }

  // Filter by event type if needed
  query = query.eq('event_type', 'gig');

  // Apply potential filter
  if (onlyPotential) {
    // Filter to ONLY potential gigs
    query = query.eq('is_potential', true);
  } else if (includePotential === false) {
    // Filter to ONLY confirmed gigs
    query = query.eq('is_potential', false);
  }
  // If includePotential === true and onlyPotential === false, include both

  const { data, error } = await query.order('date', { ascending: true });

  if (error) {
    console.error('Error fetching gigs:', error);
    return { data: null, error };
  }

  // Transform data to include nested setlist info
  const transformedData: GigData[] = (data || []).map((gig) => ({
    ...gig,
    setlist_name: gig.setlists?.name || null,
  }));

  return { data: transformedData, error: null };
}

/**
 * Get potential gigs only (for Dashboard Potential Gig card)
 */
export async function fetchPotentialGigs(
  bandId: string,
  windowDays?: number,
): Promise<{
  data: GigData[] | null;
  error: any;
}> {
  return fetchBandGigs({
    bandId,
    onlyPotential: true, // Only get potential gigs
    windowDays: windowDays || 120, // Default to 4 months
    includeAll: false,
  });
}

/**
 * Get confirmed upcoming gigs only (for Dashboard Upcoming Gigs list)
 */
export async function fetchUpcomingGigs(
  bandId: string,
  limit: number = 5,
  windowDays?: number,
): Promise<{
  data: GigData[] | null;
  error: any;
}> {
  const result = await fetchBandGigs({
    bandId,
    includePotential: false,
    windowDays: windowDays || 120,
    includeAll: false,
  });

  if (result.data && limit > 0) {
    result.data = result.data.slice(0, limit);
  }

  return result;
}

/**
 * Get all gigs for Calendar view (no filtering except band)
 */
export async function fetchAllGigsForCalendar(bandId: string): Promise<{
  data: GigData[] | null;
  error: any;
}> {
  return fetchBandGigs({
    bandId,
    includePotential: true,
    includeAll: true, // This tells the fetcher to include all dates
  });
}

/**
 * Filter potential gigs from a gig array
 */
export function filterPotentialGigs(gigs: GigData[]): GigData[] {
  return gigs.filter((gig) => gig.is_potential === true);
}

/**
 * Filter confirmed gigs from a gig array
 */
export function filterConfirmedGigs(gigs: GigData[]): GigData[] {
  return gigs.filter((gig) => gig.is_potential === false);
}

/**
 * Filter future gigs (used when we have all gigs and want to filter client-side)
 */
export function filterFutureGigs(gigs: GigData[]): GigData[] {
  const todayUTC = getTodayUTC();
  return gigs.filter((gig) => gig.date >= todayUTC);
}

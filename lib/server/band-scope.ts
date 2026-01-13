/**
 * Server-side band scoping utilities
 * Provides helpers for validating band access and filtering queries by band
 */

import { createClient } from '@/lib/supabase/server';
import { cookies } from 'next/headers';
import type { SupabaseClient } from '@supabase/supabase-js';

const CURRENT_BAND_COOKIE = 'br_current_band_id';

/**
 * Get the current band ID from cookies
 * Falls back to user's first band if no cookie is set
 */
export async function getCurrentBandId(): Promise<string | null> {
  const cookieStore = await cookies();
  const bandIdFromCookie = cookieStore.get(CURRENT_BAND_COOKIE)?.value;

  if (bandIdFromCookie) {
    return bandIdFromCookie;
  }

  // Fallback: get user's first band
  // Get user ID from our custom cookie
  const accessToken = cookieStore.get('sb-access-token')?.value;
  if (!accessToken) return null;

  const payload = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64').toString());
  const userId = payload.sub;

  const supabase = await createClient();
  let supportsIsActive = true;
  let membershipResult = await supabase
    .from('band_members')
    .select('id, band_id, is_active')
    .eq('user_id', userId)
    .order('joined_at', { ascending: true })
    .limit(1)
    .maybeSingle();

  if (membershipResult.error?.code === '42703') {
    supportsIsActive = false;
    membershipResult = await supabase
      .from('band_members')
      .select('id, band_id')
      .eq('user_id', userId)
      .order('joined_at', { ascending: true })
      .limit(1)
      .maybeSingle();
  }

  if (membershipResult.error) {
    console.warn(
      '[band-scope] Failed to load membership in getCurrentBandId:',
      membershipResult.error,
    );
    return null;
  }

  const membership = membershipResult.data as {
    id: string;
    band_id: string;
    is_active?: boolean | null;
  } | null;

  if (!membership) {
    return null;
  }

  if (supportsIsActive && membership.is_active === false) {
    const { error: reactivateError } = await supabase
      .from('band_members')
      .update({ is_active: true })
      .eq('id', membership.id)
      .select('id')
      .maybeSingle();

    if (reactivateError) {
      console.warn('[band-scope] Failed to reactivate membership in getCurrentBandId:', {
        bandId: membership.band_id,
        membershipId: membership.id,
        reactivateError,
      });
    }
  }

  return membership.band_id;
}

/**
 * Set the current band ID in cookies
 */
export async function setCurrentBandId(bandId: string): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.set(CURRENT_BAND_COOKIE, bandId, {
    path: '/',
    maxAge: 60 * 60 * 24 * 365, // 1 year
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
  });
}

/**
 * Verify that the current user is a member of the specified band
 * Throws an error if not authorized
 */
export async function requireBandMembership(bandId: string): Promise<void> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get('sb-access-token')?.value;

  if (!accessToken) {
    throw new Error('Unauthorized: No user session');
  }

  const payload = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64').toString());
  const userId = payload.sub;

  const supabase = await createClient();
  let supportsIsActive = true;
  let membershipResult = await supabase
    .from('band_members')
    .select('id, is_active')
    .eq('band_id', bandId)
    .eq('user_id', userId)
    .maybeSingle();

  if (membershipResult.error?.code === '42703') {
    supportsIsActive = false;
    membershipResult = await supabase
      .from('band_members')
      .select('id')
      .eq('band_id', bandId)
      .eq('user_id', userId)
      .maybeSingle();
  }

  if (membershipResult.error || !membershipResult.data) {
    throw new Error(`Forbidden: User is not a member of band ${bandId}`);
  }

  const membership = membershipResult.data as { id: string; is_active?: boolean | null };

  if (supportsIsActive && membership.is_active === false) {
    const { error: reactivateError } = await supabase
      .from('band_members')
      .update({ is_active: true })
      .eq('id', membership.id)
      .select('id')
      .maybeSingle();

    if (reactivateError) {
      console.warn('[band-scope] Failed to reactivate membership in requireBandMembership:', {
        bandId,
        membershipId: membership.id,
        reactivateError,
      });
    }
  }
}

/**
 * Get user's band membership status
 */
export async function getUserBandMembership(bandId: string): Promise<boolean> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get('sb-access-token')?.value;

  if (!accessToken) return false;

  const payload = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64').toString());
  const userId = payload.sub;

  const supabase = await createClient();
  let supportsIsActive = true;
  let membershipResult = await supabase
    .from('band_members')
    .select('id, is_active')
    .eq('band_id', bandId)
    .eq('user_id', userId)
    .maybeSingle();

  if (membershipResult.error?.code === '42703') {
    supportsIsActive = false;
    membershipResult = await supabase
      .from('band_members')
      .select('id')
      .eq('band_id', bandId)
      .eq('user_id', userId)
      .maybeSingle();
  }

  if (membershipResult.error || !membershipResult.data) {
    return false;
  }

  const membership = membershipResult.data as { id: string; is_active?: boolean | null };

  if (supportsIsActive && membership.is_active === false) {
    const { error } = await supabase
      .from('band_members')
      .update({ is_active: true })
      .eq('id', membership.id)
      .select('id')
      .maybeSingle();

    if (error) {
      console.warn('[band-scope] Failed to reactivate membership in getUserBandMembership:', {
        bandId,
        membershipId: membership.id,
        error,
      });
    }
  }

  return true;
}

/**
 * Create a query builder that automatically scopes to a band
 * Usage: const query = await withBandScope(supabase, bandId, 'gigs');
 */
export function withBandScope<T extends string>(
  supabase: SupabaseClient,
  bandId: string,
  table: T,
) {
  return supabase.from(table).select('*').eq('band_id', bandId);
}

/**
 * Validate that a resource belongs to the specified band
 */
export async function requireResourceInBand(
  table: string,
  resourceId: string,
  bandId: string,
): Promise<void> {
  const supabase = await createClient();

  console.log('requireResourceInBand check:', { table, resourceId, bandId });

  const { data, error } = await supabase
    .from(table)
    .select('band_id')
    .eq('id', resourceId)
    .single();

  console.log('requireResourceInBand result:', { data, error });

  if (error || !data) {
    console.error('Resource not found in requireResourceInBand:', { 
      table, 
      resourceId, 
      bandId, 
      error: error?.message, 
      code: error?.code 
    });
    throw new Error(`Resource not found: ${table}/${resourceId}`);
  }

  if (data.band_id !== bandId) {
    console.error('Resource band mismatch:', { 
      resourceId, 
      expectedBandId: bandId, 
      actualBandId: data.band_id 
    });
    throw new Error(`Forbidden: Resource ${resourceId} does not belong to band ${bandId}`);
  }

  console.log('requireResourceInBand passed:', { resourceId, bandId });
}

import type { Session } from '@supabase/supabase-js';

const SESSION_SYNC_ENDPOINT = '/api/auth/session';

export function sanitizeAppPath(candidate: string | null | undefined): string | null {
  if (!candidate) return null;
  if (!candidate.startsWith('/')) return null;
  if (candidate.startsWith('//')) return null;
  return candidate;
}

export async function syncSessionToCookies(session: Session | null) {
  if (!session) {
    throw new Error('no-session');
  }

  const response = await fetch(SESSION_SYNC_ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    credentials: 'include',
    body: JSON.stringify({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
    }),
  });

  if (!response.ok) {
    const { error } = await response.json().catch(() => ({ error: 'unknown-error' }));
    throw new Error(typeof error === 'string' ? error : 'session-sync-failed');
  }
}

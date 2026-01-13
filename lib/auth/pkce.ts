/**
 * PKCE (Proof Key for Code Exchange) utilities for tab-independent auth flow
 *
 * Stores code_verifier in HTTP-only cookies keyed by state parameter
 * to enable magic links opened in new tabs to complete authentication
 */

import { cookies } from 'next/headers';

const PKCE_COOKIE_PREFIX = 'pkce_';
const PKCE_TTL_SECONDS = 900; // 15 minutes
const IS_PRODUCTION = process.env.NODE_ENV === 'production';

/**
 * Generate cryptographically random string for PKCE
 */
function generateRandomString(length: number): string {
  const array = new Uint8Array(length);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/**
 * Generate SHA-256 hash and base64url encode
 */
async function sha256(plain: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(plain);
  const hash = await crypto.subtle.digest('SHA-256', data);

  // Convert to base64url
  const hashArray = Array.from(new Uint8Array(hash));
  const base64 = btoa(String.fromCharCode.apply(null, hashArray as any));

  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

/**
 * Create a new PKCE session and store code_verifier in HTTP-only cookie
 *
 * @returns {state, code_verifier, code_challenge} for OAuth flow
 */
export async function createPkceSession(): Promise<{
  state: string;
  code_verifier: string;
  code_challenge: string;
}> {
  const state = generateRandomString(32);
  const code_verifier = generateRandomString(64);
  const code_challenge = await sha256(code_verifier);

  // Store code_verifier in HTTP-only cookie keyed by state
  const cookieStore = cookies();
  cookieStore.set({
    name: `${PKCE_COOKIE_PREFIX}${state}`,
    value: code_verifier,
    httpOnly: true,
    secure: IS_PRODUCTION,
    sameSite: 'lax',
    path: '/',
    maxAge: PKCE_TTL_SECONDS,
  });

  console.log('[PKCE] Created session:', {
    state,
    hasVerifier: !!code_verifier,
    cookieName: `${PKCE_COOKIE_PREFIX}${state}`,
  });

  return {
    state,
    code_verifier,
    code_challenge,
  };
}

/**
 * Read code_verifier from HTTP-only cookie using state parameter
 *
 * @param state - OAuth state parameter from callback URL
 * @returns code_verifier or null if not found/expired
 */
export function readPkceVerifier(state: string): string | null {
  const cookieStore = cookies();
  const cookieName = `${PKCE_COOKIE_PREFIX}${state}`;
  const value = cookieStore.get(cookieName)?.value || null;

  console.log('[PKCE] Read verifier:', {
    state,
    cookieName,
    found: !!value,
  });

  return value;
}

/**
 * Delete PKCE session cookie after successful auth
 *
 * @param state - OAuth state parameter to cleanup
 */
export function deletePkceSession(state: string): void {
  const cookieStore = cookies();
  const cookieName = `${PKCE_COOKIE_PREFIX}${state}`;

  cookieStore.set({
    name: cookieName,
    value: '',
    httpOnly: true,
    secure: IS_PRODUCTION,
    sameSite: 'lax',
    path: '/',
    maxAge: 0,
  });

  console.log('[PKCE] Deleted session:', { state, cookieName });
}

/**
 * Cleanup expired PKCE sessions (optional background job)
 * This is handled automatically by cookie expiration, but can be called explicitly
 */
export function cleanupExpiredSessions(): void {
  const cookieStore = cookies();
  const allCookies = cookieStore.getAll();

  let cleaned = 0;
  for (const cookie of allCookies) {
    if (cookie.name.startsWith(PKCE_COOKIE_PREFIX)) {
      cookieStore.delete(cookie.name);
      cleaned++;
    }
  }

  if (cleaned > 0) {
    console.log('[PKCE] Cleaned up sessions:', cleaned);
  }
}

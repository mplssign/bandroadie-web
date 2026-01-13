/**
 * Site configuration and URL helpers for auth redirects
 */

/**
 * Get the base site URL with automatic environment detection.
 *
 * Priority:
 * 1. window.location.origin (client-side - always correct for current domain)
 * 2. NEXT_PUBLIC_SITE_URL (production/preview/dev override)
 * 3. VERCEL_URL (automatic Vercel preview deployments)
 * 4. http://localhost:3000 (local dev fallback)
 *
 * @returns Site URL without trailing slash
 */
export function getBaseUrl(): string {
  // Client-side: use current domain (works in prod, preview, and local)
  if (typeof window !== 'undefined') {
    return window.location.origin;
  }

  // Server-side: use env vars
  const fromEnv = process.env.NEXT_PUBLIC_SITE_URL;
  const fromVercel = process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : null;
  return (fromEnv || fromVercel || 'http://localhost:3000').replace(/\/$/, '');
}

/**
 * @deprecated Use getBaseUrl() instead
 */
export function getSiteUrl(): string {
  return getBaseUrl();
}

/**
 * Get the auth callback URL for magic links and OAuth
 * Points to server-side route that exchanges code for session
 * @returns Full URL to /auth/callback (server-side handler)
 */
export function getAuthCallbackUrl(): string {
  return `${getBaseUrl()}/auth/callback`;
}

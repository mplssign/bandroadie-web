// Shared CORS headers for BandRoadie Supabase Edge Functions.
// Base = Group B (Content-Type, Authorization, x-client-info, apikey) — the
// majority default. Callers override Access-Control-Allow-Methods or
// Access-Control-Allow-Headers via buildCorsHeaders() only when they need
// non-default values (calendar-feed: GET-only; send-push: X-Internal-Secret).

export const baseCorsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
};

export function buildCorsHeaders(
  overrides?: { methods?: string; headers?: string },
): Record<string, string> {
  return {
    ...baseCorsHeaders,
    ...(overrides?.methods !== undefined && { "Access-Control-Allow-Methods": overrides.methods }),
    ...(overrides?.headers !== undefined && { "Access-Control-Allow-Headers": overrides.headers }),
  };
}
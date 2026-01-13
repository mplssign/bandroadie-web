import { createClient as createSupabaseClient } from '@supabase/supabase-js';

/**
 * Create a Supabase admin client for server-side operations
 * Uses service role key to bypass RLS
 */
export function createClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

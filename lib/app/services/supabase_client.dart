import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// SUPABASE CLIENT
// Single point of access for the Supabase client.
// All repository and service code should import this file.
// ============================================================================

/// Returns the initialized Supabase client.
///
/// IMPORTANT: This uses the anon key only (public, row-level security enforced).
/// Never use service_role key in client code.
SupabaseClient get supabase => Supabase.instance.client;

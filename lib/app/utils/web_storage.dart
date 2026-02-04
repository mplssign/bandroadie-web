// Web storage utilities for accessing sessionStorage/localStorage
// Uses conditional imports to work on both web and native platforms

import 'web_storage_stub.dart'
    if (dart.library.html) 'web_storage_web.dart'
    as impl;

/// Get the Supabase auth fragment that was captured by JavaScript in index.html
/// Returns null on non-web platforms or if no fragment was captured
String? getSupabaseAuthFragment() {
  return impl.getSupabaseAuthFragment();
}

/// Clear the captured auth fragment after it's been used
void clearSupabaseAuthFragment() {
  impl.clearSupabaseAuthFragment();
}

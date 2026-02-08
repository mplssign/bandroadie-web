// Web implementation using dart:html
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

String? getSupabaseAuthFragment() {
  try {
    return html.window.sessionStorage['supabase_auth_fragment'];
  } catch (e) {
    return null;
  }
}

void clearSupabaseAuthFragment() {
  try {
    html.window.sessionStorage.remove('supabase_auth_fragment');
  } catch (e) {
    // Ignore errors
  }
}

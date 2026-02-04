// Web implementation using dart:html
// ignore: avoid_web_libraries_in_flutter
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

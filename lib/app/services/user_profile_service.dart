import 'package:bandroadie/app/models/user_profile.dart';
import 'package:bandroadie/app/services/supabase_client.dart';

/// Fetches a user profile by user ID from the 'users' table.
Future<UserProfile?> fetchUserProfileById(String userId) async {
  if (userId.isEmpty) return null;
  final response = await supabase
      .from('users')
      .select()
      .eq('id', userId)
      .maybeSingle();
  if (response == null) return null;
  return UserProfile.fromJson(response);
}

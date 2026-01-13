import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/services/supabase_client.dart';

/// Fetches a band by band ID from the 'bands' table.
Future<Band?> fetchBandById(String bandId) async {
  if (bandId.isEmpty) return null;
  final response = await supabase
      .from('bands')
      .select()
      .eq('id', bandId)
      .maybeSingle();
  if (response == null) return null;
  return Band.fromJson(response);
}

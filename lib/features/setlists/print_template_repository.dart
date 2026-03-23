import 'package:flutter/foundation.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'models/print_template.dart';

class PrintTemplateRepository {
  /// Fetch all print templates for a band.
  Future<List<PrintTemplate>> fetchTemplates(String bandId) async {
    try {
      final response = await supabase
          .from('print_templates')
          .select()
          .eq('band_id', bandId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((row) => PrintTemplate.fromSupabase(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[PrintTemplateRepo] Error fetching templates: $e');
      return [];
    }
  }

  /// Create a new print template.
  Future<PrintTemplate> createTemplate(
    String bandId,
    PrintTemplate template,
  ) async {
    final data = template.copyWith(bandId: bandId).toInsertJson();
    final response =
        await supabase.from('print_templates').insert(data).select().single();

    return PrintTemplate.fromSupabase(response);
  }

  /// Update an existing print template.
  Future<PrintTemplate> updateTemplate(PrintTemplate template) async {
    if (template.id == null) {
      throw Exception('Cannot update template without an id');
    }
    final response = await supabase
        .from('print_templates')
        .update(template.toUpdateJson())
        .eq('id', template.id!)
        .select()
        .single();

    return PrintTemplate.fromSupabase(response);
  }

  /// Delete a print template.
  Future<bool> deleteTemplate(String templateId) async {
    try {
      await supabase.from('print_templates').delete().eq('id', templateId);
      return true;
    } catch (e) {
      debugPrint('[PrintTemplateRepo] Error deleting template: $e');
      return false;
    }
  }

  /// Set the last-used print template for a band.
  /// Single atomic UPDATE on the bands row.
  Future<void> setLastUsed(String bandId, String templateId) async {
    try {
      await supabase
          .from('bands')
          .update({'last_used_print_template_id': templateId}).eq('id', bandId);
    } catch (e) {
      debugPrint('[PrintTemplateRepo] Error setting last used template: $e');
    }
  }

  /// Get the last-used print template ID for a band.
  /// Returns null if unset or if the referenced template was deleted
  /// (ON DELETE SET NULL).
  Future<String?> getLastUsedTemplateId(String bandId) async {
    try {
      final response = await supabase
          .from('bands')
          .select('last_used_print_template_id')
          .eq('id', bandId)
          .single();

      return response['last_used_print_template_id'] as String?;
    } catch (e) {
      debugPrint('[PrintTemplateRepo] Error getting last used template: $e');
      return null;
    }
  }
}

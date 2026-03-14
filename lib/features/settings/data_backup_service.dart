import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/services/app_version_service.dart';
import '../../app/services/supabase_client.dart';

// ignore: avoid_web_libraries_in_flutter
import 'data_backup_web_stub.dart'
    if (dart.library.html) 'data_backup_web.dart';

// ============================================================================
// DATA BACKUP SERVICE  —  Band-scoped export / import
// Schema version 1.
//
// Export scope (one band):
//   band, band_members, contributor_permissions,
//   songs, setlists, setlist_special_items, setlist_songs,
//   gigs, gig_dates, gig_responses, rehearsals, block_out_dates
//
// Not included (device / activity data):
//   device_tokens, notifications, band_calendar_subscriptions
// ============================================================================

class DataBackupException implements Exception {
  final String message;
  const DataBackupException(this.message);
  @override
  String toString() => message;
}

/// Read-only stats parsed from a backup file — used to populate dialogs.
class BandBackupStats {
  final String bandName;
  final int memberCount;
  final int songCount;
  final int setlistCount;
  final int gigCount;
  final int rehearsalCount;
  final int blockOutCount;

  const BandBackupStats({
    required this.bandName,
    required this.memberCount,
    required this.songCount,
    required this.setlistCount,
    required this.gigCount,
    required this.rehearsalCount,
    required this.blockOutCount,
  });
}

class DataBackupService {
  static const int schemaVersion = 1;

  // ─────────────────────────────────────────────────────────────────────────
  // EXPORT
  // ─────────────────────────────────────────────────────────────────────────

  /// Export one band's data and trigger a download / share sheet.
  static Future<void> exportBandData(
    String bandId,
    String bandName,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw const DataBackupException('Not logged in');

    final exportJson = await _buildBandExport(bandId, bandName, userId);
    final jsonString = const JsonEncoder.withIndent('  ').convert(exportJson);

    final safeName = bandName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final now = DateTime.now();
    final dateStamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}';
    final fileName = 'bandroadie_${safeName}_$dateStamp.json';

    if (kIsWeb) {
      triggerWebDownload(utf8.encode(jsonString), fileName);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonString);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'BandRoadie — $bandName Backup',
        text: fileName,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PREVIEW (for the restore dialog)
  // ─────────────────────────────────────────────────────────────────────────

  /// Parse a backup file and return stats without writing anything.
  static BandBackupStats previewBackup(String jsonContent) {
    final Map<String, dynamic> backup = _parseAndValidate(jsonContent);
    final bandEntry = backup['band_data'] as Map<String, dynamic>;
    final band = bandEntry['band'] as Map<String, dynamic>? ?? {};

    return BandBackupStats(
      bandName: band['name'] as String? ?? 'Unknown Band',
      memberCount: (bandEntry['band_members'] as List? ?? []).length,
      songCount: (bandEntry['songs'] as List? ?? []).length,
      setlistCount: (bandEntry['setlists'] as List? ?? []).length,
      gigCount: (bandEntry['gigs'] as List? ?? []).length,
      rehearsalCount: (bandEntry['rehearsals'] as List? ?? []).length,
      blockOutCount: (bandEntry['block_dates'] as List? ?? []).length,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // IMPORT
  // ─────────────────────────────────────────────────────────────────────────

  /// Validate a backup file and restore data into [targetBandId].
  static Future<void> importBandData(
    String jsonContent,
    String targetBandId,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw const DataBackupException('Not logged in');

    final backup = _parseAndValidate(jsonContent);
    final bandEntry = backup['band_data'] as Map<String, dynamic>;

    await _restoreBandData(bandEntry, targetBandId, userId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL: BUILD EXPORT
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _buildBandExport(
    String bandId,
    String bandName,
    String userId,
  ) async {
    final band = await supabase
        .from('bands')
        .select()
        .eq('id', bandId)
        .maybeSingle();

    final bandMembers = await supabase
        .from('band_members')
        .select()
        .eq('band_id', bandId);

    final memberIds =
        (bandMembers as List).map((m) => m['id'] as String).toList();
    List<dynamic> contributorPerms = [];
    if (memberIds.isNotEmpty) {
      contributorPerms = await supabase
          .from('contributor_permissions')
          .select()
          .inFilter('band_member_id', memberIds);
    }

    final songs = await supabase.from('songs').select().eq('band_id', bandId);

    final setlists =
        await supabase.from('setlists').select().eq('band_id', bandId);

    final specialItems = await supabase
        .from('setlist_special_items')
        .select()
        .eq('band_id', bandId);

    final setlistIds =
        (setlists as List).map((s) => s['id'] as String).toList();
    List<dynamic> setlistSongs = [];
    if (setlistIds.isNotEmpty) {
      setlistSongs = await supabase
          .from('setlist_songs')
          .select()
          .inFilter('setlist_id', setlistIds);
    }

    final gigs = await supabase.from('gigs').select().eq('band_id', bandId);

    final gigIds = (gigs as List).map((g) => g['id'] as String).toList();
    List<dynamic> gigDates = [];
    List<dynamic> gigResponses = [];
    if (gigIds.isNotEmpty) {
      gigDates = await supabase
          .from('gig_dates')
          .select()
          .inFilter('gig_id', gigIds);
      gigResponses = await supabase
          .from('gig_responses')
          .select()
          .inFilter('gig_id', gigIds);
    }

    final rehearsals =
        await supabase.from('rehearsals').select().eq('band_id', bandId);

    final blockOuts =
        await supabase.from('block_dates').select().eq('band_id', bandId);

    return {
      'metadata': {
        'schema_version': schemaVersion,
        'app_version': AppVersionService.fullVersion,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'exported_by_user_id': userId,
        'band_id': bandId,
        'band_name': bandName,
      },
      'band_data': {
        'band': band,
        'band_members': bandMembers,
        'contributor_permissions': contributorPerms,
        'songs': songs,
        'setlists': setlists,
        'setlist_special_items': specialItems,
        'setlist_songs': setlistSongs,
        'gigs': gigs,
        'gig_dates': gigDates,
        'gig_responses': gigResponses,
        'rehearsals': rehearsals,
        'block_dates': blockOuts,
      },
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL: VALIDATE
  // ─────────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _parseAndValidate(String jsonContent) {
    final Map<String, dynamic> backup;
    try {
      backup = json.decode(jsonContent) as Map<String, dynamic>;
    } catch (_) {
      throw const DataBackupException(
        'Invalid file. The selected file is not valid JSON.',
      );
    }

    if (!backup.containsKey('metadata') || !backup.containsKey('band_data')) {
      throw const DataBackupException(
        'Unrecognised backup format. This file is not a BandRoadie backup.',
      );
    }

    final metadata = backup['metadata'] as Map<String, dynamic>;
    final version = metadata['schema_version'] as int? ?? 0;
    if (version != schemaVersion) {
      throw DataBackupException(
        'Unsupported backup version ($version). '
        'This app supports version $schemaVersion.',
      );
    }

    return backup;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL: RESTORE  — upsert order respects FK constraints
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _restoreBandData(
    Map<String, dynamic> entry,
    String targetBandId,
    String userId,
  ) async {
    // 1. Band
    final band = entry['band'] as Map<String, dynamic>?;
    if (band != null) await _upsertRows('bands', [band]);

    // 2. Band members
    await _upsertRows('band_members', entry['band_members'] as List? ?? []);

    // 3. Contributor permissions
    await _upsertRows(
      'contributor_permissions',
      entry['contributor_permissions'] as List? ?? [],
    );

    // 4. Songs
    await _upsertRows('songs', entry['songs'] as List? ?? []);

    // 5. Setlists
    await _upsertRows('setlists', entry['setlists'] as List? ?? []);

    // 6. Setlist special items (set breaks / pauses)
    await _upsertRows(
      'setlist_special_items',
      entry['setlist_special_items'] as List? ?? [],
    );

    // 7. Setlist songs (depends on songs + setlists + special items)
    await _upsertRows('setlist_songs', entry['setlist_songs'] as List? ?? []);

    // 8. Gigs
    await _upsertRows('gigs', entry['gigs'] as List? ?? []);

    // 9. Gig dates
    await _upsertRows('gig_dates', entry['gig_dates'] as List? ?? []);

    // 10. Gig responses
    await _upsertRows('gig_responses', entry['gig_responses'] as List? ?? []);

    // 11. Rehearsals
    await _upsertRows('rehearsals', entry['rehearsals'] as List? ?? []);

    // 12. Block-out dates
    await _upsertRows(
      'block_dates',
      entry['block_dates'] as List? ?? [],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _upsertRows(String table, List<dynamic> rows) async {
    if (rows.isEmpty) return;
    final data =
        rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    await supabase
        .from(table)
        .upsert(data, onConflict: 'id', ignoreDuplicates: false);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

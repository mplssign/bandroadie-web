import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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

/// Thrown when the user dismisses a save/open dialog without selecting a file.
class DataBackupCancelledException implements Exception {
  const DataBackupCancelledException();
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

  /// Export one band's data and save it via the native file picker.
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
    final dateStamp = '${now.year}${_pad(now.month)}${_pad(now.day)}';
    final fileName = 'bandroadie_${safeName}_$dateStamp.json';

    final bytes = Uint8List.fromList(utf8.encode(jsonString));

    if (kIsWeb) {
      // Web: JS blob download
      triggerWebDownload(bytes, fileName);
    } else if (Platform.isWindows || Platform.isIOS || Platform.isAndroid) {
      // Windows / iOS / Android: file_picker requires bytes; it handles writing
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save Band Backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
    } else {
      // macOS / Linux: bytes param is unsupported — get path, write ourselves
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Band Backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (savePath == null) throw const DataBackupCancelledException();
      final saveFile = File(savePath);
      await saveFile.parent.create(recursive: true);
      await saveFile.writeAsBytes(bytes);
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
    String? targetBandId,
  ) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw const DataBackupException('Not logged in');

    final backup = _parseAndValidate(jsonContent);
    final bandEntry = backup['band_data'] as Map<String, dynamic>;

    final backupBandId =
        (bandEntry['band'] as Map<String, dynamic>?)?['id'] as String?;
    bool bandExists = false;
    if (backupBandId != null) {
      final result = await supabase
          .from('bands')
          .select('id')
          .eq('id', backupBandId)
          .maybeSingle();
      bandExists = result != null;
    }

    await _restoreBandData(bandEntry, targetBandId, userId, bandExists);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL: BUILD EXPORT
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _buildBandExport(
    String bandId,
    String bandName,
    String userId,
  ) async {
    final band =
        await supabase.from('bands').select().eq('id', bandId).maybeSingle();

    final bandMembers =
        await supabase.from('band_members').select().eq('band_id', bandId);

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
      gigDates =
          await supabase.from('gig_dates').select().inFilter('gig_id', gigIds);
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
    String? targetBandId,
    String userId,
    bool bandExists,
  ) async {
    try {
      if (bandExists) {
        // ── Existing-band path ── behaviour unchanged ──────────────────────
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
        await _upsertRows(
            'setlist_songs', entry['setlist_songs'] as List? ?? []);

        // 8. Gigs
        await _upsertRows('gigs', entry['gigs'] as List? ?? []);

        // 9. Gig dates
        await _upsertRows('gig_dates', entry['gig_dates'] as List? ?? []);

        // 10. Gig responses
        await _upsertRows(
            'gig_responses', entry['gig_responses'] as List? ?? []);

        // 11. Rehearsals
        await _upsertRows('rehearsals', entry['rehearsals'] as List? ?? []);

        // 12. Block-out dates
        await _upsertRows(
          'block_dates',
          entry['block_dates'] as List? ?? [],
        );
      } else {
        // ── Missing-band path ── band was deleted; recreate via RPC ─────────

        // a. Create the band via create_band RPC (atomic: inserts band + admin row)
        final bandMap = entry['band'] as Map<String, dynamic>? ?? {};
        final bandName = bandMap['name'] as String? ?? 'Restored Band';
        final avatarColor = bandMap['avatar_color'] as String?;
        final imageUrl = bandMap['image_url'] as String?;

        final newBandId = await supabase.rpc(
          'create_band',
          params: {
            'p_name': bandName,
            'p_avatar_color': avatarColor,
            'p_image_url': imageUrl,
          },
        ) as String;

        // Query the trigger-created catalog setlist UUID.
        // create_band fires auto_create_catalog_for_band() which inserts a catalog
        // setlist for newBandId. Remap the backup's catalog UUID onto this row to
        // avoid violating the setlists_one_catalog_per_band unique constraint.
        final triggerCatalogRow = await supabase
            .from('setlists')
            .select('id')
            .eq('band_id', newBandId)
            .eq('is_catalog', true)
            .maybeSingle();
        final triggerCatalogId = triggerCatalogRow?['id'] as String?;

        final rawSetlists =
            (entry['setlists'] as List? ?? []).cast<Map<String, dynamic>>();

        // Collect ALL backup catalog UUIDs — handles pre-existing duplicates.
        final backupCatalogIds = rawSetlists
            .where((s) => s['is_catalog'] == true)
            .map((s) => s['id'] as String?)
            .whereType<String>()
            .toSet();

        // Map ALL of them to the trigger-created catalog UUID.
        // Empty when triggerCatalogId is null — safe no-op fallback.
        final Map<String, String> setlistIdRemap = {};
        if (triggerCatalogId != null) {
          for (final id in backupCatalogIds) {
            setlistIdRemap[id] = triggerCatalogId;
          }
        }

        // b. Remap band_id to newBandId in all child tables that carry it.
        List<Map<String, dynamic>> remapBandId(List<dynamic> rows) => rows
            .map((r) =>
                Map<String, dynamic>.from(r as Map)..['band_id'] = newBandId)
            .toList();

        // c–d. Band members: remap band_id, filter out current user (already
        //      inserted as admin by create_band).
        final rawMembers =
            (entry['band_members'] as List? ?? []).cast<Map<String, dynamic>>();
        final remappedMembers = rawMembers
            .map((r) => Map<String, dynamic>.from(r)..['band_id'] = newBandId)
            .where((r) => r['user_id'] != userId)
            .toList();

        // e. Rehearsals: generate fresh UUIDs to avoid conflict on orphaned rows.
        final rawRehearsals =
            (entry['rehearsals'] as List? ?? []).cast<Map<String, dynamic>>();
        final oldToNewRehearsal = <String, String>{
          for (final r in rawRehearsals) (r['id'] as String): _generateUuid(),
        };
        final remappedRehearsals = rawRehearsals.map((r) {
          final updated = Map<String, dynamic>.from(r)
            ..['id'] = oldToNewRehearsal[r['id'] as String]
            ..['band_id'] = newBandId;
          final oldParentId = r['parent_rehearsal_id'] as String?;
          if (oldParentId != null) {
            updated['parent_rehearsal_id'] = oldToNewRehearsal[oldParentId];
          }
          return updated;
        }).toList();

        // f. Block-out dates: generate fresh UUIDs to avoid conflict on orphaned rows.
        final rawBlockDates =
            (entry['block_dates'] as List? ?? []).cast<Map<String, dynamic>>();
        final remappedBlockDates = rawBlockDates
            .map((r) => Map<String, dynamic>.from(r)
              ..['id'] = _generateUuid()
              ..['band_id'] = newBandId)
            .toList();

        // g. Upsert in the same FK-safe order.
        // 1. Band — already created by create_band RPC; skip.

        // 2. Band members (filtered, remapped) — use RPC for atomic restore
        if (remappedMembers.isNotEmpty) {
          await supabase.rpc(
            'restore_band_members',
            params: {
              'p_band_id': newBandId,
              'p_members': remappedMembers,
            },
          );
        }

        // 3. Contributor permissions (no band_id field)
        await _upsertRows(
          'contributor_permissions',
          entry['contributor_permissions'] as List? ?? [],
        );

        // 4. Songs
        await _upsertRows('songs', remapBandId(entry['songs'] as List? ?? []));

        // 5. Setlists — remap band_id; remap ALL catalog ids → trigger-uuid;
        //    deduplicate so only one is_catalog=true row is upserted.
        var catalogIncluded = false;
        final remappedSetlists = rawSetlists.expand<Map<String, dynamic>>((s) {
          final mapped = Map<String, dynamic>.from(s)..['band_id'] = newBandId;
          final oldId = s['id'] as String?;
          if (oldId != null && setlistIdRemap.containsKey(oldId)) {
            mapped['id'] = setlistIdRemap[oldId];
          }
          if (mapped['is_catalog'] == true) {
            if (catalogIncluded) return const []; // drop duplicate catalog rows
            catalogIncluded = true;
          }
          return [mapped];
        }).toList();
        await _upsertRows('setlists', remappedSetlists);

        // 6. Setlist special items
        await _upsertRows(
          'setlist_special_items',
          remapBandId(entry['setlist_special_items'] as List? ?? []),
        );

        // 7. Setlist songs — remap setlist_id for songs belonging to the catalog setlist
        final rawSetlistSongs = (entry['setlist_songs'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final remappedSetlistSongs = rawSetlistSongs.map((s) {
          final mapped = Map<String, dynamic>.from(s);
          final oldSetlistId = s['setlist_id'] as String?;
          if (oldSetlistId != null &&
              setlistIdRemap.containsKey(oldSetlistId)) {
            mapped['setlist_id'] = setlistIdRemap[oldSetlistId];
          }
          return mapped;
        }).toList();
        await _upsertRows('setlist_songs', remappedSetlistSongs);

        // 8. Gigs
        await _upsertRows('gigs', remapBandId(entry['gigs'] as List? ?? []));

        // 9. Gig dates (no band_id)
        await _upsertRows('gig_dates', entry['gig_dates'] as List? ?? []);

        // 10. Gig responses (no band_id)
        await _upsertRows(
            'gig_responses', entry['gig_responses'] as List? ?? []);

        // 11. Rehearsals (fresh UUIDs, remapped band_id)
        await _upsertRows('rehearsals', remappedRehearsals);

        // 12. Block-out dates (fresh UUIDs, remapped band_id)
        await _upsertRows('block_dates', remappedBlockDates);
      }
    } on PostgrestException catch (e) {
      throw DataBackupException('Database error during restore: ${e.message}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _upsertRows(String table, List<dynamic> rows) async {
    if (rows.isEmpty) return;
    final data = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    await supabase
        .from(table)
        .upsert(data, onConflict: 'id', ignoreDuplicates: false);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant bits
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}

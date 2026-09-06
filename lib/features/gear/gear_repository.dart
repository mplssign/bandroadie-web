import 'package:bandroadie/app/services/supabase_client.dart';
import 'models/gear_item.dart';

class NoBandSelectedGearError extends Error {
  final String message;
  NoBandSelectedGearError([
    this.message =
        'No band selected. Cannot fetch gear without a band context.',
  ]);

  @override
  String toString() => 'NoBandSelectedGearError: $message';
}

class GearRepository {
  final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  Future<List<GearItem>> fetchGear({
    required String? bandId,
    bool forceRefresh = false,
  }) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedGearError();
    }

    if (!forceRefresh) {
      final cached = _cache[bandId];
      if (cached != null && !cached.isExpired) {
        return cached.data;
      }
    }

    final response = await supabase
        .from('band_gear')
        .select()
        .eq('band_id', bandId)
        .order('name');

    final rows = List<Map<String, dynamic>>.from(response);
    final items = rows.map(GearItem.fromJson).toList();

    _cache[bandId] = _CacheEntry(data: items);

    return items;
  }

  Future<GearItem> createGear({
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    final insertData = {
      'band_id': bandId,
      ...data,
    };

    final response =
        await supabase.from('band_gear').insert(insertData).select().single();

    _invalidateCache(bandId);
    return GearItem.fromJson(response);
  }

  Future<GearItem> updateGear({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    final response = await supabase
        .from('band_gear')
        .update(data)
        .eq('id', id)
        .select()
        .single();

    final item = GearItem.fromJson(response);
    _invalidateCache(item.bandId);
    return item;
  }

  Future<void> deleteGear({
    required String id,
    required String bandId,
  }) async {
    await supabase.from('band_gear').delete().eq('id', id);
    _invalidateCache(bandId);
  }

  void _invalidateCache(String bandId) {
    _cache.remove(bandId);
  }

  void clearCache() {
    _cache.clear();
  }
}

class _CacheEntry {
  final List<GearItem> data;
  final DateTime createdAt;

  _CacheEntry({required this.data}) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt) > GearRepository._cacheDuration;
}

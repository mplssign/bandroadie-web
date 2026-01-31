import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ============================================================================
// CUSTOM TUNING SERVICE
// Manages persistence of user-created custom guitar tunings.
//
// Storage: SharedPreferences (local only for now)
// Format: JSON array of CustomTuning objects
// ============================================================================

/// Represents a custom guitar tuning created by the user
class CustomTuning {
  final String id; // Generated unique ID
  final String name; // User-provided name (e.g., "Drop D", "My Tuning")
  final String strings; // Space-separated notes (e.g., "D A D G B E")
  final DateTime createdAt;

  const CustomTuning({
    required this.id,
    required this.name,
    required this.strings,
    required this.createdAt,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'strings': strings,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Create from JSON
  factory CustomTuning.fromJson(Map<String, dynamic> json) => CustomTuning(
    id: json['id'] as String,
    name: json['name'] as String,
    strings: json['strings'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  @override
  String toString() => 'CustomTuning($id, $name, $strings)';
}

/// Service for managing custom tunings
class CustomTuningService {
  static const String _storageKey = 'custom_guitar_tunings';

  /// Get all custom tunings, sorted by creation date (newest first)
  Future<List<CustomTuning>> getCustomTunings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      final tunings = jsonList
          .map((json) => CustomTuning.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort by creation date, newest first
      tunings.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return tunings;
    } catch (e) {
      print('[CustomTuningService] Error loading tunings: $e');
      return [];
    }
  }

  /// Save a new custom tuning
  /// Returns the saved tuning with generated ID
  Future<CustomTuning> saveCustomTuning({
    required String name,
    required String strings,
  }) async {
    // Validate inputs
    if (name.trim().isEmpty) {
      throw ArgumentError('Tuning name cannot be empty');
    }
    if (strings.trim().isEmpty) {
      throw ArgumentError('Tuning strings cannot be empty');
    }

    // Create new tuning with generated ID
    final tuning = CustomTuning(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      strings: strings.trim(),
      createdAt: DateTime.now(),
    );

    // Load existing tunings
    final existing = await getCustomTunings();

    // Add new tuning
    existing.insert(0, tuning); // Add at beginning (newest first)

    // Save back to storage
    await _saveAllTunings(existing);

    print('[CustomTuningService] Saved custom tuning: $tuning');

    return tuning;
  }

  /// Delete a custom tuning by ID
  Future<void> deleteCustomTuning(String id) async {
    final existing = await getCustomTunings();
    final updated = existing.where((t) => t.id != id).toList();

    if (updated.length == existing.length) {
      print('[CustomTuningService] Tuning $id not found, nothing to delete');
      return;
    }

    await _saveAllTunings(updated);
    print('[CustomTuningService] Deleted custom tuning: $id');
  }

  /// Find a custom tuning by ID
  Future<CustomTuning?> findCustomTuningById(String id) async {
    final tunings = await getCustomTunings();
    try {
      return tunings.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Check if a tuning ID is a custom tuning (starts with 'custom_')
  static bool isCustomTuningId(String? id) {
    return id != null && id.startsWith('custom_');
  }

  /// Save all tunings to storage
  Future<void> _saveAllTunings(List<CustomTuning> tunings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = tunings.map((t) => t.toJson()).toList();
    final jsonString = json.encode(jsonList);
    await prefs.setString(_storageKey, jsonString);
  }

  /// Clear all custom tunings (for testing/reset)
  Future<void> clearAllCustomTunings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    print('[CustomTuningService] Cleared all custom tunings');
  }
}

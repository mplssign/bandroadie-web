// ============================================================================
// BAND MODEL
// Represents a band in the system.
// All band data is strictly isolated — users only see bands they belong to.
//
// Schema: public.bands
// ============================================================================

class Band {
  final String id;
  final String name;
  final String? imageUrl;
  final String? createdBy;
  final String avatarColor;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Band({
    required this.id,
    required this.name,
    this.imageUrl,
    this.createdBy,
    this.avatarColor = 'bg-red-600',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a Band from Supabase row data
  factory Band.fromJson(Map<String, dynamic> json) {
    return Band(
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: json['image_url'] as String?,
      createdBy: json['created_by'] as String?,
      avatarColor: json['avatar_color'] as String? ?? 'bg-red-600',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'image_url': imageUrl,
      'created_by': createdBy,
      'avatar_color': avatarColor,
    };
  }

  @override
  String toString() => 'Band(id: $id, name: $name)';
}

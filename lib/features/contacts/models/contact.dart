class Contact {
  final String id;
  final String bandId;
  final String name;
  final String? title;
  final String? phone;
  final String? email;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Contact({
    required this.id,
    required this.bandId,
    required this.name,
    this.title,
    this.phone,
    this.email,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      name: json['name'] as String,
      title: json['title'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'band_id': bandId,
      'name': name,
      'title': title,
      'phone': phone,
      'email': email,
      'notes': notes,
    };
  }
}

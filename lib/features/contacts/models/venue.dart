import 'venue_contact.dart';

class Venue {
  final String id;
  final String bandId;
  final String name;
  final String? address;
  final String? city;
  final String? state;
  final String? phone;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<VenueContact> contacts;

  const Venue({
    required this.id,
    required this.bandId,
    required this.name,
    this.address,
    this.city,
    this.state,
    this.phone,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.contacts = const [],
  });

  factory Venue.fromJson(Map<String, dynamic> json) {
    final venueContactsRaw = json['venue_contacts'];
    final contacts = <VenueContact>[];
    if (venueContactsRaw is List) {
      for (final vc in venueContactsRaw) {
        if (vc is Map<String, dynamic>) {
          contacts.add(VenueContact.fromJson(vc));
        }
      }
    }

    return Venue(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      phone: json['phone'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      contacts: contacts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'band_id': bandId,
      'name': name,
      'address': address,
      'city': city,
      'state': state,
      'phone': phone,
      'notes': notes,
    };
  }
}

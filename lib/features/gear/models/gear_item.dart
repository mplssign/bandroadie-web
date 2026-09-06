enum GearOwnerType {
  band,
  member;

  String get dbValue {
    switch (this) {
      case GearOwnerType.band:
        return 'band';
      case GearOwnerType.member:
        return 'member';
    }
  }

  static GearOwnerType fromDbValue(String value) {
    return GearOwnerType.values.firstWhere(
      (t) => t.dbValue == value,
      orElse: () => GearOwnerType.band,
    );
  }
}

class GearItem {
  final String id;
  final String bandId;
  final String name;
  final DateTime? purchasedOn;
  final String? purchasedFrom;
  final int? priceCents;
  final GearOwnerType ownerType;
  final String? ownerUserId;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GearItem({
    required this.id,
    required this.bandId,
    required this.name,
    this.purchasedOn,
    this.purchasedFrom,
    this.priceCents,
    required this.ownerType,
    this.ownerUserId,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(
          (ownerType == GearOwnerType.band && ownerUserId == null) ||
              (ownerType == GearOwnerType.member && ownerUserId != null),
          'Owner shape invariant violated: band must have null owner_user_id and member must have non-null owner_user_id.',
        );

  factory GearItem.fromJson(Map<String, dynamic> json) {
    return GearItem(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      name: json['name'] as String,
      purchasedOn: json['purchased_on'] != null
          ? DateTime.parse(json['purchased_on'] as String)
          : null,
      purchasedFrom: json['purchased_from'] as String?,
      priceCents: json['price_cents'] as int?,
      ownerType: GearOwnerType.fromDbValue(json['owner_type'] as String),
      ownerUserId: json['owner_user_id'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'band_id': bandId,
      'name': name,
      'purchased_on': purchasedOn?.toIso8601String().split('T').first,
      'purchased_from': purchasedFrom,
      'price_cents': priceCents,
      'owner_type': ownerType.dbValue,
      'owner_user_id': ownerUserId,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

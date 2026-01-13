// ============================================================================
// GIG RESPONSE MODEL
// Represents a band member's RSVP to a potential gig.
//
// Schema: public.gig_responses
// ============================================================================

enum GigResponseType { yes, no }

class GigResponse {
  final String id;
  final String gigId;
  final String userId;
  final GigResponseType response;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GigResponse({
    required this.id,
    required this.gigId,
    required this.userId,
    required this.response,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a GigResponse from Supabase row data
  factory GigResponse.fromJson(Map<String, dynamic> json) {
    return GigResponse(
      id: json['id'] as String,
      gigId: json['gig_id'] as String,
      userId: json['user_id'] as String,
      response: _parseResponse(json['response'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  static GigResponseType _parseResponse(String response) {
    switch (response) {
      case 'yes':
        return GigResponseType.yes;
      case 'no':
        return GigResponseType.no;
      default:
        return GigResponseType.no;
    }
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {'gig_id': gigId, 'user_id': userId, 'response': response.name};
  }

  bool get isYes => response == GigResponseType.yes;
  bool get isNo => response == GigResponseType.no;

  @override
  String toString() =>
      'GigResponse(gigId: $gigId, userId: $userId, response: ${response.name})';
}

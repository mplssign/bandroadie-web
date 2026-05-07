// ============================================================================
// REHEARSAL RESPONSE MODEL
// Represents a band member's RSVP to a potential rehearsal.
//
// Schema: public.rehearsal_responses
// ============================================================================

enum RehearsalResponseType { yes, no }

class RehearsalResponse {
  final String id;
  final String rehearsalId;
  final String userId;
  final RehearsalResponseType response;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RehearsalResponse({
    required this.id,
    required this.rehearsalId,
    required this.userId,
    required this.response,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a RehearsalResponse from Supabase row data
  factory RehearsalResponse.fromJson(Map<String, dynamic> json) {
    return RehearsalResponse(
      id: json['id'] as String,
      rehearsalId: json['rehearsal_id'] as String,
      userId: json['user_id'] as String,
      response: _parseResponse(json['response'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  static RehearsalResponseType _parseResponse(String response) {
    switch (response) {
      case 'yes':
        return RehearsalResponseType.yes;
      case 'no':
        return RehearsalResponseType.no;
      default:
        return RehearsalResponseType.no;
    }
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'rehearsal_id': rehearsalId,
      'user_id': userId,
      'response': response.name,
    };
  }

  bool get isYes => response == RehearsalResponseType.yes;
  bool get isNo => response == RehearsalResponseType.no;

  @override
  String toString() =>
      'RehearsalResponse(rehearsalId: $rehearsalId, userId: $userId, response: ${response.name})';
}

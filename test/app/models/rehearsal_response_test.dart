import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/models/rehearsal_response.dart';

void main() {
  group('RehearsalResponse', () {
    test('fromJson parses correctly with yes response', () {
      final json = {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'rehearsal_id': '123e4567-e89b-12d3-a456-426614174001',
        'user_id': '123e4567-e89b-12d3-a456-426614174002',
        'response': 'yes',
        'created_at': '2026-05-07T12:00:00Z',
        'updated_at': '2026-05-07T12:00:00Z',
      };

      final response = RehearsalResponse.fromJson(json);

      expect(response.id, '123e4567-e89b-12d3-a456-426614174000');
      expect(response.rehearsalId, '123e4567-e89b-12d3-a456-426614174001');
      expect(response.userId, '123e4567-e89b-12d3-a456-426614174002');
      expect(response.response, RehearsalResponseType.yes);
      expect(response.isYes, true);
      expect(response.isNo, false);
      expect(response.createdAt, DateTime.parse('2026-05-07T12:00:00Z'));
      expect(response.updatedAt, DateTime.parse('2026-05-07T12:00:00Z'));
    });

    test('fromJson parses correctly with no response', () {
      final json = {
        'id': '223e4567-e89b-12d3-a456-426614174000',
        'rehearsal_id': '223e4567-e89b-12d3-a456-426614174001',
        'user_id': '223e4567-e89b-12d3-a456-426614174002',
        'response': 'no',
        'created_at': '2026-05-07T13:00:00Z',
        'updated_at': '2026-05-07T13:00:00Z',
      };

      final response = RehearsalResponse.fromJson(json);

      expect(response.response, RehearsalResponseType.no);
      expect(response.isYes, false);
      expect(response.isNo, true);
    });

    test('fromJson handles invalid response by defaulting to no', () {
      final json = {
        'id': '323e4567-e89b-12d3-a456-426614174000',
        'rehearsal_id': '323e4567-e89b-12d3-a456-426614174001',
        'user_id': '323e4567-e89b-12d3-a456-426614174002',
        'response': 'invalid',
        'created_at': '2026-05-07T14:00:00Z',
        'updated_at': '2026-05-07T14:00:00Z',
      };

      final response = RehearsalResponse.fromJson(json);

      expect(response.response, RehearsalResponseType.no);
      expect(response.isNo, true);
    });

    test('toJson serializes correctly with yes response', () {
      final response = RehearsalResponse(
        id: '423e4567-e89b-12d3-a456-426614174000',
        rehearsalId: '423e4567-e89b-12d3-a456-426614174001',
        userId: '423e4567-e89b-12d3-a456-426614174002',
        response: RehearsalResponseType.yes,
        createdAt: DateTime.parse('2026-05-07T15:00:00Z'),
        updatedAt: DateTime.parse('2026-05-07T15:00:00Z'),
      );

      final json = response.toJson();

      expect(json['rehearsal_id'], '423e4567-e89b-12d3-a456-426614174001');
      expect(json['user_id'], '423e4567-e89b-12d3-a456-426614174002');
      expect(json['response'], 'yes');
      // Note: id, created_at, updated_at are not included in toJson
      // as they are managed by Supabase
    });

    test('toJson serializes correctly with no response', () {
      final response = RehearsalResponse(
        id: '523e4567-e89b-12d3-a456-426614174000',
        rehearsalId: '523e4567-e89b-12d3-a456-426614174001',
        userId: '523e4567-e89b-12d3-a456-426614174002',
        response: RehearsalResponseType.no,
        createdAt: DateTime.parse('2026-05-07T16:00:00Z'),
        updatedAt: DateTime.parse('2026-05-07T16:00:00Z'),
      );

      final json = response.toJson();

      expect(json['response'], 'no');
    });

    test('fromJson/toJson round-trip preserves data', () {
      final originalJson = {
        'id': '623e4567-e89b-12d3-a456-426614174000',
        'rehearsal_id': '623e4567-e89b-12d3-a456-426614174001',
        'user_id': '623e4567-e89b-12d3-a456-426614174002',
        'response': 'yes',
        'created_at': '2026-05-07T17:00:00Z',
        'updated_at': '2026-05-07T17:00:00Z',
      };

      final response = RehearsalResponse.fromJson(originalJson);
      final outputJson = response.toJson();

      // Verify core fields preserved
      expect(outputJson['rehearsal_id'], originalJson['rehearsal_id']);
      expect(outputJson['user_id'], originalJson['user_id']);
      expect(outputJson['response'], originalJson['response']);
    });

    test('toString returns formatted string', () {
      final response = RehearsalResponse(
        id: '723e4567-e89b-12d3-a456-426614174000',
        rehearsalId: '723e4567-e89b-12d3-a456-426614174001',
        userId: '723e4567-e89b-12d3-a456-426614174002',
        response: RehearsalResponseType.yes,
        createdAt: DateTime.parse('2026-05-07T18:00:00Z'),
        updatedAt: DateTime.parse('2026-05-07T18:00:00Z'),
      );

      final str = response.toString();

      expect(
        str,
        contains('RehearsalResponse'),
      );
      expect(str, contains('723e4567-e89b-12d3-a456-426614174001'));
      expect(str, contains('yes'));
    });
  });
}

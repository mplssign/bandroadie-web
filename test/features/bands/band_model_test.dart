import 'package:bandroadie/app/models/band.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseJson = {
    'id': 'band-1',
    'name': 'Test Band',
    'created_at': '2026-09-15T12:00:00.000Z',
    'updated_at': '2026-09-15T12:00:00.000Z',
  };

  test('constructor defaults currency code to USD', () {
    final band = Band(
      id: 'band-1',
      name: 'Test Band',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    expect(band.currencyCode, 'USD');
  });

  test('fromJson defaults a legacy row without currency code to USD', () {
    expect(Band.fromJson(baseJson).currencyCode, 'USD');
  });

  test('fromJson reads currency code', () {
    final band = Band.fromJson({...baseJson, 'currency_code': 'EUR'});

    expect(band.currencyCode, 'EUR');
  });

  test('toJson round-trip preserves currency code', () {
    final band = Band.fromJson({...baseJson, 'currency_code': 'CAD'});

    expect(band.toJson()['currency_code'], 'CAD');
    expect(
      Band.fromJson({...baseJson, ...band.toJson()}).currencyCode,
      'CAD',
    );
  });
}

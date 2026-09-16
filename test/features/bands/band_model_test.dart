import 'package:bandroadie/app/models/band.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseJson = {
    'id': 'band-1',
    'name': 'Test Band',
    'created_at': '2026-09-15T12:00:00.000Z',
    'updated_at': '2026-09-15T12:00:00.000Z',
  };

  test('constructor defaults currency code and locale', () {
    final band = Band(
      id: 'band-1',
      name: 'Test Band',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    expect(band.currencyCode, 'USD');
    expect(band.locale, 'en_US');
  });

  test('fromJson defaults a legacy row without currency code or locale', () {
    expect(Band.fromJson(baseJson).currencyCode, 'USD');
    expect(Band.fromJson(baseJson).locale, 'en_US');
  });

  test('fromJson reads currency code', () {
    final band = Band.fromJson({...baseJson, 'currency_code': 'EUR'});

    expect(band.currencyCode, 'EUR');
  });

  test('toJson round-trip preserves currency code and locale', () {
    final band = Band.fromJson({
      ...baseJson,
      'currency_code': 'CAD',
      'locale': 'en_CA',
    });

    expect(band.toJson()['currency_code'], 'CAD');
    expect(band.toJson()['locale'], 'en_CA');
    expect(
      Band.fromJson({...baseJson, ...band.toJson()}).currencyCode,
      'CAD',
    );
    expect(Band.fromJson({...baseJson, ...band.toJson()}).locale, 'en_CA');
  });

  test('currency resolves from locale before the legacy code fallback', () {
    final euroBand = Band(
      id: 'band-1',
      name: 'Test Band',
      currencyCode: 'EUR',
      locale: 'bg_BG',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    expect(euroBand.currency.locale, 'bg_BG');
    expect(Band.fromJson(baseJson).currency.locale, 'en_US');
  });
}

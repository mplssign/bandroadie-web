import 'package:bandroadie/features/bands/currency/band_currency.dart';
import 'package:flutter_test/flutter_test.dart';

const _country = 'countryLabel';
const _code = 'isoCode';
const _name = 'name';
const _symbol = 'symbol';

const _expectedCurrencies = <Map<String, Object?>>[
  {
    _country: 'United States',
    _code: 'USD',
    _name: 'US Dollar',
    _symbol: r'$',
  },
  {_country: 'Canada', _code: 'CAD', _name: 'Canadian Dollar', _symbol: r'C$'},
  {_country: 'Mexico', _code: 'MXN', _name: 'Mexican Peso', _symbol: r'$'},
  {_country: 'Eurozone / Bulgaria', _code: 'EUR', _name: 'Euro', _symbol: '€'},
  {
    _country: 'United Kingdom',
    _code: 'GBP',
    _name: 'Pound Sterling',
    _symbol: '£'
  },
  {_country: 'Switzerland', _code: 'CHF', _name: 'Swiss Franc', _symbol: null},
  {_country: 'Poland', _code: 'PLN', _name: 'Złoty', _symbol: 'zł'},
  {_country: 'Czechia', _code: 'CZK', _name: 'Czech Koruna', _symbol: 'Kč'},
  {_country: 'Hungary', _code: 'HUF', _name: 'Forint', _symbol: 'Ft'},
  {_country: 'Denmark', _code: 'DKK', _name: 'Danish Krone', _symbol: 'kr'},
  {_country: 'Sweden', _code: 'SEK', _name: 'Swedish Krona', _symbol: 'kr'},
  {_country: 'Norway', _code: 'NOK', _name: 'Norwegian Krone', _symbol: 'kr'},
  {_country: 'Iceland', _code: 'ISK', _name: 'Icelandic Króna', _symbol: 'kr'},
  {_country: 'Romania', _code: 'RON', _name: 'Romanian Leu', _symbol: 'lei'},
  {_country: 'Serbia', _code: 'RSD', _name: 'Serbian Dinar', _symbol: null},
  {_country: 'Albania', _code: 'ALL', _name: 'Lek', _symbol: 'L'},
  {_country: 'North Macedonia', _code: 'MKD', _name: 'Denar', _symbol: null},
  {_country: 'Moldova', _code: 'MDL', _name: 'Moldovan Leu', _symbol: null},
  {_country: 'Ukraine', _code: 'UAH', _name: 'Hryvnia', _symbol: '₴'},
  {_country: 'Argentina', _code: 'ARS', _name: 'Argentine Peso', _symbol: r'$'},
  {_country: 'Bolivia', _code: 'BOB', _name: 'Boliviano', _symbol: 'Bs.'},
  {_country: 'Brazil', _code: 'BRL', _name: 'Brazilian Real', _symbol: r'R$'},
  {_country: 'Chile', _code: 'CLP', _name: 'Chilean Peso', _symbol: r'$'},
  {_country: 'Colombia', _code: 'COP', _name: 'Colombian Peso', _symbol: r'$'},
  {_country: 'Guyana', _code: 'GYD', _name: 'Guyanese Dollar', _symbol: r'G$'},
  {_country: 'Paraguay', _code: 'PYG', _name: 'Guaraní', _symbol: '₲'},
  {_country: 'Peru', _code: 'PEN', _name: 'Sol', _symbol: 'S/'},
  {
    _country: 'Suriname',
    _code: 'SRD',
    _name: 'Surinamese Dollar',
    _symbol: r'$'
  },
  {_country: 'Uruguay', _code: 'UYU', _name: 'Uruguayan Peso', _symbol: r'$U'},
  {_country: 'Venezuela', _code: 'VES', _name: 'Bolívar', _symbol: 'Bs.'},
];

const _expectedCodes = <String>{
  'USD',
  'CAD',
  'MXN',
  'EUR',
  'GBP',
  'CHF',
  'PLN',
  'CZK',
  'HUF',
  'DKK',
  'SEK',
  'NOK',
  'ISK',
  'RON',
  'RSD',
  'ALL',
  'MKD',
  'MDL',
  'UAH',
  'ARS',
  'BOB',
  'BRL',
  'CLP',
  'COP',
  'GYD',
  'PYG',
  'PEN',
  'SRD',
  'UYU',
  'VES'
};

void main() {
  test('shortlist contains the exact 30 unique ISO codes', () {
    final codes = BandCurrency.shortlist.map((entry) => entry.isoCode);

    expect(BandCurrency.shortlist, hasLength(30));
    expect(codes.toSet(), hasLength(30));
    expect(codes.toSet(), _expectedCodes);
    expect(BandCurrency.byIsoCode, hasLength(30));
    expect(BandCurrency.byIsoCode.keys.toSet(), _expectedCodes);
    expect(BandCurrency.defaultCode, 'USD');
  });

  test('shortlist matches the exact 30-record ordered contract', () {
    for (var index = 0; index < _expectedCurrencies.length; index++) {
      final actual = BandCurrency.shortlist[index];
      final expected = _expectedCurrencies[index];

      expect(actual.countryLabel, expected['countryLabel'],
          reason: 'index $index');
      expect(actual.isoCode, expected['isoCode'], reason: 'index $index');
      expect(actual.name, expected['name'], reason: 'index $index');
      expect(actual.symbol, expected['symbol'], reason: 'index $index');
    }
  });

  test('USD is a single United States row in America', () {
    final usd = BandCurrency.byIsoCode['USD']!;

    expect(usd.countryLabel, 'United States');
    expect(usd.group, 'America');
    expect(
      BandCurrency.shortlist.where((entry) => entry.isoCode == 'USD'),
      hasLength(1),
    );
  });

  test('EUR preserves the Bulgaria composite mapping in Europe', () {
    final eur = BandCurrency.byIsoCode['EUR']!;

    expect(eur.countryLabel, 'Eurozone / Bulgaria');
    expect(eur.countryLabel, contains('Bulgaria'));
    expect(eur.group, 'Europe');
    expect(
      BandCurrency.shortlist.where((entry) => entry.isoCode == 'EUR'),
      hasLength(1),
    );
  });

  group('formatCents and symbolFor', () {
    test('symbol lookup uses configured symbols and ISO fallback', () {
      expect(BandCurrency.symbolFor('USD'), r'$');
      expect(BandCurrency.symbolFor('MXN'), r'$');
      expect(BandCurrency.symbolFor('EUR'), '€');
      expect(BandCurrency.symbolFor('CHF'), 'CHF');
      expect(BandCurrency.symbolFor('RSD'), 'RSD');
      expect(BandCurrency.symbolFor('MKD'), 'MKD');
      expect(BandCurrency.symbolFor('MDL'), 'MDL');
      expect(BandCurrency.symbolFor('GYD'), r'G$');
    });

    test('formatCents formats the numeric portion with two decimals', () {
      expect(BandCurrency.formatCents(150000, 'USD'), r'$1,500.00');
      expect(BandCurrency.formatCents(150000, 'MXN'), r'$1,500.00');
      expect(BandCurrency.formatCents(150000, 'EUR'), '€1,500.00');
      expect(BandCurrency.formatCents(150000, 'GYD'), r'G$1,500.00');
      expect(BandCurrency.formatCents(150000, 'MDL'), 'MDL1,500.00');
      expect(BandCurrency.formatCents(0, 'USD'), r'$0.00');
      expect(BandCurrency.formatCents(99, 'USD'), r'$0.99');
    });
  });
}

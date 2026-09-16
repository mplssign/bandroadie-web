import 'package:intl/intl.dart';

class BandCurrency {
  const BandCurrency({
    required this.group,
    required this.countryLabel,
    required this.isoCode,
    required this.name,
    this.symbol,
  });

  final String group;
  final String countryLabel;
  final String isoCode;
  final String name;
  final String? symbol;

  String get pickerLabel => '$countryLabel — $name ($isoCode)';

  static const String defaultCode = 'USD';

  static const List<BandCurrency> shortlist = [
    BandCurrency(
      group: 'America',
      countryLabel: 'United States',
      isoCode: 'USD',
      name: 'US Dollar',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'America',
      countryLabel: 'Canada',
      isoCode: 'CAD',
      name: 'Canadian Dollar',
      symbol: r'C$',
    ),
    BandCurrency(
      group: 'America',
      countryLabel: 'Mexico',
      isoCode: 'MXN',
      name: 'Mexican Peso',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Eurozone / Bulgaria',
      isoCode: 'EUR',
      name: 'Euro',
      symbol: '€',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'United Kingdom',
      isoCode: 'GBP',
      name: 'Pound Sterling',
      symbol: '£',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Switzerland',
      isoCode: 'CHF',
      name: 'Swiss Franc',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Poland',
      isoCode: 'PLN',
      name: 'Złoty',
      symbol: 'zł',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Czechia',
      isoCode: 'CZK',
      name: 'Czech Koruna',
      symbol: 'Kč',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Hungary',
      isoCode: 'HUF',
      name: 'Forint',
      symbol: 'Ft',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Denmark',
      isoCode: 'DKK',
      name: 'Danish Krone',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Sweden',
      isoCode: 'SEK',
      name: 'Swedish Krona',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Norway',
      isoCode: 'NOK',
      name: 'Norwegian Krone',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Iceland',
      isoCode: 'ISK',
      name: 'Icelandic Króna',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Romania',
      isoCode: 'RON',
      name: 'Romanian Leu',
      symbol: 'lei',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Serbia',
      isoCode: 'RSD',
      name: 'Serbian Dinar',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Albania',
      isoCode: 'ALL',
      name: 'Lek',
      symbol: 'L',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'North Macedonia',
      isoCode: 'MKD',
      name: 'Denar',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Moldova',
      isoCode: 'MDL',
      name: 'Moldovan Leu',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Ukraine',
      isoCode: 'UAH',
      name: 'Hryvnia',
      symbol: '₴',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Argentina',
      isoCode: 'ARS',
      name: 'Argentine Peso',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Bolivia',
      isoCode: 'BOB',
      name: 'Boliviano',
      symbol: 'Bs.',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Brazil',
      isoCode: 'BRL',
      name: 'Brazilian Real',
      symbol: r'R$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Chile',
      isoCode: 'CLP',
      name: 'Chilean Peso',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Colombia',
      isoCode: 'COP',
      name: 'Colombian Peso',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Guyana',
      isoCode: 'GYD',
      name: 'Guyanese Dollar',
      symbol: r'G$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Paraguay',
      isoCode: 'PYG',
      name: 'Guaraní',
      symbol: '₲',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Peru',
      isoCode: 'PEN',
      name: 'Sol',
      symbol: 'S/',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Suriname',
      isoCode: 'SRD',
      name: 'Surinamese Dollar',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Uruguay',
      isoCode: 'UYU',
      name: 'Uruguayan Peso',
      symbol: r'$U',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Venezuela',
      isoCode: 'VES',
      name: 'Bolívar',
      symbol: 'Bs.',
    ),
  ];

  static final Map<String, BandCurrency> byIsoCode = Map.unmodifiable({
    for (final currency in shortlist) currency.isoCode: currency,
  });

  static String symbolFor(String code) => byIsoCode[code]?.symbol ?? code;

  static String formatCents(int cents, String code) {
    final amount = NumberFormat('#,##0.00', 'en_US').format(cents / 100);
    return '${symbolFor(code)}$amount';
  }

  static List<BandCurrencyPickerGroup> pickerGroups() => [
        for (final groupLabel in const [
          'America',
          'Europe',
          'South America',
        ])
          BandCurrencyPickerGroup(
            label: groupLabel,
            items: {
              for (final currency
                  in shortlist.where((entry) => entry.group == groupLabel))
                currency.pickerLabel: currency.isoCode,
            },
          ),
      ];
}

class BandCurrencyPickerGroup {
  const BandCurrencyPickerGroup({
    required this.label,
    required this.items,
  });

  final String label;
  final Map<String, String> items;
}

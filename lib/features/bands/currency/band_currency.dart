import 'package:intl/intl.dart';

class BandCurrency {
  const BandCurrency({
    required this.group,
    required this.countryLabel,
    required this.isoCode,
    required this.locale,
    required this.name,
    this.symbol,
    this.forceSymbolPrefix = false,
  });

  final String group;
  final String countryLabel;
  final String isoCode;
  final String locale;
  final String name;
  final String? symbol;
  final bool forceSymbolPrefix;

  String get pickerLabel => '$countryLabel — $name ($isoCode)';
  String get glyph => symbol ?? isoCode;

  static const List<BandCurrency> shortlist = [
    BandCurrency(
      group: 'America',
      countryLabel: 'United States',
      isoCode: 'USD',
      locale: 'en_US',
      name: 'US Dollar',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'America',
      countryLabel: 'Ecuador',
      isoCode: 'USD',
      locale: 'es_EC',
      name: 'US Dollar',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'America',
      countryLabel: 'Canada',
      isoCode: 'CAD',
      locale: 'en_CA',
      name: 'Canadian Dollar',
      symbol: r'C$',
    ),
    BandCurrency(
      group: 'America',
      countryLabel: 'Mexico',
      isoCode: 'MXN',
      locale: 'es_MX',
      name: 'Mexican Peso',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Eurozone (generic)',
      isoCode: 'EUR',
      locale: 'de_DE',
      name: 'Euro',
      symbol: '€',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Bulgaria',
      isoCode: 'EUR',
      locale: 'bg_BG',
      name: 'Euro',
      symbol: '€',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'United Kingdom',
      isoCode: 'GBP',
      locale: 'en_GB',
      name: 'Pound Sterling',
      symbol: '£',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Switzerland',
      isoCode: 'CHF',
      locale: 'de_CH',
      name: 'Swiss Franc',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Poland',
      isoCode: 'PLN',
      locale: 'pl_PL',
      name: 'Złoty',
      symbol: 'zł',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Czechia',
      isoCode: 'CZK',
      locale: 'cs_CZ',
      name: 'Czech Koruna',
      symbol: 'Kč',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Hungary',
      isoCode: 'HUF',
      locale: 'hu_HU',
      name: 'Forint',
      symbol: 'Ft',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Denmark',
      isoCode: 'DKK',
      locale: 'da_DK',
      name: 'Danish Krone',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Sweden',
      isoCode: 'SEK',
      locale: 'sv_SE',
      name: 'Swedish Krona',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Norway',
      isoCode: 'NOK',
      locale: 'nb_NO',
      name: 'Norwegian Krone',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Iceland',
      isoCode: 'ISK',
      locale: 'is_IS',
      name: 'Icelandic Króna',
      symbol: 'kr',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Romania',
      isoCode: 'RON',
      locale: 'ro_RO',
      name: 'Romanian Leu',
      symbol: 'lei',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Serbia',
      isoCode: 'RSD',
      locale: 'sr_RS',
      name: 'Serbian Dinar',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Albania',
      isoCode: 'ALL',
      locale: 'sq_AL',
      name: 'Lek',
      symbol: 'L',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'North Macedonia',
      isoCode: 'MKD',
      locale: 'mk_MK',
      name: 'Denar',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Moldova',
      isoCode: 'MDL',
      locale: 'ro_MD',
      name: 'Moldovan Leu',
    ),
    BandCurrency(
      group: 'Europe',
      countryLabel: 'Ukraine',
      isoCode: 'UAH',
      locale: 'uk_UA',
      name: 'Hryvnia',
      symbol: '₴',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Argentina',
      isoCode: 'ARS',
      locale: 'es_AR',
      name: 'Argentine Peso',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Bolivia',
      isoCode: 'BOB',
      locale: 'es_BO',
      name: 'Boliviano',
      symbol: 'Bs.',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Brazil',
      isoCode: 'BRL',
      locale: 'pt_BR',
      name: 'Brazilian Real',
      symbol: r'R$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Chile',
      isoCode: 'CLP',
      locale: 'es_CL',
      name: 'Chilean Peso',
      symbol: r'$',
      forceSymbolPrefix: true,
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Colombia',
      isoCode: 'COP',
      locale: 'es_CO',
      name: 'Colombian Peso',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Guyana',
      isoCode: 'GYD',
      locale: 'en_GY',
      name: 'Guyanese Dollar',
      symbol: r'G$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Paraguay',
      isoCode: 'PYG',
      locale: 'es_PY',
      name: 'Guaraní',
      symbol: '₲',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Peru',
      isoCode: 'PEN',
      locale: 'es_PE',
      name: 'Sol',
      symbol: 'S/',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Suriname',
      isoCode: 'SRD',
      locale: 'nl_SR',
      name: 'Surinamese Dollar',
      symbol: r'$',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Uruguay',
      isoCode: 'UYU',
      locale: 'es_UY',
      name: 'Uruguayan Peso',
      symbol: r'$U',
    ),
    BandCurrency(
      group: 'South America',
      countryLabel: 'Venezuela',
      isoCode: 'VES',
      locale: 'es_VE',
      name: 'Bolívar',
      symbol: 'Bs.',
    ),
  ];

  static final Map<String, BandCurrency> byIsoCode = Map.unmodifiable({
    for (final currency in shortlist) currency.isoCode: currency,
  });

  static final Map<String, BandCurrency> byLocale = Map.unmodifiable({
    for (final currency in shortlist) currency.locale: currency,
  });

  static const BandCurrency fallback = BandCurrency(
    group: 'America',
    countryLabel: 'United States',
    isoCode: 'USD',
    locale: 'en_US',
    name: 'US Dollar',
    symbol: r'$',
  );

  String format(int cents) {
    if (forceSymbolPrefix) {
      final number = NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: 2,
      ).format(cents / 100);
      return '$glyph$number';
    }

    return NumberFormat.currency(
      locale: locale,
      symbol: glyph,
      decimalDigits: 2,
    ).format(cents / 100);
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
                currency.pickerLabel: currency.locale,
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

import 'package:bandroadie/features/bands/currency/band_currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortlist contains all 32 locale-specific currency entries', () {
    expect(BandCurrency.shortlist, hasLength(32));
    expect(BandCurrency.byLocale, hasLength(32));
    expect(
        BandCurrency.byLocale.keys,
        containsAll(<String>[
          'en_US',
          'es_EC',
          'en_CA',
          'es_MX',
          'de_DE',
          'bg_BG',
          'en_GB',
          'de_CH',
          'pl_PL',
          'cs_CZ',
          'hu_HU',
          'da_DK',
          'sv_SE',
          'nb_NO',
          'is_IS',
          'ro_RO',
          'sr_RS',
          'sq_AL',
          'mk_MK',
          'ro_MD',
          'uk_UA',
          'es_AR',
          'es_BO',
          'pt_BR',
          'es_CL',
          'es_CO',
          'en_GY',
          'es_PY',
          'es_PE',
          'nl_SR',
          'es_UY',
          'es_VE',
        ]));
    expect(BandCurrency.byIsoCode, hasLength(30));
    expect(BandCurrency.byIsoCode['USD'], isNotNull);
    expect(BandCurrency.byIsoCode['EUR'], isNotNull);
    expect(BandCurrency.fallback.locale, 'en_US');
  });

  test('formats amounts with each currency locale convention', () {
    expect(BandCurrency.byLocale['en_US']!.format(123450), r'$1,234.50');
    expect(BandCurrency.byLocale['de_DE']!.format(123450), '1.234,50 €');
    expect(BandCurrency.byLocale['es_CL']!.format(123450), r'$1.234,50');
    expect(
        BandCurrency.byLocale['de_CH']!.format(123450), contains("1'234.50"));
    expect(BandCurrency.byLocale['de_CH']!.format(123450), contains('CHF'));
    expect(BandCurrency.byLocale['en_US']!.format(123500), r'$1,235.00');
    expect(BandCurrency.byLocale['de_CH']!.glyph, 'CHF');
    expect(BandCurrency.byLocale['sr_RS']!.glyph, 'RSD');
    expect(BandCurrency.byLocale['es_CL']!.forceSymbolPrefix, isTrue);
    expect(BandCurrency.byLocale['es_AR']!.forceSymbolPrefix, isFalse);
    expect(BandCurrency.byLocale['de_DE']!.forceSymbolPrefix, isFalse);
    expect(BandCurrency.byLocale['es_AR']!.format(123450), '1.234,50 \$');
  });
}

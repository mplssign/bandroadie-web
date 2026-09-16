import 'package:bandroadie/features/bands/currency/band_currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picker groups have the exact order and cardinalities', () {
    final groups = BandCurrency.pickerGroups();

    expect(groups.map((group) => group.label), [
      'America',
      'Europe',
      'South America',
    ]);
    expect(groups, hasLength(3));
    expect(groups[0].items, hasLength(4));
    expect(groups[1].items, hasLength(17));
    expect(groups[2].items, hasLength(11));
  });

  test('picker rows have globally unique labels and locale values', () {
    final groups = BandCurrency.pickerGroups();
    final entries = groups.expand((group) => group.items.entries).toList();

    expect(entries, hasLength(32));
    expect(entries.map((entry) => entry.key).toSet(), hasLength(32));
    expect(entries.map((entry) => entry.value).toSet(), hasLength(32));
  });

  test('USD and EUR each have two distinct country rows', () {
    final groups = BandCurrency.pickerGroups();

    final usdRows = groups
        .expand((group) => group.items.entries)
        .where((entry) => entry.key.contains('(USD)'));
    final eurRows = groups
        .expand((group) => group.items.entries)
        .where((entry) => entry.key.contains('(EUR)'));

    expect(usdRows, hasLength(2));
    expect(
      usdRows.map((e) => e.key).toSet(),
      {'United States — US Dollar (USD)', 'Ecuador — US Dollar (USD)'},
    );
    expect(eurRows, hasLength(2));
    expect(
      eurRows.map((e) => e.key).toSet(),
      {'Eurozone (generic) — Euro (EUR)', 'Bulgaria — Euro (EUR)'},
    );
  });

  test(
      'Ecuador and Bulgaria are their own distinct rows, each with the '
      'correct locale', () {
    final groups = BandCurrency.pickerGroups();
    final americaItems = groups.firstWhere((g) => g.label == 'America').items;
    final europeItems = groups.firstWhere((g) => g.label == 'Europe').items;

    expect(americaItems['Ecuador — US Dollar (USD)'], 'es_EC');
    expect(europeItems['Bulgaria — Euro (EUR)'], 'bg_BG');
  });
}

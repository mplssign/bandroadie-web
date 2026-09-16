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
    expect(groups[0].items, hasLength(3));
    expect(groups[1].items, hasLength(16));
    expect(groups[2].items, hasLength(11));
  });

  test('picker rows have globally unique labels and ISO values', () {
    final groups = BandCurrency.pickerGroups();
    final entries = groups.expand((group) => group.items.entries).toList();

    expect(entries, hasLength(30));
    expect(entries.map((entry) => entry.key).toSet(), hasLength(30));
    expect(entries.map((entry) => entry.value).toSet(), hasLength(30));
  });

  test('USD and EUR use one exact composite row in the correct group', () {
    final groups = BandCurrency.pickerGroups();

    final usdGroups = groups.where((group) => group.items.containsValue('USD'));
    final eurGroups = groups.where((group) => group.items.containsValue('EUR'));

    expect(usdGroups, hasLength(1));
    expect(usdGroups.single.label, 'America');
    expect(
      usdGroups.single.items['United States — US Dollar (USD)'],
      'USD',
    );
    expect(eurGroups, hasLength(1));
    expect(eurGroups.single.label, 'Europe');
    expect(
      eurGroups.single.items['Eurozone / Bulgaria — Euro (EUR)'],
      'EUR',
    );
  });

  test('Bulgaria retains composite row and Ecuador is fully absent', () {
    final labels = BandCurrency.pickerGroups()
        .expand((group) => group.items.keys)
        .toList();

    expect(labels, isNot(contains(matches(RegExp(r'^Bulgaria —')))));
    expect(labels, everyElement(isNot(contains('Ecuador'))));
  });
}

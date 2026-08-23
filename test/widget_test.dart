import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dummy test', () {
    expect(1 + 1, 2);
  });

  test('intentional failure for CI negative test', () {
    expect(1, equals(2)); // This will fail
  });
}

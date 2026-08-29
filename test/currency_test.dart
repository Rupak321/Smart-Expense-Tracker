import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/app_currency.dart';
import 'package:smartexpense/core/utils/money_utils.dart';

void main() {
  // Every test restores the default, since MoneyUtils.currency is global.
  tearDown(() => MoneyUtils.currency = AppCurrency.nepaleseRupee);

  group('South Asian grouping', () {
    const grouping = DigitGrouping.southAsian;

    test('three digits or fewer are untouched', () {
      expect(grouping.format(5), '5');
      expect(grouping.format(999), '999');
    });

    test('the last three stay together, then pairs', () {
      expect(grouping.format(1000), '1,000');
      expect(grouping.format(12345), '12,345');
      expect(grouping.format(123456), '1,23,456');
    });

    test('a lakh and a crore group the way they are named', () {
      expect(grouping.format(100000), '1,00,000');
      expect(grouping.format(10000000), '1,00,00,000');
    });

    test('the balance from the app reads the Nepali way', () {
      // This showed as "8,538,550" before, while the same screen described
      // large figures in lakhs.
      expect(grouping.format(8538550), '85,38,550');
    });
  });

  group('western grouping', () {
    const grouping = DigitGrouping.western;

    test('threes all the way up', () {
      expect(grouping.format(1000), '1,000');
      expect(grouping.format(123456), '123,456');
      expect(grouping.format(8538550), '8,538,550');
      expect(grouping.format(1000000000), '1,000,000,000');
    });
  });

  group('formatting follows the selected currency', () {
    test('rupees keep the symbol and South Asian grouping', () {
      expect(MoneyUtils.formatPaisa(853855000), 'Rs. 85,38,550');
    });

    test('dollars switch both symbol and grouping', () {
      MoneyUtils.currency = AppCurrency.usDollar;
      expect(MoneyUtils.formatPaisa(853855000), r'$8,538,550');
    });

    test('a glyph symbol takes no space, a word-like one does', () {
      MoneyUtils.currency = AppCurrency.euro;
      expect(MoneyUtils.formatPaisa(10000), '€100');

      MoneyUtils.currency = AppCurrency.nepaleseRupee;
      expect(MoneyUtils.formatPaisa(10000), 'Rs. 100');
    });

    test('paisa are still shown when present', () {
      expect(MoneyUtils.formatPaisa(1250), 'Rs. 12.50');
    });

    test('the minus sits outside the symbol', () {
      expect(MoneyUtils.formatPaisa(-50000), '-Rs. 500');
    });
  });

  group('compact form', () {
    test('rupees read in thousands, lakhs and crores', () {
      expect(MoneyUtils.formatCompactPaisa(1240000), 'Rs. 12.4k');
      expect(MoneyUtils.formatCompactPaisa(12000000), 'Rs. 1.2L');
      expect(MoneyUtils.formatCompactPaisa(1200000000), 'Rs. 1.2Cr');
    });

    test('dollars read in K, M and B instead', () {
      MoneyUtils.currency = AppCurrency.usDollar;
      expect(MoneyUtils.formatCompactPaisa(1240000), r'$12.4K');
      expect(MoneyUtils.formatCompactPaisa(1200000000), r'$12.0M');
    });

    test('small amounts are not abbreviated', () {
      expect(MoneyUtils.formatCompactPaisa(45000), 'Rs. 450');
    });
  });

  group('choosing a currency', () {
    test('an unknown or missing code falls back to rupees', () {
      expect(AppCurrency.fromCode('XYZ'), AppCurrency.nepaleseRupee);
      expect(AppCurrency.fromCode(null), AppCurrency.nepaleseRupee);
    });

    test('a known code resolves to itself', () {
      expect(AppCurrency.fromCode('USD'), AppCurrency.usDollar);
    });

    test('every supported currency has a distinct code', () {
      final codes = AppCurrency.supported.map((c) => c.code).toSet();
      expect(codes, hasLength(AppCurrency.supported.length));
    });
  });
}

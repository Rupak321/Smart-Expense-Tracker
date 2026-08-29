import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/utils/money_utils.dart';

void main() {
  group('formatPaisa', () {
    test('does not emit a leading space', () {
      // The old implementation built '$sign Rs. ...' with an empty sign, so
      // every tile rendered "-  Rs. 500" with a double space.
      expect(MoneyUtils.formatPaisa(50000), 'Rs. 500');
      expect(MoneyUtils.formatPaisa(50000).startsWith(' '), isFalse);
    });

    test('keeps the minus sign attached', () {
      expect(MoneyUtils.formatPaisa(-50000), '-Rs. 500');
    });

    // This used to group in threes (194,550 / 1,000,000) while
    // formatCompactPaisa abbreviated with lakh and crore, so one screen could
    // show the same magnitude two different ways. Both now follow the
    // selected currency, which for rupees is the South Asian system.
    test('groups digits the South Asian way for rupees', () {
      expect(MoneyUtils.formatPaisa(19455000), 'Rs. 1,94,550');
      expect(MoneyUtils.formatPaisa(100000000), 'Rs. 10,00,000');
    });

    test('shows paisa only when non-zero', () {
      expect(MoneyUtils.formatPaisa(45050), 'Rs. 450.50');
      expect(MoneyUtils.formatPaisa(45000), 'Rs. 450');
    });
  });

  group('formatCompactPaisa', () {
    test('abbreviates by Indian magnitude', () {
      expect(MoneyUtils.formatCompactPaisa(45000), 'Rs. 450');
      expect(MoneyUtils.formatCompactPaisa(1234500), 'Rs. 12.3k');
      expect(MoneyUtils.formatCompactPaisa(15000000), 'Rs. 1.5L');
      expect(MoneyUtils.formatCompactPaisa(2500000000), 'Rs. 2.5Cr');
    });

    test('stays short enough for a chart axis gutter', () {
      for (final paisa in [0, 999, 99999, 9999999, 999999999]) {
        expect(MoneyUtils.formatCompactPaisa(paisa).length, lessThanOrEqualTo(12));
      }
    });

    test('keeps the sign', () {
      expect(MoneyUtils.formatCompactPaisa(-1234500), '-Rs. 12.3k');
    });
  });

  group('parseToPaisa', () {
    test('round-trips through formatting', () {
      expect(MoneyUtils.parseToPaisa('450.50'), 45050);
      expect(MoneyUtils.parseToPaisa('1,234'), 123400);
    });
  });
}

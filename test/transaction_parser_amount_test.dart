import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/parser/transaction_parser_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final parser = TransactionParserService();

  Future<double> amountOf(String input) async {
    final parsed = await parser.parse(input);
    return parsed.amount;
  }

  group('amount extraction', () {
    test('reads a single plain amount', () async {
      expect(await amountOf('spent 500 on lunch'), 500);
    });

    test('does not glue a quantity onto the amount', () async {
      // Previously every non-digit was stripped and the remainder parsed, so
      // this returned 5002.
      expect(await amountOf('spent 500 on 2 coffees'), 500);
      expect(await amountOf('bought 3 shirts for 1200'), 1200);
    });

    test('ignores a year in the text', () async {
      // Previously became 12002026.
      expect(await amountOf('paid 1200 rent for july 2026'), 1200);
    });

    test('ignores a date', () async {
      expect(await amountOf('450 lunch on 24/07/2026'), 450);
    });

    test('handles k and lakh shorthand', () async {
      expect(await amountOf('got 45k salary'), 45000);
      expect(await amountOf('paid 1.5 lakh for the car'), 150000);
    });

    test('handles a thousands separator', () async {
      expect(await amountOf('spent 1,200 on groceries'), 1200);
    });

    test('keeps decimals', () async {
      expect(await amountOf('spent 99.50 on coffee'), 99.5);
    });

    test('returns zero when there is no number', () async {
      expect(await amountOf('had lunch with friends'), 0);
    });

    test('falls back to a year when it is the only number', () async {
      // Not a sensible amount, but better than silently reporting zero.
      expect(await amountOf('spent 2000'), 2000);
    });
  });

  group('direction', () {
    test('classifies clear spending as an expense', () async {
      final parsed = await parser.parse('spent 500 on lunch');
      expect(parsed.type, TransactionType.expense);
    });

    test('classifies clear earning as income', () async {
      final parsed = await parser.parse('got 45000 salary from office');
      expect(parsed.type, TransactionType.income);
    });
  });
}

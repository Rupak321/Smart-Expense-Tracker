import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/parser/transaction_parser_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TransactionParserService parser;

  setUp(() {
    parser = TransactionParserService();
  });

  test('uses direction-aware rules for minimal pairs', () async {
    final gaveToMom = await parser.parse('gave mom 500');
    expect(gaveToMom.type, TransactionType.expense);
    expect(gaveToMom.confidence, greaterThanOrEqualTo(0.8));

    final momGaveMe = await parser.parse('mom gave me 500');
    expect(momGaveMe.type, TransactionType.income);
    expect(momGaveMe.confidence, greaterThanOrEqualTo(0.8));
  });

  test('handles Nepali relation aliases', () async {
    final aama = await parser.parse('aama le paisa diyo 500');
    expect(aama.type, TransactionType.income);

    final buwa = await parser.parse('buwa le paisa diyo 500');
    expect(buwa.type, TransactionType.income);

    final maile = await parser.parse('maile paisa dincha 500');
    expect(maile.type, TransactionType.expense);
  });

  test('normalizes shorthand amounts', () async {
    final parsed = await parser.parse('45k');
    expect(parsed.amount, 45000);

    final parsed2 = await parser.parse('1.5k');
    expect(parsed2.amount, 1500);

    final parsed3 = await parser.parse('12,000');
    expect(parsed3.amount, 12000);

    final parsed4 = await parser.parse('1 lakh');
    expect(parsed4.amount, 100000);

    final parsed5 = await parser.parse('1L');
    expect(parsed5.amount, 100000);
  });
}

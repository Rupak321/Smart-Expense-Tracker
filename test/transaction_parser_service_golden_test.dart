import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/parser/transaction_parser_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes shorthand amounts', () async {
    final parser = TransactionParserService();
    final result1 = await parser.parse('45k');
    final result2 = await parser.parse('1.5k');
    final result3 = await parser.parse('12,000');
    final result4 = await parser.parse('1 lakh');
    final result5 = await parser.parse('1L');

    expect(result1.amount, 45000);
    expect(result2.amount, 1500);
    expect(result3.amount, 12000);
    expect(result4.amount, 100000);
    expect(result5.amount, 100000);
  });
}

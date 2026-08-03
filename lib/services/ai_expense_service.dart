import '../core/parser/transaction_parser_service.dart';

class AiExpenseResult {
  final String title;
  final double amount;
  final String category;
  final bool isExpense;

  AiExpenseResult({
    required this.title,
    required this.amount,
    required this.category,
    required this.isExpense,
  });
}

class AiExpenseService {
  static Future<AiExpenseResult?> parseExpense(String input) async {
    final parsed = await TransactionParserService().parse(input);
    if (parsed.amount <= 0) {
      return null;
    }

    return AiExpenseResult(
      title: parsed.title,
      amount: parsed.amount,
      category: parsed.category,
      isExpense: parsed.type == TransactionType.expense,
    );
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/secrets.dart';

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
    if (Secrets.groqApiKey.isEmpty || !Secrets.groqApiKey.startsWith('gsk_')) {
      throw Exception('Please provide a valid Groq API Key in lib/core/secrets.dart');
    }

    final prompt = '''
You are a highly intelligent financial assistant for Smart Expense. I will provide a raw text string representing either an expense or an income.
Your goal is to extract the exact amount, a short descriptive title, a transaction type, and an intelligent granular category.
Do not use preset categories. Decide the best category in the format "Parent Category - Subcategory" (e.g., "Shopping - Clothes", "Food - Restaurant", "Bills - Electricity", "Income - Salary", "Income - Family").

Important type rules:
- Money received is income: salary, earned, got paid, credited, refund, reimbursement, bonus, commission, cash from someone, mom/dad/family/friend gave or sent money to the user.
- Money paid out is expense: spent, bought, paid to someone, sent money to someone, bills, rent, food, shopping, fees.
- "mom gave me 500", "cash from mom 500", "dad sent 1000" are income.
- "gave mom 500", "paid dad 1000", "sent money to friend" are expenses.

Input text: "$input"

Return the result STRICTLY as a valid JSON object with no markdown formatting and no extra text, using these exact keys:
{
  "amount": <number>,
  "title": "<string>",
  "category": "<string>",
  "type": "expense|income"
}
''';

    try {
      final response = await http.post(
        Uri.https('api.groq.com', '/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${Secrets.groqApiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': Secrets.groqModel,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.1,
          'response_format': {'type': 'json_object'}
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Groq API Error: ${response.statusCode} ${response.body}');
      }

      final data = jsonDecode(response.body);
      final text = data['choices']?[0]?['message']?['content'];
      if (text == null) return null;

      // Clean up markdown if model returned it despite instructions
      String jsonStr = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> resultData = jsonDecode(jsonStr);
      
      final parsedType = resultData['type']?.toString().toLowerCase();
      final inferredType = _inferIsExpense(
        input: input,
        title: resultData['title']?.toString() ?? '',
        category: resultData['category']?.toString() ?? '',
      );

      return AiExpenseResult(
        title: resultData['title'] ?? 'Smart Expense',
        amount: (resultData['amount'] as num?)?.toDouble() ?? 0.0,
        category: resultData['category'] ?? 'Other - Uncategorised',
        isExpense:
            inferredType ?? (parsedType == 'income' ? false : true),
      );
    } catch (e) {
      throw Exception('Failed to parse expense using Groq AI.');
    }
  }

  static bool? _inferIsExpense({
    required String input,
    required String title,
    required String category,
  }) {
    final text = '$input $title $category'.toLowerCase();

    final outgoingPatterns = [
      RegExp(r'\b(gave|give|sent|send|paid|pay|transferred|transfer)\s+(to\s+)?(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
      RegExp(r'\b(to|for)\s+(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
    ];
    if (outgoingPatterns.any((pattern) => pattern.hasMatch(text))) {
      return true;
    }

    final incomingPatterns = [
      RegExp(r'\b(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\s+(gave|sent|paid|transferred|send)\b'),
      RegExp(r'\b(cash|money|payment|transfer)\s+from\s+(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
      RegExp(r'\b(got|received|recieved)\s+.*\bfrom\s+\w+'),
      RegExp(r'\b(gave|sent|paid|transferred)\s+me\b'),
    ];
    if (incomingPatterns.any((pattern) => pattern.hasMatch(text))) {
      return false;
    }

    const incomeSignals = [
      'salary',
      'paycheck',
      'pay cheque',
      'income',
      'earned',
      'earning',
      'received',
      'recieved',
      'credited',
      'freelance',
      'business income',
      'bonus',
      'commission',
      'deposit',
      'refund',
      'reimbursement',
      'allowance',
      'pocket money',
      'cash from',
    ];
    const expenseSignals = [
      'spent',
      'spend',
      'paid',
      'payment',
      'bought',
      'purchase',
      'expense',
      'bill',
      'rent',
      'emi',
      'fee',
      'charge',
    ];

    final hasIncomeSignal = incomeSignals.any(text.contains);
    final hasExpenseSignal = expenseSignals.any(text.contains);
    if (hasIncomeSignal && !hasExpenseSignal) {
      return false;
    }
    if (hasExpenseSignal && !hasIncomeSignal) {
      return true;
    }
    return null;
  }
}

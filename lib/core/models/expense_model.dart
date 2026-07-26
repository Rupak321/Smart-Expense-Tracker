import '../utils/money_utils.dart';

class ExpenseModel {
  final String id;
  final String title;
  final double amount;
  final String category; // e.g., 'Food', 'Travel', 'Shopping'
  final DateTime date;
  final bool isExpense; // true for expense, false for income

  ExpenseModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.isExpense,
  });

  int get amountPaisa => MoneyUtils.amountToPaisa(amount);
}
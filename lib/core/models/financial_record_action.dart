import 'expense_model.dart';

class FinancialActionParseResult {
  final FinancialRecordAction? action;
  final String? clarification;

  const FinancialActionParseResult({this.action, this.clarification});
}

class FinancialRecordAction {
  final FinancialActionType type;
  final ExpenseModel? oldRecord;
  final ExpenseModel? newRecord;
  final String? targetId;

  /// Set when the category on [newRecord] does not exist yet.
  ///
  /// Creating categories used to happen invisibly — the assistant stored
  /// whatever name it invented, which is how one kind of spending ended up
  /// under several. A new category is now surfaced in the confirmation so it
  /// is a deliberate choice.
  final String? newCategoryName;

  /// Direction the new category should accept, when one is being created.
  final bool newCategoryIsExpense;

  const FinancialRecordAction({
    required this.type,
    this.oldRecord,
    this.newRecord,
    this.targetId,
    this.newCategoryName,
    this.newCategoryIsExpense = true,
  });

  bool get createsCategory => newCategoryName != null;
}

enum FinancialActionType { add, update, delete }

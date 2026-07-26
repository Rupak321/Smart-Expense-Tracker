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

  const FinancialRecordAction({
    required this.type,
    this.oldRecord,
    this.newRecord,
    this.targetId,
  });
}

enum FinancialActionType { add, update, delete }

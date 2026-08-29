import 'package:flutter_test/flutter_test.dart';
import 'package:smartexpense/core/models/budget.dart';
import 'package:smartexpense/core/models/expense_model.dart';
import 'package:smartexpense/core/models/financial_insights.dart';
import 'package:smartexpense/core/models/money_account.dart';
import 'package:smartexpense/services/financial_insights_service.dart';

final now = DateTime(2026, 8, 15);

MoneyAccount account(String id, {int opening = 0}) {
  return MoneyAccount(
    id: id,
    name: id,
    kind: AccountKind.cash,
    openingBalancePaisa: opening,
    createdAt: DateTime(2026, 1, 1),
  );
}

ExpenseModel tx({
  required int rupees,
  required bool isExpense,
  String? accountId,
  String? transferGroupId,
  String category = 'Other',
  DateTime? date,
}) {
  return ExpenseModel(
    id: '$rupees$isExpense$accountId$transferGroupId${date ?? now}',
    title: 'row',
    amount: rupees.toDouble(),
    category: category,
    date: date ?? DateTime(2026, 8, 10),
    isExpense: isExpense,
    accountId: accountId,
    transferGroupId: transferGroupId,
  );
}

/// The two rows a transfer is stored as.
List<ExpenseModel> transfer({
  required int rupees,
  required String from,
  required String to,
  String group = 'g1',
}) {
  return [
    tx(rupees: rupees, isExpense: true, accountId: from, transferGroupId: group),
    tx(rupees: rupees, isExpense: false, accountId: to, transferGroupId: group),
  ];
}

void main() {
  group('what a transfer is', () {
    test('both halves are marked as a transfer', () {
      final rows = transfer(rupees: 10000, from: 'cash', to: 'bank');
      expect(rows.every((r) => r.isTransfer), isTrue);
    });

    test('neither half counts as real income or spending', () {
      final rows = transfer(rupees: 10000, from: 'cash', to: 'bank');
      expect(rows.any((r) => r.countsAsExpense), isFalse);
      expect(rows.any((r) => r.countsAsIncome), isFalse);
    });

    test('an ordinary transaction still counts on its own side', () {
      expect(tx(rupees: 500, isExpense: true).countsAsExpense, isTrue);
      expect(tx(rupees: 500, isExpense: true).countsAsIncome, isFalse);
      expect(tx(rupees: 500, isExpense: false).countsAsIncome, isTrue);
      expect(tx(rupees: 500, isExpense: false).isTransfer, isFalse);
    });
  });

  group('balances', () {
    test('opening balance is the starting point', () {
      final result = AccountCalculator.balances(
        accounts: [account('cash', opening: 500000)],
        transactions: const [],
      );
      expect(result.single.balancePaisa, 500000);
    });

    test('income adds and spending subtracts', () {
      final result = AccountCalculator.balances(
        accounts: [account('cash')],
        transactions: [
          tx(rupees: 1000, isExpense: false, accountId: 'cash'),
          tx(rupees: 300, isExpense: true, accountId: 'cash'),
        ],
      );
      expect(result.single.balancePaisa, 700 * 100);
    });

    test('a transfer moves money between the two balances', () {
      // This is the case accounts exist for, and the one place a transfer
      // must count: it is not income or spending, but it certainly changes
      // what each account holds.
      final result = AccountCalculator.balances(
        accounts: [
          account('cash', opening: 2000000),
          account('bank', opening: 0),
        ],
        transactions: transfer(rupees: 5000, from: 'cash', to: 'bank'),
      );

      final byName = {for (final b in result) b.account.id: b.balancePaisa};
      expect(byName['cash'], 2000000 - 500000);
      expect(byName['bank'], 500000);
    });

    test('a transfer leaves the combined total untouched', () {
      final result = AccountCalculator.balances(
        accounts: [account('cash', opening: 2000000), account('bank')],
        transactions: transfer(rupees: 5000, from: 'cash', to: 'bank'),
      );

      expect(result.fold(0, (sum, b) => sum + b.balancePaisa), 2000000);
    });

    test('transactions belonging to another account are not counted', () {
      final result = AccountCalculator.balances(
        accounts: [account('cash'), account('bank')],
        transactions: [tx(rupees: 900, isExpense: true, accountId: 'bank')],
      );

      final byName = {for (final b in result) b.account.id: b.balancePaisa};
      expect(byName['cash'], 0);
      expect(byName['bank'], -900 * 100);
    });

    test('unassigned records are reported, not silently dropped', () {
      final transactions = [
        tx(rupees: 100, isExpense: true, accountId: 'cash'),
        tx(rupees: 200, isExpense: true),
        tx(rupees: 300, isExpense: true),
      ];

      expect(AccountCalculator.unassignedCount(transactions), 2);
      final result = AccountCalculator.balances(
        accounts: [account('cash')],
        transactions: transactions,
      );
      expect(result.single.transactionCount, 1);
    });
  });

  group('transfers stay out of the figures', () {
    FinancialInsights insightsFor(List<ExpenseModel> transactions) {
      return FinancialInsightsService.compute(
        transactions: transactions,
        recurring: const [],
        bills: const [],
        now: now,
      );
    }

    test('all-time totals ignore both halves', () {
      final withoutTransfer = insightsFor([
        tx(rupees: 60000, isExpense: false),
        tx(rupees: 2000, isExpense: true),
      ]);
      final withTransfer = insightsFor([
        tx(rupees: 60000, isExpense: false),
        tx(rupees: 2000, isExpense: true),
        ...transfer(rupees: 25000, from: 'cash', to: 'bank'),
      ]);

      expect(withTransfer.totalIncomePaisa, withoutTransfer.totalIncomePaisa);
      expect(withTransfer.totalExpensePaisa, withoutTransfer.totalExpensePaisa);
      expect(withTransfer.balancePaisa, withoutTransfer.balancePaisa);
    });

    test('the month snapshot ignores them too, including the count', () {
      final plain = insightsFor([
        tx(rupees: 60000, isExpense: false, date: DateTime(2026, 8, 2)),
      ]);
      final withTransfer = insightsFor([
        tx(rupees: 60000, isExpense: false, date: DateTime(2026, 8, 2)),
        ...transfer(rupees: 25000, from: 'cash', to: 'bank'),
      ]);

      expect(
        withTransfer.thisMonth.expensePaisa,
        plain.thisMonth.expensePaisa,
      );
      expect(withTransfer.thisMonth.incomePaisa, plain.thisMonth.incomePaisa);
      expect(
        withTransfer.thisMonth.transactionCount,
        plain.thisMonth.transactionCount,
      );
    });

    test('the savings rate is not wrecked by moving money around', () {
      // Earn 60,000, spend 2,000, then shuffle 25,000 into savings. Counting
      // the transfer would report far more spending than actually happened.
      final insights = insightsFor([
        tx(rupees: 60000, isExpense: false, date: DateTime(2026, 8, 2)),
        tx(rupees: 2000, isExpense: true, date: DateTime(2026, 8, 3)),
        ...transfer(rupees: 25000, from: 'cash', to: 'savings'),
      ]);

      expect(insights.thisMonth.expensePaisa, 2000 * 100);
      expect(insights.thisMonth.incomePaisa, 60000 * 100);
    });

    test('a budget is not consumed by a transfer', () {
      final budget = Budget(
        id: 'b',
        category: null,
        limitPaisa: 10000 * 100,
        createdAt: DateTime(2026, 8, 1),
      );

      final progress = BudgetCalculator.evaluate(
        budgets: [budget],
        transactions: [
          tx(rupees: 2000, isExpense: true, date: DateTime(2026, 8, 3)),
          ...transfer(rupees: 50000, from: 'cash', to: 'bank'),
        ],
        now: now,
      );

      // Without the exclusion this reads 52,000 against a 10,000 budget.
      expect(progress.single.spentPaisa, 2000 * 100);
      expect(progress.single.isOverspent, isFalse);
    });
  });

  test('an account survives the round trip through storage', () {
    final original = account('cash', opening: 12345);
    final restored = MoneyAccount.fromMap(original.id, original.toMap());

    expect(restored.name, original.name);
    expect(restored.kind, original.kind);
    expect(restored.openingBalancePaisa, 12345);
  });

  test('an unknown account kind falls back rather than throwing', () {
    expect(AccountKind.fromName('nonsense'), AccountKind.cash);
    expect(AccountKind.fromName(null), AccountKind.cash);
    expect(AccountKind.fromName('bank'), AccountKind.bank);
  });
}

import 'expense_model.dart';

enum AccountKind {
  cash('Cash', 'payments'),
  bank('Bank', 'bank'),
  wallet('Digital wallet', 'wallet'),
  card('Card', 'card');

  final String label;
  final String iconKey;
  const AccountKind(this.label, this.iconKey);

  static AccountKind fromName(String? name) {
    return AccountKind.values.firstWhere(
      (kind) => kind.name == name,
      orElse: () => AccountKind.cash,
    );
  }
}

/// A place money sits: cash in hand, a bank account, eSewa, a card.
///
/// Everything used to be one undifferentiated pool, so "how much cash do I
/// actually have on me" had no answer, and moving money between two of your
/// own accounts could not be recorded as anything other than spending it.
class MoneyAccount {
  final String id;
  final String name;
  final AccountKind kind;

  /// What the account held before the first recorded transaction.
  ///
  /// Without this, an account opened partway through has a balance that only
  /// reflects what the app happened to see.
  final int openingBalancePaisa;

  final DateTime createdAt;

  const MoneyAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.openingBalancePaisa,
    required this.createdAt,
  });

  MoneyAccount copyWith({String? name, AccountKind? kind, int? openingBalancePaisa}) {
    return MoneyAccount(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      openingBalancePaisa: openingBalancePaisa ?? this.openingBalancePaisa,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'kind': kind.name,
      'openingBalancePaisa': openingBalancePaisa,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static MoneyAccount fromMap(String id, Map<String, dynamic> data) {
    return MoneyAccount(
      id: id,
      name: data['name']?.toString() ?? 'Account',
      kind: AccountKind.fromName(data['kind']?.toString()),
      openingBalancePaisa:
          (data['openingBalancePaisa'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// An account with its current balance worked out.
class AccountBalance {
  final MoneyAccount account;

  /// Money in, including the incoming half of transfers.
  final int inPaisa;

  /// Money out, including the outgoing half of transfers.
  final int outPaisa;

  final int transactionCount;

  const AccountBalance({
    required this.account,
    required this.inPaisa,
    required this.outPaisa,
    required this.transactionCount,
  });

  int get balancePaisa => account.openingBalancePaisa + inPaisa - outPaisa;
}

class AccountCalculator {
  const AccountCalculator._();

  /// Works out where the money currently sits.
  ///
  /// Transfers deliberately *do* count here, unlike everywhere else. Moving
  /// Rs. 10,000 from cash to bank is not income or spending, but it very much
  /// changes what each account holds, so a per-account balance that ignored
  /// transfers would be wrong in exactly the case accounts exist for.
  static List<AccountBalance> balances({
    required List<MoneyAccount> accounts,
    required List<ExpenseModel> transactions,
  }) {
    final results = accounts.map((account) {
      final mine = transactions.where((t) => t.accountId == account.id);

      var moneyIn = 0;
      var moneyOut = 0;
      for (final transaction in mine) {
        if (transaction.isExpense) {
          moneyOut += transaction.amountPaisa;
        } else {
          moneyIn += transaction.amountPaisa;
        }
      }

      return AccountBalance(
        account: account,
        inPaisa: moneyIn,
        outPaisa: moneyOut,
        transactionCount: mine.length,
      );
    }).toList();

    results.sort((a, b) => b.balancePaisa.compareTo(a.balancePaisa));
    return results;
  }

  /// Transactions recorded before accounts existed, or since left unassigned.
  ///
  /// Surfaced rather than hidden: their money is real and belongs to some
  /// account, and silently dropping them would make the account totals
  /// disagree with the overall balance for no visible reason.
  static int unassignedCount(List<ExpenseModel> transactions) {
    return transactions.where((t) => t.accountId == null).length;
  }
}

import 'package:flutter/material.dart';

import '../../../core/components/transaction_tile.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/utils/money_utils.dart';
import '../../../services/user_data_service.dart';

class AllExpensesScreen extends StatelessWidget {
  const AllExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExpenseModel>>(
      stream: UserDataService.transactionsStream(),
      builder: (context, snapshot) {
        final transactions = _sortedTransactions(
          snapshot.data ?? const <ExpenseModel>[],
        );
        final expenses = transactions
            .where((transaction) => transaction.isExpense)
            .toList();
        final expenseCount = expenses.length;
        final totalExpensePaisa = expenses.fold(
          0,
          (total, transaction) => total + transaction.amountPaisa,
        );

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
              child: _Header(
                count: expenseCount,
                total: MoneyUtils.formatPaisa(totalExpensePaisa),
              ),
            ),
            if (expenses.isNotEmpty)
              SliverToBoxAdapter(child: _SectionHeader(count: expenseCount)),
            if (expenses.isEmpty)
              SliverToBoxAdapter(child: const _EmptyExpensesState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 170),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final transaction = expenses[index];
                    const sign = '-';

                    return Dismissible(
                      key: ValueKey(transaction.id),
                      direction: DismissDirection.endToStart,
                      background: const _DeleteBackground(),
                      confirmDismiss: (_) =>
                          _confirmDelete(context, transaction),
                      child: TransactionTile(
                        title: transaction.title,
                        category: _dateLabel(
                          transaction.date,
                          transaction.category,
                        ),
                        amount:
                            '$sign ${MoneyUtils.formatAmount(transaction.amount)}',
                        isExpense: transaction.isExpense,
                        icon: _iconForCategory(transaction.category),
                        onTap: () => _confirmDelete(context, transaction),
                      ),
                    );
                  }, childCount: expenses.length),
                ),
              ),
          ],
        ),
        );
      },
    );
  }

  List<ExpenseModel> _sortedTransactions(List<ExpenseModel> transactions) {
    final sorted = List<ExpenseModel>.from(transactions);
    sorted.sort((first, second) => second.date.compareTo(first.date));
    return sorted;
  }

  static String _dateLabel(DateTime date, String category) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$category - $day/$month/${date.year}';
  }

  static IconData _iconForCategory(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant_rounded;
      case 'Travel':
        return Icons.flight_takeoff_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      case 'Bills':
        return Icons.receipt_long_rounded;
      case 'Restaurant':
        return Icons.restaurant_menu_rounded;
      case 'Other':
        return Icons.category_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  static Future<bool> _confirmDelete(
    BuildContext context,
    ExpenseModel transaction,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete transaction?'),
          content: Text('Remove "${transaction.title}" permanently?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return false;
    }

    await UserDataService.deleteTransaction(transaction.id);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transaction deleted')));
    }

    return true;
  }
}

class _Header extends StatelessWidget {
  final int count;
  final String total;

  const _Header({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Expenses',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: colorScheme.primary,
                  size: 21,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.onPrimary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.trending_down_rounded,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total spent',
                        style: TextStyle(
                          color: colorScheme.onPrimary.withValues(alpha: 0.78),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        total,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final int count;

  const _SectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Recent expenses',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '$count item${count == 1 ? '' : 's'}',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExpensesState extends StatelessWidget {
  const _EmptyExpensesState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 170),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.32)),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.receipt_long_rounded, color: colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            'No expenses yet',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'New expense records will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      child: Icon(
        Icons.delete_rounded,
        color: Theme.of(context).colorScheme.onError,
      ),
    );
  }
}

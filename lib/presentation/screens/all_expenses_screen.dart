import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/components/transaction_tile.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/utils/money_utils.dart';

class AllExpensesScreen extends StatelessWidget {
  const AllExpensesScreen({super.key});

  static const _accent = Color(0xFF2A9D8F);
  static const _ink = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context) {
    final box = Hive.isBoxOpen('transactions') ? Hive.box<ExpenseModel>('transactions') : null;

    if (box == null) {
      return const Center(child: Text('No transactions available'));
    }

    return StreamBuilder<BoxEvent>(
      stream: box.watch(),
      builder: (context, snapshot) {
        final transactions = _sortedTransactions(box);
        final totalExpensePaisa = transactions
            .where((transaction) => transaction.isExpense)
            .fold(
              0,
              (total, transaction) =>
                  total + MoneyUtils.amountToPaisa(transaction.amount),
            );

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
            SliverToBoxAdapter(
              child: _TotalCard(
                count: transactions.length,
                total: MoneyUtils.formatPaisa(totalExpensePaisa),
              ),
            ),
            if (transactions.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 40, 16, 170),
                  child: Center(
                    child: Text(
                      'No transactions yet',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 170),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final transaction = transactions[index];
                    final sign = transaction.isExpense ? '-' : '+';

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
                  }, childCount: transactions.length),
                ),
              ),
          ],
        );
      },
    );
  }

  List<ExpenseModel> _sortedTransactions(Box<ExpenseModel>? box) {
    if (box == null) {
      return [];
    }

    final transactions = box.values.toList();
    transactions.sort((first, second) => second.date.compareTo(first.date));
    return transactions;
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
      default:
        return Icons.receipt_long_rounded;
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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return false;
    }

    await transaction.delete();
    if (Hive.isBoxOpen('transactions')) {
      await Hive.box<ExpenseModel>('transactions').flush();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transaction deleted')));
    }

    return true;
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'All Expenses',
              style: TextStyle(
                color: AllExpensesScreen._ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AllExpensesScreen._accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AllExpensesScreen._accent,
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFE63946),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerRight,
      child: const Icon(Icons.delete_rounded, color: Colors.white),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final int count;
  final String total;

  const _TotalCard({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEEB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_down_rounded, color: Color(0xFFE63946)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total,
                  style: const TextStyle(
                    color: AllExpensesScreen._ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count transaction${count == 1 ? '' : 's'} recorded',
                  style: const TextStyle(
                    color: Color(0xFF6B7470),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

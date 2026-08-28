import 'package:flutter/material.dart';

import '../../../core/components/app_widgets.dart';
import '../../../core/components/transaction_tile.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_utils.dart';
import '../../../services/user_data_service.dart';
import '../widgets/add_transaction_sheet.dart';

class AllExpensesScreen extends StatelessWidget {
  const AllExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExpenseModel>>(
      stream: UserDataService.transactionsStream(),
      builder: (context, snapshot) {
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final transactions = _sortedTransactions(
          snapshot.data ?? const <ExpenseModel>[],
        );
        final expenses = transactions
            .where((transaction) => transaction.isExpense)
            .toList();
        final totalExpensePaisa = expenses.fold(
          0,
          (total, transaction) => total + transaction.amountPaisa,
        );
        final bottomInset =
            MediaQuery.paddingOf(context).bottom + AppTokens.gapXl;

        return Scaffold(
          appBar: AppBar(),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  count: expenses.length,
                  total: MoneyUtils.formatPaisa(totalExpensePaisa),
                ),
              ),
              if (isLoading)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.pageGutter,
                    0,
                    AppTokens.pageGutter,
                    bottomInset,
                  ),
                  sliver: const SliverToBoxAdapter(
                    child: TransactionListSkeleton(),
                  ),
                )
              else if (expenses.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  sliver: const SliverToBoxAdapter(
                    child: EmptyStateCard(
                      icon: Icons.receipt_long_rounded,
                      title: 'No expenses yet',
                      message: 'New expense records will appear here.',
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Recent expenses',
                    trailing: Text(
                      '${expenses.length} item${expenses.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.pageGutter,
                    0,
                    AppTokens.pageGutter,
                    bottomInset,
                  ),
                  sliver: SliverList.builder(
                    itemCount: expenses.length,
                    itemBuilder: (context, index) {
                      final transaction = expenses[index];

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
                              '- ${MoneyUtils.formatAmount(transaction.amount)}',
                          isExpense: transaction.isExpense,
                          icon: _iconForCategory(transaction.category),
                          // Tapping used to open the delete confirmation,
                          // which made a stray tap the start of destroying a
                          // record. Editing is the safe default; deleting
                          // stays on the deliberate swipe.
                          onTap: () => showTransactionSheet(
                            context,
                            existing: transaction,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
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
    return '$category • $day/$month/${date.year}';
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
    final colorScheme = Theme.of(context).colorScheme;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete transaction?'),
          content: Text('"${transaction.title}" will be removed permanently.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Transaction deleted')));
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          title: 'Expenses',
          subtitle: 'Everything you have spent',
          icon: Icons.receipt_long_rounded,
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(
            AppTokens.pageGutter,
            AppTokens.gapSm,
            AppTokens.pageGutter,
            0,
          ),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colorScheme.appHeroGradient,
            ),
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.appOnHero.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(
                  Icons.trending_down_rounded,
                  color: colorScheme.appOnHero,
                ),
              ),
              const SizedBox(width: AppTokens.gapLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total spent',
                      style: TextStyle(
                        color: colorScheme.appOnHero.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppTokens.gapXs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        total,
                        maxLines: 1,
                        style: TextStyle(
                          color: colorScheme.appOnHero,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.gapSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.gapMd,
                  vertical: AppTokens.gapXs + 2,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.appOnHero.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: colorScheme.appOnHero,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.gapSm),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      alignment: Alignment.centerRight,
      child: Icon(Icons.delete_rounded, color: colorScheme.onErrorContainer),
    );
  }
}

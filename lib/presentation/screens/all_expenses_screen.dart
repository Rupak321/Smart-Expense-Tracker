import 'package:flutter/material.dart';

import '../../../core/categories/category_icons.dart';
import '../../../core/components/app_widgets.dart';
import '../../../core/components/transaction_tile.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_utils.dart';
import '../../../services/user_data_service.dart';
import '../widgets/add_transaction_sheet.dart';
import '../widgets/transaction_filter_sheet.dart';

/// The full transaction history, searchable and filterable.
///
/// This screen used to show expenses only, sorted by date, with no way to
/// narrow anything down. That is workable at fifty records and useless at
/// five hundred, and it also meant income was invisible here even though it
/// is half the ledger.
class AllExpensesScreen extends StatefulWidget {
  const AllExpensesScreen({super.key});

  @override
  State<AllExpensesScreen> createState() => _AllExpensesScreenState();
}

class _AllExpensesScreenState extends State<AllExpensesScreen> {
  final _searchController = TextEditingController();
  TransactionFilter _filter = const TransactionFilter();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next != _query) {
        setState(() => _query = next);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters(List<ExpenseModel> all) async {
    final categories =
        all.map((transaction) => transaction.category).toSet().toList()..sort();

    final result = await showTransactionFilterSheet(
      context,
      current: _filter,
      availableCategories: categories,
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExpenseModel>>(
      stream: UserDataService.transactionsStream(),
      builder: (context, snapshot) {
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final all = snapshot.data ?? const <ExpenseModel>[];
        final results = _filter.apply(all, query: _query);

        final totalPaisa = results.fold(
          0,
          (total, transaction) => transaction.isExpense
              ? total - transaction.amountPaisa
              : total + transaction.amountPaisa,
        );
        final bottomInset =
            MediaQuery.paddingOf(context).bottom + AppTokens.gapXl;
        final isNarrowed = _filter.isActive || _query.isNotEmpty;

        return Scaffold(
          appBar: AppBar(title: const Text('Transactions')),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.pageGutter,
                    0,
                    AppTokens.pageGutter,
                    AppTokens.gapMd,
                  ),
                  child: Column(
                    children: [
                      _SearchBar(
                        controller: _searchController,
                        activeFilters: _filter.activeCount,
                        onFilterTap: () => _openFilters(all),
                      ),
                      if (isNarrowed) ...[
                        const SizedBox(height: AppTokens.gapMd),
                        _ResultSummary(
                          count: results.length,
                          net: totalPaisa,
                          onClear: () {
                            _searchController.clear();
                            setState(() => _filter = const TransactionFilter());
                          },
                        ),
                      ],
                    ],
                  ),
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
              else if (results.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  sliver: SliverToBoxAdapter(
                    child: EmptyStateCard(
                      icon: isNarrowed
                          ? Icons.search_off_rounded
                          : Icons.receipt_long_rounded,
                      title: isNarrowed
                          ? 'Nothing matches'
                          : 'No transactions yet',
                      message: isNarrowed
                          ? 'Try a different search, or clear the filters.'
                          : 'Records you add will appear here.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.pageGutter,
                    0,
                    AppTokens.pageGutter,
                    bottomInset,
                  ),
                  sliver: SliverList.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final transaction = results[index];
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
                          icon: CategoryIcons.resolve(
                            CategoryIcons.suggestFor(transaction.category),
                          ),
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
          ),
        );
      },
    );
  }

  static String _dateLabel(DateTime date, String category) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$category • $day/$month/${date.year}';
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

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final int activeFilters;
  final VoidCallback onFilterTap;

  const _SearchBar({
    required this.controller,
    required this.activeFilters,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search title or category',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: controller.clear,
                  );
                },
              ),
              isDense: true,
              filled: true,
              fillColor: colorScheme.appCardMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.gapSm),
        Badge(
          isLabelVisible: activeFilters > 0,
          label: Text('$activeFilters'),
          child: IconButton.filledTonal(
            tooltip: 'Filters',
            onPressed: onFilterTap,
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    );
  }
}

class _ResultSummary extends StatelessWidget {
  final int count;
  final int net;
  final VoidCallback onClear;

  const _ResultSummary({
    required this.count,
    required this.net,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.gapLg,
        vertical: AppTokens.gapMd,
      ),
      decoration: BoxDecoration(
        color: colorScheme.appCardMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count ${count == 1 ? 'result' : 'results'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Net ${MoneyUtils.formatPaisa(net)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: net < 0 ? colorScheme.appExpense : colorScheme.appIncome,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.gapMd),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapXl),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
    );
  }
}

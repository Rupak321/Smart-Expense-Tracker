import 'package:flutter/material.dart';

import '../../core/models/expense_model.dart';
import '../../core/theme/app_theme.dart';

/// Which side of the ledger to show.
enum DirectionFilter {
  all('All'),
  expense('Expenses'),
  income('Income');

  final String label;
  const DirectionFilter(this.label);

  bool allows(ExpenseModel transaction) {
    return switch (this) {
      DirectionFilter.all => true,
      DirectionFilter.expense => transaction.isExpense,
      DirectionFilter.income => !transaction.isExpense,
    };
  }
}

/// The period a search runs over.
enum PeriodFilter {
  anyTime('Any time'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last30Days('Last 30 days'),
  last90Days('Last 90 days'),
  thisYear('This year');

  final String label;
  const PeriodFilter(this.label);

  /// Inclusive lower bound, or null when the period is unbounded.
  DateTime? startFrom(DateTime now) {
    return switch (this) {
      PeriodFilter.anyTime => null,
      PeriodFilter.thisMonth => DateTime(now.year, now.month),
      PeriodFilter.lastMonth => DateTime(now.year, now.month - 1),
      PeriodFilter.last30Days => _daysBefore(now, 30),
      PeriodFilter.last90Days => _daysBefore(now, 90),
      PeriodFilter.thisYear => DateTime(now.year),
    };
  }

  /// Exclusive upper bound, or null when the period runs to now.
  DateTime? endBefore(DateTime now) {
    return this == PeriodFilter.lastMonth
        ? DateTime(now.year, now.month)
        : null;
  }

  static DateTime _daysBefore(DateTime now, int days) {
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: days - 1));
  }

  bool contains(DateTime date, DateTime now) {
    final start = startFrom(now);
    final end = endBefore(now);
    if (start != null && date.isBefore(start)) return false;
    if (end != null && !date.isBefore(end)) return false;
    return true;
  }
}

/// How results are ordered.
enum TransactionSort {
  newest('Newest first'),
  oldest('Oldest first'),
  largest('Largest amount'),
  smallest('Smallest amount');

  final String label;
  const TransactionSort(this.label);

  int compare(ExpenseModel a, ExpenseModel b) {
    return switch (this) {
      TransactionSort.newest => b.date.compareTo(a.date),
      TransactionSort.oldest => a.date.compareTo(b.date),
      TransactionSort.largest => b.amountPaisa.compareTo(a.amountPaisa),
      TransactionSort.smallest => a.amountPaisa.compareTo(b.amountPaisa),
    };
  }
}

/// A complete description of what the transaction list is showing.
///
/// Immutable and pure, so the whole narrowing behaviour is testable without
/// building a widget or touching Firestore.
class TransactionFilter {
  final DirectionFilter direction;
  final PeriodFilter period;
  final TransactionSort sort;

  /// Empty means every category. Names rather than ids, matching how
  /// transactions store their category.
  final Set<String> categories;

  const TransactionFilter({
    this.direction = DirectionFilter.all,
    this.period = PeriodFilter.anyTime,
    this.sort = TransactionSort.newest,
    this.categories = const {},
  });

  /// How many non-default choices are in play, for the badge on the button.
  ///
  /// Sort is excluded deliberately: reordering does not hide anything, so
  /// counting it would suggest results are missing when they are not.
  int get activeCount {
    var count = 0;
    if (direction != DirectionFilter.all) count++;
    if (period != PeriodFilter.anyTime) count++;
    if (categories.isNotEmpty) count++;
    return count;
  }

  bool get isActive => activeCount > 0;

  TransactionFilter copyWith({
    DirectionFilter? direction,
    PeriodFilter? period,
    TransactionSort? sort,
    Set<String>? categories,
  }) {
    return TransactionFilter(
      direction: direction ?? this.direction,
      period: period ?? this.period,
      sort: sort ?? this.sort,
      categories: categories ?? this.categories,
    );
  }

  /// Narrows and orders [transactions].
  ///
  /// [query] matches the title or the category, case-insensitively, so
  /// searching "food" finds both a title mentioning food and everything filed
  /// under a food category.
  List<ExpenseModel> apply(
    List<ExpenseModel> transactions, {
    String query = '',
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final needle = query.trim().toLowerCase();

    final results = transactions.where((transaction) {
      if (!direction.allows(transaction)) return false;
      if (!period.contains(transaction.date, today)) return false;
      if (categories.isNotEmpty && !categories.contains(transaction.category)) {
        return false;
      }
      if (needle.isEmpty) return true;

      return transaction.title.toLowerCase().contains(needle) ||
          transaction.category.toLowerCase().contains(needle);
    }).toList();

    results.sort(sort.compare);
    return results;
  }
}

/// Opens the filter sheet. Resolves to null when dismissed unchanged.
Future<TransactionFilter?> showTransactionFilterSheet(
  BuildContext context, {
  required TransactionFilter current,
  required List<String> availableCategories,
}) {
  return showModalBottomSheet<TransactionFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => TransactionFilterSheet(
      current: current,
      availableCategories: availableCategories,
    ),
  );
}

class TransactionFilterSheet extends StatefulWidget {
  final TransactionFilter current;
  final List<String> availableCategories;

  const TransactionFilterSheet({
    super.key,
    required this.current,
    required this.availableCategories,
  });

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late TransactionFilter _draft = widget.current;

  void _toggleCategory(String name) {
    final next = Set<String>.from(_draft.categories);
    if (!next.add(name)) next.remove(name);
    setState(() => _draft = _draft.copyWith(categories: next));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gapXl,
          AppTokens.gapLg,
          AppTokens.gapXl,
          AppTokens.gapXl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _draft.isActive
                        ? () => setState(
                            () => _draft = TransactionFilter(sort: _draft.sort),
                          )
                        : null,
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gapMd),

              _FilterGroup(
                label: 'Show',
                child: Wrap(
                  spacing: AppTokens.gapSm,
                  children: [
                    for (final option in DirectionFilter.values)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: _draft.direction == option,
                        showCheckmark: false,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(direction: option),
                        ),
                      ),
                  ],
                ),
              ),

              _FilterGroup(
                label: 'Period',
                child: Wrap(
                  spacing: AppTokens.gapSm,
                  runSpacing: AppTokens.gapSm,
                  children: [
                    for (final option in PeriodFilter.values)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: _draft.period == option,
                        showCheckmark: false,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(period: option),
                        ),
                      ),
                  ],
                ),
              ),

              _FilterGroup(
                label: 'Sort by',
                child: Wrap(
                  spacing: AppTokens.gapSm,
                  runSpacing: AppTokens.gapSm,
                  children: [
                    for (final option in TransactionSort.values)
                      ChoiceChip(
                        label: Text(option.label),
                        selected: _draft.sort == option,
                        showCheckmark: false,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(sort: option),
                        ),
                      ),
                  ],
                ),
              ),

              if (widget.availableCategories.isNotEmpty)
                _FilterGroup(
                  label: _draft.categories.isEmpty
                      ? 'Categories — all'
                      : 'Categories — ${_draft.categories.length} selected',
                  child: Wrap(
                    spacing: AppTokens.gapSm,
                    runSpacing: AppTokens.gapSm,
                    children: [
                      for (final name in widget.availableCategories)
                        FilterChip(
                          label: Text(name),
                          selected: _draft.categories.contains(name),
                          showCheckmark: true,
                          onSelected: (_) => _toggleCategory(name),
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: AppTokens.gapXl),
              FilledButton(
                onPressed: () => Navigator.pop(context, _draft),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Apply',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  final String label;
  final Widget child;

  const _FilterGroup({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.gapSm),
          child,
        ],
      ),
    );
  }
}

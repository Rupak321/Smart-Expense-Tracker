import 'package:flutter/material.dart';

import '../../core/components/app_widgets.dart';
import '../../core/models/budget.dart';
import '../../core/models/expense_category.dart';
import '../../core/models/expense_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../services/budget_service.dart';
import '../../services/category_service.dart';
import '../../services/user_data_service.dart';

/// Monthly spending ceilings and how the current month is tracking against
/// them.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<ExpenseCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await CategoryService.ensureSeeded();
    if (mounted) setState(() => _categories = categories);
  }

  Future<void> _edit({Budget? existing, List<Budget> all = const []}) async {
    final taken = all
        .where((budget) => budget.id != existing?.id)
        .map((budget) => budget.category)
        .toSet();

    final result = await showModalBottomSheet<_BudgetDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _BudgetSheet(
        existing: existing,
        categories: _categories
            .where((category) => category.kind.allows(isExpense: true))
            .map((category) => category.name)
            .where((name) => !taken.contains(name))
            .toList(),
        overallTaken: taken.contains(null),
      ),
    );

    if (result == null) return;
    await BudgetService.save(
      category: result.category,
      limitPaisa: result.limitPaisa,
    );
  }

  Future<void> _confirmDelete(Budget budget) async {
    final colorScheme = Theme.of(context).colorScheme;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove budget?'),
        content: Text(
          'The ceiling on ${budget.label} will be removed. '
          'Your transactions are not affected.',
        ),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await BudgetService.delete(budget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Budget>>(
      stream: BudgetService.stream(),
      builder: (context, budgetSnapshot) {
        final budgets = budgetSnapshot.data ?? const <Budget>[];

        return StreamBuilder<List<ExpenseModel>>(
          stream: UserDataService.transactionsStream(),
          builder: (context, transactionSnapshot) {
            final transactions =
                transactionSnapshot.data ?? const <ExpenseModel>[];
            final progress = BudgetCalculator.evaluate(
              budgets: budgets,
              transactions: transactions,
              now: DateTime.now(),
            );

            return Scaffold(
              appBar: AppBar(title: const Text('Budgets')),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _edit(all: budgets),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New budget'),
              ),
              body: budgets.isEmpty
                  ? const SingleChildScrollView(
                      child: EmptyStateCard(
                        icon: Icons.savings_rounded,
                        title: 'No budgets yet',
                        message:
                            'Set a monthly ceiling on a category, or on your '
                            'spending as a whole, and this page will track it.',
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        AppTokens.pageGutter,
                        AppTokens.gapLg,
                        AppTokens.pageGutter,
                        MediaQuery.paddingOf(context).bottom + 96,
                      ),
                      itemCount: progress.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppTokens.gapMd),
                      itemBuilder: (context, index) {
                        final item = progress[index];
                        return BudgetCard(
                          progress: item,
                          onEdit: () =>
                              _edit(existing: item.budget, all: budgets),
                          onDelete: () => _confirmDelete(item.budget),
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }
}

/// One budget, its bar, and the sentence that explains where it stands.
class BudgetCard extends StatelessWidget {
  final BudgetProgress progress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const BudgetCard({
    super.key,
    required this.progress,
    this.onEdit,
    this.onDelete,
  });

  static Color colorFor(BudgetHealth health, ColorScheme scheme) {
    return switch (health) {
      BudgetHealth.comfortable => scheme.appIncome,
      BudgetHealth.tight => scheme.appWarning,
      BudgetHealth.atRisk => scheme.appWarning,
      BudgetHealth.over => scheme.appExpense,
    };
  }

  /// Plain language about where this budget stands, written to be useful
  /// rather than merely restating the bar.
  static String messageFor(BudgetProgress progress) {
    final remaining = MoneyUtils.formatPaisa(progress.remainingPaisa.abs());

    if (progress.isOverspent) {
      return 'Over by $remaining';
    }
    if (progress.isOnTrackToOverspend) {
      final projected = MoneyUtils.formatPaisa(progress.projectedPaisa);
      return 'On track for $projected by month end';
    }
    final daily = MoneyUtils.formatPaisa(progress.safeDailyPaisa);
    if (progress.safeDailyPaisa > 0) {
      return '$remaining left — about $daily a day';
    }
    return '$remaining left';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorFor(progress.health, colorScheme);

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapLg),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: colorScheme.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.budget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  tooltip: 'Budget options',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppTokens.gapSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                MoneyUtils.formatPaisa(progress.spentPaisa),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'of ${MoneyUtils.formatPaisa(progress.limitPaisa)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.gapMd),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: LinearProgressIndicator(
              value: progress.barValue,
              minHeight: 8,
              backgroundColor: colorScheme.appCardMuted,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: AppTokens.gapSm),
          Text(
            messageFor(progress),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: progress.health == BudgetHealth.comfortable
                  ? colorScheme.onSurfaceVariant
                  : accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetDraft {
  final String? category;
  final int limitPaisa;

  const _BudgetDraft({required this.category, required this.limitPaisa});
}

class _BudgetSheet extends StatefulWidget {
  final Budget? existing;
  final List<String> categories;
  final bool overallTaken;

  const _BudgetSheet({
    required this.existing,
    required this.categories,
    required this.overallTaken,
  });

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String? _category;
  late bool _isOverall;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amountController.text = MoneyUtils.editableAmount(
        MoneyUtils.paisaToAmount(existing.limitPaisa),
      );
      _category = existing.category;
      _isOverall = existing.isOverall;
    } else {
      _isOverall = widget.overallTaken ? false : widget.categories.isEmpty;
      _category = widget.categories.firstOrNull;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (!_isOverall && _category == null) return;

    Navigator.pop(
      context,
      _BudgetDraft(
        category: _isOverall ? null : _category,
        limitPaisa: MoneyUtils.parseToPaisa(_amountController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canChooseOverall = !widget.overallTaken || _isOverall;

    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.gapXl,
        right: AppTokens.gapXl,
        top: AppTokens.gapLg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.gapXl,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'New budget' : 'Edit budget',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppTokens.gapLg),

              if (canChooseOverall)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isOverall,
                  onChanged: (value) => setState(() => _isOverall = value),
                  title: const Text('Cap total spending'),
                  subtitle: const Text('Rather than one category'),
                ),

              if (!_isOverall) ...[
                const SizedBox(height: AppTokens.gapSm),
                if (widget.categories.isEmpty)
                  Text(
                    'Every category already has a budget.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: [
                      for (final name in widget.categories)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: (value) => setState(() => _category = value),
                  ),
              ],

              const SizedBox(height: AppTokens.gapLg),
              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Monthly limit',
                  hintText: 'Rs. 0.00',
                  prefixIcon: const Icon(Icons.currency_rupee_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: MoneyUtils.validateAmount,
              ),

              const SizedBox(height: AppTokens.gapXl),
              FilledButton(
                onPressed: (!_isOverall && widget.categories.isEmpty)
                    ? null
                    : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Save budget',
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

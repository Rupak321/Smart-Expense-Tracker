import 'package:flutter/material.dart';

import '../../core/components/app_widgets.dart';
import '../../core/models/recurring_expense_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../services/user_data_service.dart';

class RecurringExpensesScreen extends StatelessWidget {
  const RecurringExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Expenses')),
      body: StreamBuilder<List<RecurringExpenseModel>>(
        stream: UserDataService.recurringExpensesStream(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <RecurringExpenseModel>[];
          final bottomInset =
              96 + MediaQuery.paddingOf(context).bottom;

          if (items.isEmpty) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppTokens.pageGutter,
                AppTokens.gapXl,
                AppTokens.pageGutter,
                bottomInset,
              ),
              child: EmptyStateCard(
                icon: Icons.repeat_rounded,
                title: 'No recurring expenses',
                message:
                    'Add rent, subscriptions, bills, or other repeating '
                    'expenses and they will be recorded automatically.',
                actionLabel: 'Add first one',
                onAction: () => _showAddEditRecurringExpense(context),
                margin: EdgeInsets.zero,
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppTokens.pageGutter,
              AppTokens.gapMd,
              AppTokens.pageGutter,
              bottomInset,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppTokens.gapSm),
            itemBuilder: (context, index) {
              final item = items[index];
              return _RecurringExpenseTile(expense: item);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditRecurringExpense(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
    );
  }
}

class UpcomingRecurringSection extends StatelessWidget {
  const UpcomingRecurringSection({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RecurringExpenseModel>>(
      stream: UserDataService.recurringExpensesStream(),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <RecurringExpenseModel>[])
            .where((item) => item.status == RecurringStatus.active)
            .toList()
          ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
        final upcoming = items.take(5).toList();
        if (upcoming.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Upcoming Recurring',
              trailing: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RecurringExpensesScreen(),
                  ),
                ),
                child: const Text('View all'),
              ),
            ),
            SizedBox(
              height: 124,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.pageGutter,
                ),
                itemCount: upcoming.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppTokens.gapSm),
                itemBuilder: (context, index) {
                  final item = upcoming[index];
                  return SizedBox(
                    width: 190,
                    child: _UpcomingRecurringCard(expense: item),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecurringExpenseTile extends StatelessWidget {
  final RecurringExpenseModel expense;

  const _RecurringExpenseTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final paused = expense.status == RecurringStatus.paused;
    return Material(
      color: colorScheme.appCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(
            _iconForCategory(expense.category),
            color: colorScheme.primary,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                expense.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (paused) ...[
              const SizedBox(width: AppTokens.gapSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.appCardMuted,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  'Paused',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${_frequencyLabel(expense)} • ${_dueLabel(expense.nextDueDate)} • '
          '${MoneyUtils.formatAmount(expense.amount)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              _showAddEditRecurringExpense(context, expense: expense);
            } else if (value == 'toggle') {
              await UserDataService.updateRecurringStatus(
                expense.id,
                paused ? RecurringStatus.active : RecurringStatus.paused,
              );
            } else if (value == 'delete') {
              await UserDataService.deleteRecurringExpense(expense.id);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(paused ? 'Resume' : 'Pause'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _UpcomingRecurringCard extends StatelessWidget {
  final RecurringExpenseModel expense;

  const _UpcomingRecurringCard({required this.expense});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RecurringExpensesScreen()),
      ),
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.gapMd),
        decoration: BoxDecoration(
          color: colorScheme.appCard,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: colorScheme.appBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _iconForCategory(expense.category),
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: AppTokens.gapSm),
                Expanded(
                  child: Text(
                    expense.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  MoneyUtils.formatAmount(expense.amount),
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.gapXs + 2),
            _DueBadge(date: expense.nextDueDate),
          ],
        ),
      ),
    );
  }
}

class _DueBadge extends StatelessWidget {
  final DateTime date;

  const _DueBadge({required this.date});

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.dateOnly(date)
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    final colorScheme = Theme.of(context).colorScheme;
    final color = days <= 0
        ? colorScheme.appExpense
        : days <= 2
        ? colorScheme.appWarning
        : colorScheme.onSurfaceVariant;
    return Text(
      _dueLabel(date),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    );
  }
}

Future<void> _showAddEditRecurringExpense(
  BuildContext context, {
  RecurringExpenseModel? expense,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecurringExpenseForm(expense: expense),
  );
}

class _RecurringExpenseForm extends StatefulWidget {
  final RecurringExpenseModel? expense;

  const _RecurringExpenseForm({this.expense});

  @override
  State<_RecurringExpenseForm> createState() => _RecurringExpenseFormState();
}

class _RecurringExpenseFormState extends State<_RecurringExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late RecurringFrequency _frequency;
  late String _category;
  late DateTime _startDate;
  DateTime? _endDate;
  var _interval = 1;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _titleController = TextEditingController(text: expense?.title ?? '');
    _amountController = TextEditingController(
      text: expense == null ? '' : expense.amount.toStringAsFixed(0),
    );
    _frequency = expense?.frequency ?? RecurringFrequency.monthly;
    _category = expense?.category ?? 'Bills';
    _startDate = expense?.startDate ?? DateTime.now();
    _endDate = expense?.endDate;
    _interval = expense?.interval ?? 1;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.expense == null ? 'Add Recurring Expense' : 'Edit Recurring Expense',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in const ['Rent', 'Utilities', 'Internet', 'Gym', 'Subscription', 'Insurance'])
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() {
                        _category = category;
                        if (_titleController.text.trim().isEmpty) {
                          _titleController.text = category;
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  return parsed == null || parsed <= 0 ? 'Enter a valid amount' : null;
                },
              ),
              const SizedBox(height: AppTokens.gapLg),
              // Four segments do not fit a narrow phone at larger text scales,
              // so the control scrolls horizontally instead of overflowing.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<RecurringFrequency>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: RecurringFrequency.daily,
                      label: Text('Daily'),
                    ),
                    ButtonSegment(
                      value: RecurringFrequency.weekly,
                      label: Text('Weekly'),
                    ),
                    ButtonSegment(
                      value: RecurringFrequency.monthly,
                      label: Text('Monthly'),
                    ),
                    ButtonSegment(
                      value: RecurringFrequency.yearly,
                      label: Text('Yearly'),
                    ),
                  ],
                  selected: {_frequency},
                  onSelectionChanged: (value) =>
                      setState(() => _frequency = value.first),
                ),
              ),
              const SizedBox(height: AppTokens.gapMd),
              Row(
                children: [
                  const Text('Repeat every'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Decrease interval',
                    onPressed: _interval > 1
                        ? () => setState(() => _interval--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$_interval',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Increase interval',
                    onPressed: () => setState(() => _interval++),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  // Flexible so a long unit name shortens instead of pushing
                  // the stepper off the row.
                  Flexible(
                    child: Text(
                      _intervalUnitLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gapSm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Starts ${_shortDate(_startDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: _startDate,
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End date'),
                value: _endDate != null,
                onChanged: (enabled) async {
                  if (!enabled) {
                    setState(() => _endDate = null);
                    return;
                  }
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: _startDate,
                    lastDate: DateTime(2100),
                    initialDate: _endDate ?? _startDate,
                  );
                  if (picked != null) setState(() => _endDate = picked);
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary),
                child: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "day" / "days" etc, matching the chosen frequency and interval.
  String _intervalUnitLabel() {
    final unit = switch (_frequency) {
      RecurringFrequency.daily => 'day',
      RecurringFrequency.weekly => 'week',
      RecurringFrequency.monthly => 'month',
      RecurringFrequency.yearly => 'year',
    };
    return _interval == 1 ? unit : '${unit}s';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final current = widget.expense;
    final model = RecurringExpenseModel(
      id: current?.id ?? '',
      userId: UserDataService.currentUid ?? '',
      title: _titleController.text.trim(),
      category: _category,
      amount: double.parse(_amountController.text.trim()),
      currency: current?.currency ?? 'NPR',
      frequency: _frequency,
      interval: _interval,
      startDate: _startDate,
      endDate: _endDate,
      nextDueDate: current?.nextDueDate ?? _startDate,
      lastGeneratedDate: current?.lastGeneratedDate,
      status: current?.status ?? RecurringStatus.active,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      await UserDataService.saveRecurringExpense(model);
      await UserDataService.runRecurringCatchUp();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _frequencyLabel(RecurringExpenseModel expense) {
  final unit = expense.frequency.name;
  return expense.interval == 1 ? unit : 'Every ${expense.interval} $unit';
}

String _dueLabel(DateTime date) {
  final days = DateUtils.dateOnly(date)
      .difference(DateUtils.dateOnly(DateTime.now()))
      .inDays;
  if (days < 0) return 'Overdue';
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in $days days';
}

String _shortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

IconData _iconForCategory(String category) {
  final lower = category.toLowerCase();
  if (lower.contains('rent')) return Icons.home_outlined;
  if (lower.contains('util')) return Icons.bolt_outlined;
  if (lower.contains('internet')) return Icons.wifi_rounded;
  if (lower.contains('gym')) return Icons.fitness_center_rounded;
  if (lower.contains('subscription')) return Icons.subscriptions_rounded;
  if (lower.contains('insurance')) return Icons.shield_outlined;
  return Icons.receipt_long_rounded;
}

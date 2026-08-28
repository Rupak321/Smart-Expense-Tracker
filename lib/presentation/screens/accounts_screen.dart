import 'package:flutter/material.dart';

import '../../core/components/app_widgets.dart';
import '../../core/models/expense_model.dart';
import '../../core/models/money_account.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../services/account_service.dart';
import '../../services/user_data_service.dart';
import '../widgets/transfer_sheet.dart';

/// Where the money sits: cash, bank, wallets, cards.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  static IconData iconFor(AccountKind kind) {
    return switch (kind) {
      AccountKind.cash => Icons.payments_rounded,
      AccountKind.bank => Icons.account_balance_rounded,
      AccountKind.wallet => Icons.account_balance_wallet_rounded,
      AccountKind.card => Icons.credit_card_rounded,
    };
  }

  Future<void> _edit(BuildContext context, {MoneyAccount? existing}) async {
    final result = await showModalBottomSheet<MoneyAccount>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AccountSheet(existing: existing),
    );
    if (result == null) return;

    if (existing == null) {
      await AccountService.create(
        name: result.name,
        kind: result.kind,
        openingBalancePaisa: result.openingBalancePaisa,
      );
    } else {
      await AccountService.save(result);
    }
  }

  Future<void> _confirmDelete(BuildContext context, AccountBalance item) async {
    final colorScheme = Theme.of(context).colorScheme;
    final count = item.transactionCount;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${item.account.name}?'),
        content: Text(
          count == 0
              ? 'Nothing is filed under this account.'
              : '$count ${count == 1 ? 'transaction stays' : 'transactions stay'} '
                    'in your history but will no longer be attributed to an '
                    'account. Nothing is deleted.',
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
      await AccountService.delete(item.account.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MoneyAccount>>(
      stream: AccountService.stream(),
      builder: (context, accountSnapshot) {
        final accounts = accountSnapshot.data ?? const <MoneyAccount>[];

        return StreamBuilder<List<ExpenseModel>>(
          stream: UserDataService.transactionsStream(),
          builder: (context, transactionSnapshot) {
            final transactions =
                transactionSnapshot.data ?? const <ExpenseModel>[];
            final balances = AccountCalculator.balances(
              accounts: accounts,
              transactions: transactions,
            );
            final unassigned = AccountCalculator.unassignedCount(transactions);
            final totalPaisa = balances.fold(
              0,
              (sum, item) => sum + item.balancePaisa,
            );

            return Scaffold(
              appBar: AppBar(
                title: const Text('Accounts'),
                actions: [
                  if (accounts.length >= 2)
                    IconButton(
                      tooltip: 'Transfer between accounts',
                      icon: const Icon(Icons.swap_horiz_rounded),
                      onPressed: () => showTransferSheet(context, accounts),
                    ),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New account'),
              ),
              body: accounts.isEmpty
                  ? const SingleChildScrollView(
                      child: EmptyStateCard(
                        icon: Icons.account_balance_wallet_rounded,
                        title: 'No accounts yet',
                        message:
                            'Add your cash, bank account or wallet to see '
                            'where your money actually sits, and to record '
                            'moves between them.',
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        AppTokens.pageGutter,
                        AppTokens.gapLg,
                        AppTokens.pageGutter,
                        MediaQuery.paddingOf(context).bottom + 96,
                      ),
                      children: [
                        _TotalCard(total: totalPaisa, count: accounts.length),
                        if (unassigned > 0) ...[
                          const SizedBox(height: AppTokens.gapMd),
                          _UnassignedNotice(count: unassigned),
                        ],
                        const SizedBox(height: AppTokens.gapLg),
                        for (final item in balances) ...[
                          _AccountCard(
                            balance: item,
                            icon: iconFor(item.account.kind),
                            onEdit: () =>
                                _edit(context, existing: item.account),
                            onDelete: () => _confirmDelete(context, item),
                          ),
                          const SizedBox(height: AppTokens.gapMd),
                        ],
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

class _TotalCard extends StatelessWidget {
  final int total;
  final int count;

  const _TotalCard({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colorScheme.appHeroGradient),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Across $count ${count == 1 ? 'account' : 'accounts'}',
            style: TextStyle(
              color: colorScheme.appOnHero.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              MoneyUtils.formatPaisa(total),
              style: TextStyle(
                color: colorScheme.appOnHero,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says plainly that some records are not attributed anywhere.
///
/// Hiding them would make the account totals disagree with the balance on the
/// home screen, with nothing on screen to explain the gap.
class _UnassignedNotice extends StatelessWidget {
  final int count;

  const _UnassignedNotice({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapMd),
      decoration: BoxDecoration(
        color: colorScheme.appWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colorScheme.appWarning,
          ),
          const SizedBox(width: AppTokens.gapSm),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'transaction is' : 'transactions are'} '
              'not assigned to an account, so they are not counted above.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AccountBalance balance;
  final IconData icon;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AccountCard({
    required this.balance,
    required this.icon,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNegative = balance.balancePaisa < 0;

    return Material(
      color: colorScheme.appCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        side: BorderSide(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.gapLg),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 21),
              ),
              const SizedBox(width: AppTokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      balance.account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${balance.account.kind.label} · '
                      '${balance.transactionCount} '
                      '${balance.transactionCount == 1 ? 'record' : 'records'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.gapSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    MoneyUtils.formatPaisa(balance.balancePaisa),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isNegative
                          ? colorScheme.appExpense
                          : colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: IconButton(
                      tooltip: 'Remove account',
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountSheet extends StatefulWidget {
  final MoneyAccount? existing;

  const _AccountSheet({required this.existing});

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _openingController = TextEditingController();
  AccountKind _kind = AccountKind.cash;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _kind = existing.kind;
      if (existing.openingBalancePaisa != 0) {
        _openingController.text = MoneyUtils.editableAmount(
          MoneyUtils.paisaToAmount(existing.openingBalancePaisa),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      MoneyAccount(
        id: widget.existing?.id ?? '',
        name: _nameController.text.trim(),
        kind: _kind,
        openingBalancePaisa: _openingController.text.trim().isEmpty
            ? 0
            : MoneyUtils.parseToPaisa(_openingController.text),
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                widget.existing == null ? 'New account' : 'Edit account',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppTokens.gapLg),
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Wallet, NIC Asia, eSewa',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Give the account a name'
                    : null,
              ),
              const SizedBox(height: AppTokens.gapLg),
              Wrap(
                spacing: AppTokens.gapSm,
                runSpacing: AppTokens.gapSm,
                children: [
                  for (final kind in AccountKind.values)
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: _kind == kind,
                      showCheckmark: false,
                      avatar: Icon(AccountsScreen.iconFor(kind), size: 16),
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.gapLg),
              TextFormField(
                controller: _openingController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Opening balance (optional)',
                  helperText: 'What it held before you started recording',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  return MoneyUtils.validateAmount(value);
                },
              ),
              const SizedBox(height: AppTokens.gapXl),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Save account',
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

import 'package:flutter/material.dart';

import '../../core/models/money_account.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../services/account_service.dart';

/// Records money moving between two of the user's own accounts.
Future<bool?> showTransferSheet(
  BuildContext context,
  List<MoneyAccount> accounts,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => TransferSheet(accounts: accounts),
  );
}

class TransferSheet extends StatefulWidget {
  final List<MoneyAccount> accounts;

  const TransferSheet({super.key, required this.accounts});

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late MoneyAccount _from = widget.accounts.first;
  late MoneyAccount _to = widget.accounts[1];
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Keeps the two sides different.
  ///
  /// A transfer from an account to itself would write two rows that cancel out
  /// and mean nothing, so picking one side pushes the other along.
  void _setFrom(MoneyAccount account) {
    setState(() {
      _from = account;
      if (_to.id == _from.id) {
        _to = widget.accounts.firstWhere((a) => a.id != _from.id);
      }
    });
  }

  void _setTo(MoneyAccount account) {
    setState(() {
      _to = account;
      if (_from.id == _to.id) {
        _from = widget.accounts.firstWhere((a) => a.id != _to.id);
      }
    });
  }

  void _swap() {
    setState(() {
      final previous = _from;
      _from = _to;
      _to = previous;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Transfer date',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await AccountService.transfer(
        from: _from,
        to: _to,
        amount: MoneyUtils.paisaToAmount(
          MoneyUtils.parseToPaisa(_amountController.text),
        ),
        date: _date,
        note: _noteController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                'Transfer',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Moving your own money between accounts. This is not counted '
                'as income or spending.',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTokens.gapLg),

              Row(
                children: [
                  Expanded(
                    child: _AccountDropdown(
                      label: 'From',
                      value: _from,
                      accounts: widget.accounts,
                      onChanged: _setFrom,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Swap',
                    onPressed: _swap,
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                  Expanded(
                    child: _AccountDropdown(
                      label: 'To',
                      value: _to,
                      accounts: widget.accounts,
                      onChanged: _setTo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gapLg),

              TextFormField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: const Icon(Icons.currency_rupee_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: MoneyUtils.validateAmount,
              ),
              const SizedBox(height: AppTokens.gapLg),

              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date',
                    prefixIcon: const Icon(Icons.event_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '${_date.day.toString().padLeft(2, '0')}/'
                    '${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.gapLg),

              TextFormField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. Cash withdrawal',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: AppTokens.gapXl),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  _saving ? 'Saving…' : 'Record transfer',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  final String label;
  final MoneyAccount value;
  final List<MoneyAccount> accounts;
  final ValueChanged<MoneyAccount> onChanged;

  const _AccountDropdown({
    required this.label,
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        for (final account in accounts)
          DropdownMenuItem(
            value: account.id,
            child: Text(account.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        onChanged(accounts.firstWhere((account) => account.id == id));
      },
    );
  }
}

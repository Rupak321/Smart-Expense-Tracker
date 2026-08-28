import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/categories/category_icons.dart';
import '../../core/models/expense_category.dart';
import '../../core/models/expense_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../core/utils/receipt_storage.dart';
import '../../core/models/money_account.dart';
import '../../services/account_service.dart';
import '../../services/category_service.dart';
import '../../services/user_data_service.dart';

/// Opens the record sheet, either empty or prefilled for an edit.
///
/// Resolves to true when something was saved, so callers can confirm.
Future<bool?> showTransactionSheet(
  BuildContext context, {
  ExpenseModel? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AddTransactionSheet(existing: existing),
  );
}

class AddTransactionSheet extends StatefulWidget {
  /// Supplies the category list instead of loading it.
  ///
  /// Only used by tests and previews; in the app it is null and the sheet
  /// reads the user's own vocabulary.
  final List<ExpenseCategory>? categoriesOverride;

  /// The transaction being edited, or null when recording a new one.
  ///
  /// When present the sheet keeps the same document id, so editing updates the
  /// record in place instead of leaving the old one behind.
  final ExpenseModel? existing;

  const AddTransactionSheet({
    super.key,
    this.categoriesOverride,
    this.existing,
  });

  bool get isEditing => existing != null;

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  String? _selectedCategory;
  bool _isExpense = true; // Toggle state: true = Expense, false = Income
  bool _isSaving = false;
  bool _isWindfall = false;
  DateTime _date = DateTime.now();

  List<MoneyAccount> _accounts = const [];
  String? _accountId;

  String? _receiptPath;

  /// A receipt attached during this edit but not yet saved. If the sheet is
  /// dismissed it is removed again, rather than left as an orphan file.
  String? _pendingReceiptPath;

  /// The user's own vocabulary, loaded once when the sheet opens.
  List<ExpenseCategory> _categories = const [];
  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _amountController.text = MoneyUtils.editableAmount(existing.amount);
      _selectedCategory = existing.category;
      _isExpense = existing.isExpense;
      _isWindfall = existing.isWindfall;
      _date = existing.date;
      _accountId = existing.accountId;
      _receiptPath = existing.receiptPath;
    }
    _loadCategories();
    _loadAccounts();
  }

  Future<void> _loadCategories() async {
    final override = widget.categoriesOverride;
    if (override != null) {
      setState(() {
        _categories = override;
        _loadingCategories = false;
        _selectedCategory ??= _visibleCategories().firstOrNull?.name;
      });
      return;
    }

    final categories = await CategoryService.ensureSeeded();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _loadingCategories = false;
      _selectedCategory ??= _visibleCategories().firstOrNull?.name;
    });
  }

  Future<void> _loadAccounts() async {
    final accounts = await AccountService.getOnce();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      // Only default for a new record. Leaving an edited transaction's blank
      // account alone avoids silently attributing an old row to an account
      // the user never chose for it.
      if (widget.existing == null && accounts.length == 1) {
        _accountId ??= accounts.first.id;
      }
    });
  }

  /// Categories usable for the current direction.
  List<ExpenseCategory> _visibleCategories() {
    final visible = _categories
        .where((category) => category.kind.allows(isExpense: _isExpense))
        .toList();

    // A transaction being edited may sit in a category that no longer accepts
    // its own direction - an older record filed before the vocabulary settled.
    // Dropping it would silently reassign the transaction on open, so it is
    // pinned into the list.
    //
    // Only the category the transaction arrived with, and only while the
    // direction is unchanged. Pinning whatever happens to be selected would
    // make every category look valid for both directions and defeat the reset
    // in _setTransactionType.
    final existing = widget.existing;
    if (existing != null && existing.isExpense == _isExpense) {
      final pinned = existing.category;
      if (!visible.any((c) => c.name == pinned)) {
        final match = _categories.where((c) => c.name == pinned).firstOrNull;
        if (match != null) visible.insert(0, match);
      }
    }
    return visible;
  }

  @override
  void dispose() {
    // An attachment made and then abandoned leaves a file nothing points at.
    final orphan = _pendingReceiptPath;
    if (orphan != null) unawaited(ReceiptStorage.delete(orphan));

    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _saveTransaction() async {
    if (_isSaving) {
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      final title = _titleController.text.trim();
      final amountInPaisa = MoneyUtils.parseToPaisa(_amountController.text);

      final existing = widget.existing;
      final transaction = ExpenseModel(
        // Editing keeps the original id so the record is replaced rather than
        // duplicated, and any recurring link it carried survives.
        id: existing?.id ?? const Uuid().v4(),
        title: title,
        amount: MoneyUtils.paisaToAmount(amountInPaisa),
        category: _selectedCategory ?? ExpenseCategory.fallbackName,
        date: _date,
        isExpense: _isExpense,
        isWindfall: !_isExpense && _isWindfall,
        accountId: _accountId,
        receiptPath: _receiptPath,
        transferGroupId: existing?.transferGroupId,
        recurringExpenseId: existing?.recurringExpenseId,
        isAutoGenerated: existing?.isAutoGenerated ?? false,
      );

      // Saved, so the attachment is no longer provisional.
      _pendingReceiptPath = null;

      try {
        if (existing != null) {
          await UserDataService.updateTransaction(existing.id, transaction);
        } else {
          await UserDataService.addTransaction(transaction);
        }

        if (mounted) {
          Navigator.pop(context, true);
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final categories = _visibleCategories();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomInset + AppTokens.gapXl,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isEditing
                          ? 'Edit Transaction'
                          : 'Add Transaction',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gapMd),

              // Transaction Type Segmented Toggle Controls
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Expense')),
                      selected: _isExpense == true,
                      selectedColor: colorScheme.error.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: _isExpense
                            ? colorScheme.error
                            : colorScheme.onSurface,
                        fontWeight: _isExpense
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      showCheckmark: false,
                      onSelected: (val) => _setTransactionType(isExpense: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Income')),
                      selected: _isExpense == false,
                      selectedColor: colorScheme.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: !_isExpense
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        fontWeight: !_isExpense
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      showCheckmark: false,
                      onSelected: (val) => _setTransactionType(isExpense: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Title Input Form Field
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: _isExpense
                      ? 'e.g., Grocery Shopping'
                      : 'e.g., Monthly Salary',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.title_rounded),
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Please enter a title'
                    : null,
              ),
              const SizedBox(height: 16),

              // Amount Input Form Field
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Rs. 0.00',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.currency_rupee_rounded),
                ),
                validator: MoneyUtils.validateAmount,
              ),
              const SizedBox(height: 16),

              _DateField(date: _date, onPick: _pickDate),
              const SizedBox(height: 16),

              if (_accounts.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  initialValue: _accountId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Account',
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_rounded,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Not specified'),
                    ),
                    for (final account in _accounts)
                      DropdownMenuItem<String?>(
                        value: account.id,
                        child: Text(
                          account.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                ),
                const SizedBox(height: 16),
              ],

              if (_loadingCategories)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppTokens.gapXl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _CategoryPicker(
                  categories: categories,
                  selectedCategory: _selectedCategory,
                  onChanged: (category) {
                    if (category != _selectedCategory) {
                      setState(() => _selectedCategory = category);
                    }
                  },
                  onCreate: _createCategory,
                ),
              if (!_isExpense) ...[
                const SizedBox(height: AppTokens.gapLg),
                _WindfallToggle(
                  value: _isWindfall,
                  onChanged: (value) => setState(() => _isWindfall = value),
                ),
              ],
              const SizedBox(height: AppTokens.gapLg),
              _ReceiptField(
                path: _receiptPath,
                onAttach: _chooseReceiptSource,
                onView: _viewReceipt,
                onRemove: _removeReceipt,
              ),

              const SizedBox(height: 24),

              // Submit Save Action Button Component
              ElevatedButton(
                onPressed: _isSaving ? null : _saveTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isSaving
                      ? 'Saving...'
                      : widget.isEditing
                      ? 'Save Changes'
                      : 'Save Transaction',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _attachReceipt(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
    );
    if (picked == null) return;

    final stored = await ReceiptStorage.save(picked.path);
    if (stored == null || !mounted) return;

    // Replacing one attachment with another should not leave the first behind.
    final previous = _pendingReceiptPath;
    if (previous != null) await ReceiptStorage.delete(previous);

    setState(() {
      _receiptPath = stored;
      _pendingReceiptPath = stored;
    });
  }

  Future<void> _chooseReceiptSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _attachReceipt(source);
  }

  Future<void> _removeReceipt() async {
    final path = _receiptPath;
    setState(() {
      _receiptPath = null;
      _pendingReceiptPath = null;
    });
    // Only delete a file attached in this session. Removing the one already
    // saved on the record would destroy it before the user has confirmed the
    // edit, and dismissing the sheet would leave nothing to restore.
    if (path != null && path == _pendingReceiptPath) {
      await ReceiptStorage.delete(path);
    }
  }

  Future<void> _viewReceipt() async {
    final path = _receiptPath;
    if (path == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(AppTokens.gapLg),
        child: InteractiveViewer(
          child: Image.file(
            File(path),
            errorBuilder: (context, error, stack) => const Padding(
              padding: EdgeInsets.all(AppTokens.gapXl),
              child: Text('This receipt image is no longer on the device.'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      // Far enough back to enter a forgotten receipt, but not so far that the
      // wheel becomes a scrolling exercise.
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Transaction date',
    );
    if (picked == null || !mounted) return;

    setState(() {
      // Keep the original time so same-day ordering stays stable.
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
  }

  /// Lets the user add a category without leaving the sheet.
  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    final created = await CategoryService.create(
      name: name,
      kind: _isExpense ? CategoryKind.expense : CategoryKind.income,
    );
    final refreshed = await CategoryService.getOnce();
    if (!mounted) return;
    setState(() {
      _categories = refreshed;
      _selectedCategory = created.name;
    });
  }

  void _setTransactionType({required bool isExpense}) {
    if (_isExpense == isExpense) {
      return;
    }

    setState(() {
      _isExpense = isExpense;
      // The previous pick may not be valid for the new direction.
      final usable = _visibleCategories();
      final stillValid = usable.any((c) => c.name == _selectedCategory);
      if (!stillValid) {
        _selectedCategory = usable.firstOrNull?.name;
      }
    });
  }

}

class _CategoryPicker extends StatelessWidget {
  final List<ExpenseCategory> categories;
  final String? selectedCategory;
  final ValueChanged<String> onChanged;
  final VoidCallback onCreate;

  const _CategoryPicker({
    required this.categories,
    required this.selectedCategory,
    required this.onChanged,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: AppTokens.gapSm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Category',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = AppTokens.gapSm;
            final tileWidth = (constraints.maxWidth - spacing) / 2;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final category in categories)
                  SizedBox(
                    width: tileWidth,
                    height: 48,
                    child: _CategoryTile(
                      label: category.name,
                      icon: CategoryIcons.resolve(category.iconKey),
                      selected: category.name == selectedCategory,
                      onTap: () => onChanged(category.name),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.12)
          : colorScheme.appCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.appBorder,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapMd),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? colorScheme.onSurface : color,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marks income that is not part of the usual pattern.
///
/// Excluded from savings rate and averages so a one-off asset sale cannot make
/// a normal month look like a 99% saving month.
class _WindfallToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _WindfallToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.gapMd,
        vertical: AppTokens.gapSm,
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'One-off income',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Kept out of savings rate and averages',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Shows the transaction date and opens the picker when tapped.
///
/// Before this existed every manual entry was stamped with the moment it was
/// typed, so a receipt entered the next morning landed on the wrong day and
/// quietly moved money between months.
class _DateField extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPick;

  const _DateField({required this.date, required this.onPick});

  String get _label {
    final now = DateTime.now();
    final justDate = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(justDate).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[date.month - 1];
    return date.year == now.year
        ? '${date.day} $month'
        : '${date.day} $month ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          prefixIcon: const Icon(Icons.event_rounded),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.edit_calendar_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Attach, view or remove the photo behind a transaction.
class _ReceiptField extends StatelessWidget {
  final String? path;
  final VoidCallback onAttach;
  final VoidCallback onView;
  final VoidCallback onRemove;

  const _ReceiptField({
    required this.path,
    required this.onAttach,
    required this.onView,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (path == null) {
      return OutlinedButton.icon(
        onPressed: onAttach,
        icon: const Icon(Icons.attach_file_rounded, size: 18),
        label: const Text('Attach receipt'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: colorScheme.appBorder),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapSm),
      decoration: BoxDecoration(
        color: colorScheme.appCardMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onView,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              child: Image.file(
                File(path!),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  width: 44,
                  height: 44,
                  color: colorScheme.appCard,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.gapMd),
          Expanded(
            child: Text(
              'Receipt attached',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'View receipt',
            onPressed: onView,
            icon: const Icon(Icons.open_in_full_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Remove receipt',
            onPressed: onRemove,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colorScheme.error,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

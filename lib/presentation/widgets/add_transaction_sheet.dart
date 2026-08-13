import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/categories/category_icons.dart';
import '../../core/models/expense_category.dart';
import '../../core/models/expense_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../services/category_service.dart';
import '../../services/user_data_service.dart';

class AddTransactionSheet extends StatefulWidget {
  /// Supplies the category list instead of loading it.
  ///
  /// Only used by tests and previews; in the app it is null and the sheet
  /// reads the user's own vocabulary.
  final List<ExpenseCategory>? categoriesOverride;

  const AddTransactionSheet({super.key, this.categoriesOverride});

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

  /// The user's own vocabulary, loaded once when the sheet opens.
  List<ExpenseCategory> _categories = const [];
  bool _loadingCategories = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
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

  /// Categories usable for the current direction.
  List<ExpenseCategory> _visibleCategories() {
    return _categories
        .where((category) => category.kind.allows(isExpense: _isExpense))
        .toList();
  }

  @override
  void dispose() {
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

      // Create our database record model instance
      final newTransaction = ExpenseModel(
        id: const Uuid().v4(), // Generates a unique secure ID string
        title: title,
        amount: MoneyUtils.paisaToAmount(amountInPaisa),
        category: _selectedCategory ?? ExpenseCategory.fallbackName,
        date: DateTime.now(),
        isExpense: _isExpense,
        isWindfall: !_isExpense && _isWindfall,
      );

      try {
        await UserDataService.addTransaction(newTransaction);

        if (mounted) {
          Navigator.pop(context);
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
                      'Add Transaction',
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
                  _isSaving ? 'Saving...' : 'Save Transaction',
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

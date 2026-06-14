import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/expense_model.dart';
import '../../core/utils/money_utils.dart';

class AddTransactionSheet extends StatefulWidget {
  const AddTransactionSheet({super.key});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  String _selectedCategory = 'Food';
  bool _isExpense = true; // Toggle state: true = Expense, false = Income
  bool _isSaving = false;

  static const List<String> _expenseCategories = [
    'Food',
    'Travel',
    'Shopping',
    'Bills',
    'Other',
  ];

  static const List<String> _incomeCategories = [
    'Salary',
    'Freelance',
    'Business',
    'Investments',
    'Gifts',
    'Other',
  ];

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
        category: _selectedCategory,
        date: DateTime.now(),
        isExpense: _isExpense,
      );

      try {
        // Access our pre-opened Hive box and save the entry
        final box = Hive.box<ExpenseModel>('transactions');
        await box.add(newTransaction);
        await box.flush();

        // Close the modal sheet panel view
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
    final categories = _isExpense ? _expenseCategories : _incomeCategories;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Transaction',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colorScheme.onSurface),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),

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

              _CategoryPicker(
                categories: categories,
                selectedCategory: _selectedCategory,
                iconForCategory: _categoryIcon,
                onChanged: (category) {
                  if (category != _selectedCategory) {
                    setState(() => _selectedCategory = category);
                  }
                },
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

  void _setTransactionType({required bool isExpense}) {
    if (_isExpense == isExpense) {
      return;
    }

    final nextCategories = isExpense ? _expenseCategories : _incomeCategories;
    setState(() {
      _isExpense = isExpense;
      _selectedCategory = nextCategories.first;
    });
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant_rounded;
      case 'Travel':
        return Icons.flight_takeoff_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      case 'Bills':
        return Icons.receipt_long_rounded;
      case 'Salary':
        return Icons.monetization_on_rounded;
      case 'Freelance':
        return Icons.laptop_mac_rounded;
      case 'Business':
        return Icons.storefront_rounded;
      case 'Investments':
        return Icons.trending_up_rounded;
      case 'Gifts':
        return Icons.card_giftcard_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }
}

class _CategoryPicker extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final IconData Function(String category) iconForCategory;
  final ValueChanged<String> onChanged;

  const _CategoryPicker({
    required this.categories,
    required this.selectedCategory,
    required this.iconForCategory,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
            'Category',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
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
                      label: category,
                      icon: iconForCategory(category),
                      selected: category == selectedCategory,
                      onTap: () => onChanged(category),
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
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outline,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: colorScheme.primary.withValues(alpha: 0.10),
        highlightColor: colorScheme.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    fontSize: 14,
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

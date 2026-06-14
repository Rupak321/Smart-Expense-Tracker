import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/components/summary_item.dart';
import '../../../core/components/transaction_tile.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/models/user_profile_model.dart';
import '../../../core/utils/money_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _profileFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _occupationController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  String? _profileImagePath;
  bool _profilePromptShown = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transactionBox = Hive.isBoxOpen('transactions')
        ? Hive.box<ExpenseModel>('transactions')
        : null;
    final profileBox = Hive.isBoxOpen('user_profile')
        ? Hive.box<UserProfileModel>('user_profile')
        : null;

    if (transactionBox == null) {
      return const Center(child: Text('No transactions available'));
    }

    return StreamBuilder<BoxEvent>(
      stream: transactionBox.watch(),
      builder: (context, snapshot) {
        final transactions = _sortedTransactions(transactionBox);
        final expenseTransactions =
            transactions.where((tx) => tx.isExpense).toList();
        final incomePaisa = _totalPaisa(
          transactions.where((tx) => !tx.isExpense),
        );
        final expensePaisa = _totalPaisa(expenseTransactions);
        final balancePaisa = incomePaisa - expensePaisa;

        Widget content(String userName) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeaderCard(
                  context,
                  userName,
                  balancePaisa,
                  incomePaisa,
                  expensePaisa,
                ),
              ),
              SliverToBoxAdapter(child: _buildSectionHeader(context)),
              if (transactions.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 40, 16, 170),
                          child: Center(
                            child: Text(
                              'Add income or expenses to see your balance and history.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final transaction = transactions[index];
                        final sign = transaction.isExpense ? '-' : '+';
                        return TransactionTile(
                          title: transaction.title,
                          category: _dateLabel(transaction.date, transaction.category),
                          amount:
                              '$sign ${MoneyUtils.formatAmount(transaction.amount)}',
                          isExpense: transaction.isExpense,
                          icon: _iconForCategory(transaction.category),
                        );
                      },
                      childCount: transactions.length,
                    ),
                  ),
                ),
            ],
          );
        }

        if (profileBox != null) {
          final profileData = profileBox.get('primary');
          if (profileData == null && !_profilePromptShown) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showProfilePopup(profileBox);
            });
          }

          return StreamBuilder<BoxEvent>(
            stream: profileBox.watch(key: 'primary'),
            builder: (context, profileSnapshot) {
              final profileData = profileBox.get('primary');
              final userName = profileData?.name.trim().isNotEmpty == true
                  ? profileData!.name
                  : 'Guest User';
              return content(userName);
            },
          );
        }

        return content('Guest User');
      },
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    String userName,
    int balancePaisa,
    int incomePaisa,
    int expensePaisa,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          _decorativeCircle(-30, 30, 100, 0.08, color: colorScheme.primary),
          _decorativeCircle(10, -20, 80, 0.06, color: colorScheme.primary),
          _decorativeCircle(null, 60, 70, 0.06, color: colorScheme.primary, bottom: -20),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good afternoon,',
                  style: TextStyle(
                    color: colorScheme.onPrimary.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
                Text(
                  userName,
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Total Balance',
                  style: TextStyle(
                    color: colorScheme.onPrimary.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
                Text(
                  MoneyUtils.formatPaisa(balancePaisa),
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                Divider(color: colorScheme.onPrimary.withValues(alpha: 0.2), thickness: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SummaryItem(
                        icon: Icons.arrow_downward,
                        label: 'Income',
                        amount: MoneyUtils.formatPaisa(incomePaisa),
                      ),
                    ),
                    Expanded(
                      child: SummaryItem(
                        icon: Icons.arrow_upward,
                        label: 'Expenses',
                        amount: MoneyUtils.formatPaisa(expensePaisa),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Transactions History',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          TextButton(onPressed: () {}, child: Text('See all', style: TextStyle(color: Theme.of(context).colorScheme.primary))),
        ],
      ),
    );
  }

  List<ExpenseModel> _sortedTransactions(Box<ExpenseModel> box) {
    final transactions = box.values.toList();
    transactions.sort((a, b) => b.date.compareTo(a.date));
    return transactions;
  }

  int _totalPaisa(Iterable<ExpenseModel> transactions) {
    return transactions.fold(0, (sum, tx) => sum + tx.amountPaisa);
  }

  String _dateLabel(DateTime date, String category) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$category • $day/$month/${date.year}';
  }

  IconData _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.fastfood;
      case 'shopping':
        return Icons.shopping_bag;
      case 'travel':
        return Icons.flight;
      case 'bills':
        return Icons.receipt_long;
      case 'salary':
      case 'income':
        return Icons.attach_money;
      case 'freelance':
        return Icons.laptop_mac;
      case 'business':
        return Icons.storefront;
      case 'investments':
        return Icons.trending_up;
      case 'gifts':
        return Icons.card_giftcard;
      case 'entertainment':
        return Icons.movie;
      default:
        return Icons.category;
    }
  }

  Future<void> _showProfilePopup(Box<UserProfileModel> profileBox) async {
    if (!mounted) return;

    setState(() {
      _profilePromptShown = true;
    });

    _nameController.clear();
    _phoneController.clear();
    _addressController.clear();
    _emailController.clear();
    _occupationController.clear();
    _profileImagePath = null;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Text(
                      'Welcome to Smart Expense',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Add your personal details to get started.',
                      textAlign: TextAlign.center,
                        style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await _imagePicker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 800,
                            maxHeight: 800,
                            imageQuality: 80,
                          );
                          if (picked == null) return;
                          setSheetState(() {
                            _profileImagePath = picked.path;
                          });
                        },
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            image: _profileImagePath != null
                                ? DecorationImage(
                                    image: FileImage(File(_profileImagePath!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _profileImagePath == null
                              ? Icon(
                                  Icons.camera_alt_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 34,
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _profileFormKey,
                      child: Column(
                        children: [
                          _buildProfileField(
                            controller: _nameController,
                            label: 'Full Name',
                            icon: Icons.person_rounded,
                            validator: _requiredValidator,
                          ),
                          const SizedBox(height: 12),
                          _buildProfileField(
                            controller: _phoneController,
                            label: 'Phone Number',
                            icon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                            validator: _phoneValidator,
                          ),
                          const SizedBox(height: 12),
                          _buildProfileField(
                            controller: _emailController,
                            label: 'Email',
                            icon: Icons.mail_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: _emailValidator,
                          ),
                          const SizedBox(height: 12),
                          _buildProfileField(
                            controller: _occupationController,
                            label: 'Occupation',
                            icon: Icons.work_rounded,
                          ),
                          const SizedBox(height: 12),
                          _buildProfileField(
                            controller: _addressController,
                            label: 'Address',
                            icon: Icons.location_on_rounded,
                            minLines: 2,
                            maxLines: 3,
                            validator: _requiredValidator,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        if (!_profileFormKey.currentState!.validate()) {
                          return;
                        }
                        final navigator = Navigator.of(context);
                        await _saveProfile(profileBox);
                        if (!mounted) return;
                        navigator.pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Save and Continue',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _saveProfile(Box<UserProfileModel> profileBox) async {
    final profile = UserProfileModel(
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      email: _emailController.text.trim(),
      occupation: _occupationController.text.trim(),
      updatedAt: DateTime.now(),
      profileImagePath: _profileImagePath,
    );

    await profileBox.put('primary', profile);
    await profileBox.flush();
  }

  Widget _buildProfileField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
      ),
      validator: validator,
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Phone number is required';
    }
    if (!RegExp(r'^[0-9+\-\s]{7,16}$').hasMatch(trimmed)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  Widget _decorativeCircle(double? top, double? right, double size, double opacity, {double? bottom, double? left, Color? color}) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: (color ?? Colors.white).withValues(alpha: opacity)),
      ),
    );
  }
}

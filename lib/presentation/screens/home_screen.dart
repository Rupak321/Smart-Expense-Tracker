import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../core/components/summary_item.dart';
import '../../../core/components/transaction_tile.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/models/user_profile_model.dart';
import '../../../core/utils/money_utils.dart';
import '../../../core/utils/profile_image_storage.dart';
import '../../../services/ai_expense_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_data_service.dart';

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
  final _smartExpenseController = TextEditingController();

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
    _smartExpenseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExpenseModel>>(
      stream: UserDataService.transactionsStream(),
      builder: (context, snapshot) {
        final transactions = _sortedTransactions(snapshot.data ?? const <ExpenseModel>[]);
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
              SliverToBoxAdapter(
                child: _buildSmartExpenseInput(context),
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

        return StreamBuilder<UserProfileModel?>(
          stream: UserDataService.profileStream(),
          builder: (context, profileSnapshot) {
            final authUser = AuthService.currentUser;
            final profileData = profileSnapshot.data ??
                (authUser != null
                    ? UserProfileModel(
                        name: authUser.displayName ?? '',
                        phoneNumber: '',
                        address: '',
                        email: authUser.email ?? '',
                        occupation: '',
                        updatedAt: DateTime.now(),
                        profileImagePath: authUser.photoURL,
                      )
                    : null);

            if (profileData == null && !_profilePromptShown) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showProfilePopup();
              });
            }
            final userName = profileData?.name.trim().isNotEmpty == true
                ? profileData!.name
                : 'Guest User';
            return content(userName);
          },
        );
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
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      MoneyUtils.formatPaisa(balancePaisa),
                      maxLines: 1,
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
                    const SizedBox(width: 12),
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

  Widget _buildSmartExpenseInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: TextField(
          controller: _smartExpenseController,
          decoration: InputDecoration(
            hintText: 'AI add (e.g. salary 45k, Rs. 450 food)',
            hintStyle: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.auto_awesome,
              color: Theme.of(context).colorScheme.primary,
            ),
            suffixIcon: _isProcessingSmartExpense
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      Icons.send_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: _processSmartExpense,
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          onSubmitted: (_) => _processSmartExpense(),
        ),
      ),
    );
  }

  bool _isProcessingSmartExpense = false;

  void _processSmartExpense() async {
    final text = _smartExpenseController.text.trim();
    if (text.isEmpty || _isProcessingSmartExpense) return;

    setState(() {
      _isProcessingSmartExpense = true;
    });

    try {
      final result = await AiExpenseService.parseExpense(text);
      if (!mounted) return;

      if (result != null && result.amount > 0) {
        final newExpense = ExpenseModel(
          id: const Uuid().v4(),
          title: result.title,
          amount: result.amount,
          category: result.category,
          date: DateTime.now(),
          isExpense: result.isExpense,
        );

        await UserDataService.addTransaction(newExpense);
        if (!mounted) return;
        _smartExpenseController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${result.isExpense ? 'expense' : 'income'}: Rs. ${result.amount}',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not detect expense details. Please try again.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSmartExpense = false;
        });
      }
    }
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
          TextButton(
            onPressed: () {},
            child: Text(
              'See all',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  List<ExpenseModel> _sortedTransactions(List<ExpenseModel> transactions) {
    final sorted = List<ExpenseModel>.from(transactions);
    sorted.sort((a, b) => b.date.compareTo(a.date));
    return sorted;
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
    final lower = category.toLowerCase();
    if (lower.contains('food') ||
        lower.contains('restaurant') ||
        lower.contains('grocer')) {
      return Icons.fastfood;
    }
    if (lower.contains('shopping') ||
        lower.contains('clothes') ||
        lower.contains('electronics')) {
      return Icons.shopping_bag;
    }
    if (lower.contains('travel') || lower.contains('transport')) {
      return Icons.flight;
    }
    if (lower.contains('bill') || lower.contains('utilit')) {
      return Icons.receipt_long;
    }
    if (lower.contains('salary') ||
        lower.contains('income') ||
        lower.contains('freelance') ||
        lower.contains('business')) {
      return Icons.attach_money;
    }
    if (lower.contains('invest')) return Icons.trending_up;
    if (lower.contains('gift')) return Icons.card_giftcard;
    if (lower.contains('entertain') || lower.contains('movie')) {
      return Icons.movie;
    }
    if (lower.contains('health') || lower.contains('medic')) {
      return Icons.local_hospital;
    }
    return Icons.category;
  }

  Future<void> _showProfilePopup() async {
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
                          final savedPath =
                              await ProfileImageStorage.savePickedImage(picked.path);
                          setSheetState(() {
                            _profileImagePath = savedPath;
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
                        await _saveProfile();
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

  Future<void> _saveProfile() async {
    final profile = UserProfileModel(
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      email: _emailController.text.trim(),
      occupation: _occupationController.text.trim(),
      updatedAt: DateTime.now(),
      profileImagePath: _profileImagePath,
    );

    await UserDataService.saveProfile(profile);
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

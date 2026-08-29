import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/components/app_widgets.dart';
import '../../../core/components/summary_item.dart';
import '../../../core/components/transaction_tile.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/models/user_profile_model.dart';
import '../../../core/parser/transaction_parser_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_utils.dart';
import '../../../core/utils/profile_image_storage.dart';
import '../../../services/auth_service.dart';
import '../../../services/user_data_service.dart';
import '../widgets/add_transaction_sheet.dart';
import 'main_navigation.dart';
import 'recurring_expenses_screen.dart';

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
  bool _recurringCatchUpStarted = false;
  bool _isProcessingSmartExpense = false;

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
    _runRecurringCatchUpOnce();
    final bottomInset = NavShellInsets.of(context);

    return StreamBuilder<List<ExpenseModel>>(
      stream: UserDataService.transactionsStream(),
      builder: (context, snapshot) {
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final transactions = _sortedTransactions(
          snapshot.data ?? const <ExpenseModel>[],
        );
        final incomePaisa = _totalPaisa(
          transactions.where((tx) => tx.countsAsIncome),
        );
        final expensePaisa = _totalPaisa(
          transactions.where((tx) => tx.countsAsExpense),
        );
        final balancePaisa = incomePaisa - expensePaisa;

        Widget content(String userName) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _BalanceHeader(
                  userName: userName,
                  balancePaisa: balancePaisa,
                  incomePaisa: incomePaisa,
                  expensePaisa: expensePaisa,
                ),
              ),
              SliverToBoxAdapter(child: _buildSmartExpenseInput(context)),
              const SliverToBoxAdapter(child: UpcomingRecurringSection()),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Transaction History',
                  trailing: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecurringExpensesScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.repeat_rounded, size: 16),
                    label: const Text('Recurring'),
                  ),
                ),
              ),
              if (isLoading)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.pageGutter,
                    0,
                    AppTokens.pageGutter,
                    bottomInset,
                  ),
                  sliver: const SliverToBoxAdapter(
                    child: TransactionListSkeleton(),
                  ),
                )
              else if (transactions.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(0, AppTokens.gapSm, 0, bottomInset),
                  sliver: const SliverToBoxAdapter(
                    child: EmptyStateCard(
                      icon: Icons.receipt_long_rounded,
                      title: 'No transactions yet',
                      message:
                          'Tap + to record one, or type something like '
                          '"450 lunch" in the box above.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.pageGutter,
                    0,
                    AppTokens.pageGutter,
                    bottomInset,
                  ),
                  sliver: SliverList.builder(
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];
                      final sign = transaction.isExpense ? '-' : '+';
                      return Dismissible(
                        key: ValueKey(transaction.id),
                        direction: DismissDirection.endToStart,
                        background: const _DeleteSwipeBackground(),
                        confirmDismiss: (_) => _confirmDelete(transaction),
                        child: TransactionTile(
                          title: transaction.title,
                          category: _dateLabel(
                            transaction.date,
                            transaction.category,
                          ),
                          amount:
                              '$sign ${MoneyUtils.formatAmount(transaction.amount)}',
                          isExpense: transaction.isExpense,
                          icon: _iconForCategory(transaction.category),
                          onTap: () => _showTransactionActions(transaction),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        }

        return StreamBuilder<UserProfileModel?>(
          stream: UserDataService.profileStream(),
          builder: (context, profileSnapshot) {
            final authUser = AuthService.currentUser;
            final profileData =
                profileSnapshot.data ??
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

  Widget _buildSmartExpenseInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.pageGutter,
        vertical: AppTokens.gapSm,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.appCard,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.28),
          ),
        ),
        child: TextField(
          controller: _smartExpenseController,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'Quick add — try "450 lunch"',
            filled: false,
            hintStyle: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.auto_awesome_rounded,
              color: colorScheme.primary,
              size: 20,
            ),
            suffixIcon: _isProcessingSmartExpense
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Add with AI',
                    icon: Icon(
                      Icons.send_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    onPressed: _processSmartExpense,
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.gapLg,
              vertical: AppTokens.gapMd,
            ),
          ),
          onSubmitted: (_) => _processSmartExpense(),
        ),
      ),
    );
  }

  Future<void> _processSmartExpense() async {
    final text = _smartExpenseController.text.trim();
    if (text.isEmpty || _isProcessingSmartExpense) return;

    setState(() => _isProcessingSmartExpense = true);

    try {
      final parser = TransactionParserService();
      final result = await parser.parse(text);
      if (!mounted) return;

      if (result.amount > 0) {
        final newExpense = ExpenseModel(
          id: const Uuid().v4(),
          title: result.title,
          amount: result.amount,
          category: result.category,
          date: DateTime.now(),
          isExpense: result.type == TransactionType.expense,
        );

        await UserDataService.addTransaction(newExpense);
        if (!mounted) return;
        _smartExpenseController.clear();
        FocusScope.of(context).unfocus();

        final isExpense = result.type == TransactionType.expense;
        _showSnack(
          'Added ${isExpense ? 'expense' : 'income'}: '
          '${MoneyUtils.formatAmount(result.amount)}',
          icon: Icons.check_circle_rounded,
        );
      } else {
        _showSnack(
          'Could not read an amount from that. Try "450 lunch".',
          icon: Icons.error_outline_rounded,
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e.toString().replaceAll('Exception: ', ''),
        icon: Icons.error_outline_rounded,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingSmartExpense = false);
      }
    }
  }

  void _showSnack(String message, {IconData? icon, bool isError = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: isError
                      ? colorScheme.error
                      : colorScheme.onInverseSurface,
                ),
                const SizedBox(width: AppTokens.gapSm),
              ],
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  /// Actions for an existing transaction.
  ///
  /// Tapping a row used to jump straight to a delete prompt, which left no way
  /// to mark an already-recorded one-off such as an asset sale.
  Future<void> _showTransactionActions(ExpenseModel transaction) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.gapXl,
                  0,
                  AppTokens.gapXl,
                  AppTokens.gapSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${transaction.category} · '
                      '${MoneyUtils.formatAmount(transaction.amount)}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                onTap: () => Navigator.pop(sheetContext, 'edit'),
                leading: Icon(
                  Icons.edit_outlined,
                  color: colorScheme.primary,
                ),
                title: const Text('Edit'),
                subtitle: const Text('Change amount, date, category or type'),
              ),
              if (!transaction.isExpense)
                ListTile(
                  onTap: () => Navigator.pop(sheetContext, 'windfall'),
                  leading: Icon(
                    transaction.isWindfall
                        ? Icons.repeat_rounded
                        : Icons.bolt_rounded,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    transaction.isWindfall
                        ? 'Treat as regular income'
                        : 'Mark as one-off income',
                  ),
                  subtitle: Text(
                    transaction.isWindfall
                        ? 'Counts towards savings rate again'
                        : 'Keeps it out of savings rate and averages',
                  ),
                ),
              ListTile(
                onTap: () => Navigator.pop(sheetContext, 'delete'),
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
              const SizedBox(height: AppTokens.gapSm),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'edit') {
      await _editTransaction(transaction);
      return;
    }

    if (action == 'windfall') {
      await UserDataService.updateTransaction(
        transaction.id,
        transaction.copyWith(isWindfall: !transaction.isWindfall),
      );
      if (mounted) {
        _showSnack(
          transaction.isWindfall
              ? 'Counted as regular income again'
              : 'Marked as one-off income',
          icon: Icons.check_circle_rounded,
        );
      }
      return;
    }

    if (action == 'delete') {
      await _confirmDelete(transaction);
    }
  }

  Future<void> _editTransaction(ExpenseModel transaction) async {
    final saved = await showTransactionSheet(context, existing: transaction);
    if (saved == true && mounted) {
      _showSnack('Transaction updated', icon: Icons.check_circle_rounded);
    }
  }

  Future<bool> _confirmDelete(ExpenseModel transaction) async {
    final colorScheme = Theme.of(context).colorScheme;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          '"${transaction.title}" will be removed permanently.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return false;

    await UserDataService.deleteTransaction(transaction.id);
    if (mounted) {
      _showSnack('Transaction deleted', icon: Icons.delete_outline_rounded);
    }
    return true;
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
      return Icons.restaurant_rounded;
    }
    if (lower.contains('shopping') ||
        lower.contains('clothes') ||
        lower.contains('electronics')) {
      return Icons.shopping_bag_rounded;
    }
    if (lower.contains('travel') || lower.contains('transport')) {
      return Icons.flight_takeoff_rounded;
    }
    if (lower.contains('bill') || lower.contains('utilit')) {
      return Icons.receipt_long_rounded;
    }
    if (lower.contains('salary') ||
        lower.contains('income') ||
        lower.contains('freelance') ||
        lower.contains('business')) {
      return Icons.payments_rounded;
    }
    if (lower.contains('invest')) return Icons.trending_up_rounded;
    if (lower.contains('gift')) return Icons.card_giftcard_rounded;
    if (lower.contains('entertain') || lower.contains('movie')) {
      return Icons.movie_rounded;
    }
    if (lower.contains('health') || lower.contains('medic')) {
      return Icons.medical_services_rounded;
    }
    return Icons.category_rounded;
  }

  Future<void> _showProfilePopup() async {
    if (!mounted) return;

    setState(() => _profilePromptShown = true);

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
      useSafeArea: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.gapLg,
                  0,
                  AppTokens.gapLg,
                  AppTokens.gapXl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome to Smart Expense',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppTokens.gapSm),
                    Text(
                      'Add your personal details to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: AppTokens.gapXl),
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
                              await ProfileImageStorage.savePickedImage(
                                picked.path,
                              );
                          setSheetState(() => _profileImagePath = savedPath);
                        },
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.14),
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
                                  color: colorScheme.primary,
                                  size: 32,
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.gapXl),
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
                          const SizedBox(height: AppTokens.gapMd),
                          _buildProfileField(
                            controller: _phoneController,
                            label: 'Phone Number',
                            icon: Icons.phone_rounded,
                            keyboardType: TextInputType.phone,
                            validator: _phoneValidator,
                          ),
                          const SizedBox(height: AppTokens.gapMd),
                          _buildProfileField(
                            controller: _emailController,
                            label: 'Email',
                            icon: Icons.mail_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: _emailValidator,
                          ),
                          const SizedBox(height: AppTokens.gapMd),
                          _buildProfileField(
                            controller: _occupationController,
                            label: 'Occupation',
                            icon: Icons.work_rounded,
                          ),
                          const SizedBox(height: AppTokens.gapMd),
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
                    const SizedBox(height: AppTokens.gapXl),
                    FilledButton(
                      onPressed: () async {
                        if (!_profileFormKey.currentState!.validate()) {
                          return;
                        }
                        final navigator = Navigator.of(context);
                        await _saveProfile();
                        if (!mounted) return;
                        navigator.pop();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('Save and Continue'),
                    ),
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
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
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

  void _runRecurringCatchUpOnce() {
    if (_recurringCatchUpStarted) {
      return;
    }
    _recurringCatchUpStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final generated = await UserDataService.runRecurringCatchUp();
        if (!mounted || generated == 0) {
          return;
        }
        _showSnack(
          'Added $generated recurring transaction${generated == 1 ? '' : 's'}',
          icon: Icons.repeat_rounded,
        );
      } catch (_) {}
    });
  }
}

class _BalanceHeader extends StatelessWidget {
  final String userName;
  final int balancePaisa;
  final int incomePaisa;
  final int expensePaisa;

  const _BalanceHeader({
    required this.userName,
    required this.balancePaisa,
    required this.incomePaisa,
    required this.expensePaisa,
  });

  /// Greeting follows the clock instead of always claiming it is afternoon.
  static String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    if (hour < 21) return 'Good evening,';
    return 'Good night,';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNegative = balancePaisa < 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.pageGutter,
        AppTokens.gapMd,
        AppTokens.pageGutter,
        AppTokens.gapSm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colorScheme.appHeroGradient,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        child: Stack(
          children: [
            Positioned(
              top: -34,
              right: 18,
              child: _Bubble(size: 108, color: colorScheme.appOnHero),
            ),
            Positioned(
              bottom: -28,
              right: 76,
              child: _Bubble(size: 78, color: colorScheme.appOnHero),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(DateTime.now()),
                    style: TextStyle(
                      color: colorScheme.appOnHero.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.appOnHero,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Total Balance',
                        style: TextStyle(
                          color: colorScheme.appOnHero.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                      if (isNegative) ...[
                        const SizedBox(width: AppTokens.gapSm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.gapSm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.appOnHero.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusPill,
                            ),
                          ),
                          child: Text(
                            'Overspent',
                            style: TextStyle(
                              color: colorScheme.appOnHero,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        MoneyUtils.formatPaisa(balancePaisa),
                        maxLines: 1,
                        style: TextStyle(
                          color: colorScheme.appOnHero,
                          fontSize: 34,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Divider(
                    color: colorScheme.appOnHero.withValues(alpha: 0.24),
                    height: 1,
                  ),
                  const SizedBox(height: AppTokens.gapLg),
                  Row(
                    children: [
                      Expanded(
                        child: SummaryItem(
                          icon: Icons.arrow_downward_rounded,
                          label: 'Income',
                          amount: MoneyUtils.formatPaisa(incomePaisa),
                        ),
                      ),
                      const SizedBox(width: AppTokens.gapMd),
                      Expanded(
                        child: SummaryItem(
                          icon: Icons.arrow_upward_rounded,
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
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final double size;
  final Color color;

  const _Bubble({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.09),
      ),
    );
  }
}

class _DeleteSwipeBackground extends StatelessWidget {
  const _DeleteSwipeBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.gapSm),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      alignment: Alignment.centerRight,
      child: Icon(
        Icons.delete_rounded,
        color: colorScheme.onErrorContainer,
      ),
    );
  }
}

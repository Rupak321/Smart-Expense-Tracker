import 'package:flutter/material.dart';
import 'account_screen.dart';
import 'all_expenses_screen.dart';
import 'analytics_screen.dart';
import 'home_screen.dart';
import '../widgets/add_transaction_sheet.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;

  const MainNavigation({super.key, this.initialIndex = 0});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screens = [
      const HomeScreen(),
      const AllExpensesScreen(),
      const AnalyticsScreen(),
      const AccountScreen(),
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: screens),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled:
                true, // Ensures layout pushes upward smoothly over the software panel keyboard
            backgroundColor: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (context) => const AddTransactionSheet(),
          );
        },
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: colorScheme.surface,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(Icons.home_rounded, 0),
              _buildNavItem(Icons.receipt_long_rounded, 1),
              const SizedBox(
                width: 40,
              ), // Void clearance width spacing allocation structural buffer for center FAB inclusion
              _buildNavItem(Icons.bar_chart_rounded, 2),
              _buildNavItem(Icons.person_outline_rounded, 3),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds unified responsive nav system selectors mapping dynamic state contexts
  Widget _buildNavItem(IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: () => setState(() => _selectedIndex = index),
      icon: Icon(
        icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 26,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'account_screen.dart';
import 'all_expenses_screen.dart';
import 'analytics_screen.dart';
import 'home_screen.dart';
import '../widgets/add_transaction_sheet.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const AllExpensesScreen(),
      const AnalyticsScreen(),
      const AccountScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: screens),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled:
                true, // Ensures layout pushes upward smoothly over the software panel keyboard
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (context) => const AddTransactionSheet(),
          );
        },
        backgroundColor: const Color(0xFF2A9D8F),
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
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
    return IconButton(
      onPressed: () => setState(() => _selectedIndex = index),
      icon: Icon(
        icon,
        color: isSelected ? const Color(0xFF2A9D8F) : Colors.grey.shade400,
        size: 26,
      ),
    );
  }
}

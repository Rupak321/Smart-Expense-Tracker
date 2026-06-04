import 'package:flutter/material.dart';
import '../../../core/components/summary_item.dart';
import '../../../core/components/transaction_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeaderCard()),
        SliverToBoxAdapter(child: _buildSectionHeader(context)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final transactions = [
                  {'title': 'Grocery Store', 'subtitle': 'Food & Drinks', 'amount': '- Rs. 2,450', 'isExpense': true, 'icon': Icons.shopping_basket_rounded},
                  {'title': 'Freelance Project', 'subtitle': 'Salary Pay', 'amount': '+ Rs. 45,000', 'isExpense': false, 'icon': Icons.monetization_on_rounded},
                  {'title': 'Netflix Subscription', 'subtitle': 'Entertainment', 'amount': '- Rs. 1,200', 'isExpense': true, 'icon': Icons.tv_rounded},
                ];

                if (index >= transactions.length) return null;
                final item = transactions[index];

                return TransactionTile(
                  title: item['title'] as String,
                  category: item['subtitle'] as String,
                  amount: item['amount'] as String,
                  isExpense: item['isExpense'] as bool,
                  icon: item['icon'] as IconData,
                );
              },
              childCount: 3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A9D8F),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A9D8F).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          _decorativeCircle(-30, 30, 100, 0.08),
          _decorativeCircle(10, -20, 80, 0.06),
          _decorativeCircle(null, 60, 70, 0.06, bottom: -20),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Good afternoon,', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                const Text('Rupak Pandey', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 22),
                Text('Total Balance', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                const Text('Rs. 5,000', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                Divider(color: Colors.white.withValues(alpha: 0.2), thickness: 1),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Expanded(child: SummaryItem(icon: Icons.arrow_downward, label: 'Income', amount: 'Rs. 200,000')),
                    Expanded(child: SummaryItem(icon: Icons.arrow_upward, label: 'Expenses', amount: 'Rs. 15,000')),
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
          const Text('Transactions History', style: TextStyle(color: Color(0xFF1A1A2E), fontSize: 16, fontWeight: FontWeight.w700)),
          TextButton(onPressed: () {}, child: const Text('See all', style: TextStyle(color: Color(0xFF2A9D8F)))),
        ],
      ),
    );
  }

  Widget _decorativeCircle(double? top, double? right, double size, double opacity, {double? bottom, double? left}) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: opacity)),
      ),
    );
  }
}
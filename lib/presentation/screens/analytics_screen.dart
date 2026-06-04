import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/models/expense_model.dart';
import '../../../core/utils/money_utils.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  static const _accent = Color(0xFF2A9D8F);
  static const _ink = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context) {
    final box = Hive.isBoxOpen('transactions') ? Hive.box<ExpenseModel>('transactions') : null;

    if (box == null) {
      return const Center(child: Text('No transactions available'));
    }

    return StreamBuilder<BoxEvent>(
      stream: box.watch(),
      builder: (context, snapshot) {
        final transactions = _sortedTransactions(box);
        final expenses = transactions
            .where((transaction) => transaction.isExpense)
            .toList();
        final incomePaisa = _totalPaisa(
          transactions.where((transaction) => !transaction.isExpense),
        );
        final expensePaisa = _totalPaisa(expenses);
        final categorySlices = _buildCategorySlices(expenses);
        final trend = _buildRecentTrend(expenses);

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
            SliverToBoxAdapter(
              child: _SummaryBand(
                incomePaisa: incomePaisa,
                expensePaisa: expensePaisa,
              ),
            ),
            SliverToBoxAdapter(
              child: _ChartPanel(
                totalExpensePaisa: expensePaisa,
                slices: categorySlices,
              ),
            ),
            SliverToBoxAdapter(child: _TrendPanel(points: trend)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Category Details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (categorySlices.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 170),
                  child: Center(
                    child: Text(
                      'Add expenses to see detailed analytics',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 170),
                sliver: SliverList.separated(
                  itemCount: categorySlices.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _CategoryBreakdownRow(
                      slice: categorySlices[index],
                      maxPaisa: categorySlices.first.paisa,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  List<ExpenseModel> _sortedTransactions(Box<ExpenseModel>? box) {
    if (box == null) {
      return [];
    }

    final transactions = box.values.toList();
    transactions.sort((first, second) => second.date.compareTo(first.date));
    return transactions;
  }

  int _totalPaisa(Iterable<ExpenseModel> transactions) {
    return transactions.fold(
      0,
      (total, transaction) =>
          total + MoneyUtils.amountToPaisa(transaction.amount),
    );
  }

  List<_CategorySlice> _buildCategorySlices(List<ExpenseModel> expenses) {
    final totals = <String, int>{};
    for (final expense in expenses) {
      totals.update(
        expense.category,
        (value) => value + MoneyUtils.amountToPaisa(expense.amount),
        ifAbsent: () => MoneyUtils.amountToPaisa(expense.amount),
      );
    }

    final colors = <String, Color>{
      'Food': const Color(0xFFE76F51),
      'Travel': const Color(0xFF457B9D),
      'Shopping': const Color(0xFFE9C46A),
      'Salary': const Color(0xFF2A9D8F),
      'Other': const Color(0xFF7C6AAB),
    };

    final slices = totals.entries.map((entry) {
      return _CategorySlice(
        label: entry.key,
        paisa: entry.value,
        color: colors[entry.key] ?? _accent,
        icon: _iconForCategory(entry.key),
      );
    }).toList();

    slices.sort((first, second) => second.paisa.compareTo(first.paisa));
    return slices;
  }

  List<_TrendPoint> _buildRecentTrend(List<ExpenseModel> expenses) {
    final today = DateTime.now();
    final days = List.generate(7, (index) {
      final day = today.subtract(Duration(days: 6 - index));
      return DateTime(day.year, day.month, day.day);
    });
    final totals = {for (final day in days) day: 0};

    for (final expense in expenses) {
      final day = DateTime(
        expense.date.year,
        expense.date.month,
        expense.date.day,
      );
      if (totals.containsKey(day)) {
        totals[day] = totals[day]! + MoneyUtils.amountToPaisa(expense.amount);
      }
    }

    return days.map((day) {
      return _TrendPoint(label: _shortDay(day), paisa: totals[day] ?? 0);
    }).toList();
  }

  String _shortDay(DateTime date) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.weekday - 1];
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant_rounded;
      case 'Travel':
        return Icons.flight_takeoff_rounded;
      case 'Shopping':
        return Icons.shopping_bag_rounded;
      case 'Salary':
        return Icons.monetization_on_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Analytics',
              style: TextStyle(
                color: AnalyticsScreen._ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AnalyticsScreen._accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
            child: const Icon(
              Icons.insights_rounded,
              color: AnalyticsScreen._accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBand extends StatelessWidget {
  final int incomePaisa;
  final int expensePaisa;

  const _SummaryBand({required this.incomePaisa, required this.expensePaisa});

  @override
  Widget build(BuildContext context) {
    final balancePaisa = incomePaisa - expensePaisa;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _MetricCard(
              label: 'Balance',
              amount: MoneyUtils.formatPaisa(balancePaisa),
              icon: Icons.account_balance_wallet_rounded,
              color: AnalyticsScreen._accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCard(
              label: 'Spent',
              amount: MoneyUtils.formatPaisa(expensePaisa),
              icon: Icons.trending_down_rounded,
              color: const Color(0xFFE63946),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EEEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7470),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              maxLines: 1,
              style: const TextStyle(
                color: AnalyticsScreen._ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPanel extends StatelessWidget {
  final int totalExpensePaisa;
  final List<_CategorySlice> slices;

  const _ChartPanel({required this.totalExpensePaisa, required this.slices});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EEEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Expense Breakdown',
            style: TextStyle(
              color: AnalyticsScreen._ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(176),
                    painter: _DonutChartPainter(slices: slices),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Total Spent',
                        style: TextStyle(
                          color: Color(0xFF7A8580),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 112,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            MoneyUtils.formatPaisa(totalExpensePaisa),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AnalyticsScreen._ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _LegendList(slices: slices, totalExpensePaisa: totalExpensePaisa),
        ],
      ),
    );
  }
}

class _LegendList extends StatelessWidget {
  final List<_CategorySlice> slices;
  final int totalExpensePaisa;

  const _LegendList({required this.slices, required this.totalExpensePaisa});

  @override
  Widget build(BuildContext context) {
    final visibleSlices = slices.take(4).toList();

    if (visibleSlices.isEmpty) {
      return const Center(
        child: Text(
          'No expenses yet',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return Column(
      children: [
        for (final slice in visibleSlices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AnalyticsScreen._ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  slice.percentLabel(totalExpensePaisa),
                  style: const TextStyle(
                    color: Color(0xFF6B7470),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrendPanel extends StatelessWidget {
  final List<_TrendPoint> points;

  const _TrendPanel({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EEEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Last 7 Days',
            style: TextStyle(
              color: AnalyticsScreen._ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 112, child: _TrendBars(points: points)),
        ],
      ),
    );
  }
}

class _TrendBars extends StatelessWidget {
  final List<_TrendPoint> points;

  const _TrendBars({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold(0, (max, point) => math.max(max, point.paisa));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final point in points)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: maxValue == 0
                            ? 0.08
                            : math.max(0.08, point.paisa / maxValue),
                        child: Container(
                          width: 18,
                          decoration: BoxDecoration(
                            color: point.paisa == 0
                                ? const Color(0xFFE8EEEB)
                                : AnalyticsScreen._accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    point.label,
                    style: const TextStyle(
                      color: Color(0xFF7A8580),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryBreakdownRow extends StatelessWidget {
  final _CategorySlice slice;
  final int maxPaisa;

  const _CategoryBreakdownRow({required this.slice, required this.maxPaisa});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EEEB)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                  color: slice.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(slice.icon, color: slice.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slice.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AnalyticsScreen._ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: maxPaisa == 0 ? 0 : slice.paisa / maxPaisa,
                    color: slice.color,
                    backgroundColor: const Color(0xFFE8EEEB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            MoneyUtils.formatPaisa(slice.paisa),
            style: const TextStyle(
              color: AnalyticsScreen._ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<_CategorySlice> slices;

  const _DonutChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.width * 0.12;
    final total = slices.fold(0, (sum, slice) => sum + slice.paisa);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFFE8EEEB);

    canvas.drawArc(rect.deflate(strokeWidth), 0, math.pi * 2, false, basePaint);

    if (total == 0) {
      return;
    }

    var start = -math.pi / 2;
    for (final slice in slices) {
      final rawSweep = (slice.paisa / total) * math.pi * 2;
      final sweep = math.max(0.0, rawSweep - 0.02);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = slice.color;
      canvas.drawArc(rect.deflate(strokeWidth), start, sweep, false, paint);
      start += rawSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _CategorySlice {
  final String label;
  final int paisa;
  final Color color;
  final IconData icon;

  const _CategorySlice({
    required this.label,
    required this.paisa,
    required this.color,
    required this.icon,
  });

  double percentOf(int totalPaisa) {
    if (totalPaisa == 0) {
      return 0;
    }
    return paisa / totalPaisa * 100;
  }

  String percentLabel(int totalPaisa) {
    final percent = percentOf(totalPaisa);
    if (percent > 0 && percent < 1) {
      return '<1%';
    }
    return '${percent.toStringAsFixed(0)}%';
  }
}

class _TrendPoint {
  final String label;
  final int paisa;

  const _TrendPoint({required this.label, required this.paisa});
}

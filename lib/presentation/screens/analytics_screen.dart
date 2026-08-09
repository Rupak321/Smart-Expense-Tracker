import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/components/app_widgets.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_utils.dart';
import '../../../services/financial_report_service.dart';
import '../../../services/user_data_service.dart';
import 'all_expenses_screen.dart';
import 'main_navigation.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  static void _showAnalyticsReportOptions(BuildContext context) {
    final theme = Theme.of(context);
    final stableContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.picture_as_pdf, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Generate Financial Report',
                style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose report options:',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _ReportOptionButton(
              icon: Icons.date_range,
              title: 'Last 7 Days',
              subtitle: 'Weekly spending analysis',
              onTap: () => _generateAnalyticsReport(stableContext, forMonths: 0),
            ),
            _ReportOptionButton(
              icon: Icons.calendar_today,
              title: 'Month to Date',
              subtitle: 'Current month summary',
              onTap: () => _generateAnalyticsReport(stableContext, forMonths: 1),
            ),
            _ReportOptionButton(
              icon: Icons.timeline,
              title: 'Last 3 Months',
              subtitle: 'Quarterly financial review',
              onTap: () => _generateAnalyticsReport(stableContext, forMonths: 3),
            ),
            _ReportOptionButton(
              icon: Icons.library_books,
              title: 'All Time',
              subtitle: 'Comprehensive financial report',
              onTap: () => _generateAnalyticsReport(stableContext, forMonths: null),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _generateAnalyticsReport(BuildContext context, {int? forMonths}) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final scaffold = ScaffoldMessenger.of(context);

    if (navigator.canPop()) {
      navigator.pop();
    }

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text('Generating report...'),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final reportContent = await FinancialReportService.generateProfessionalReport(
        forMonths: forMonths,
        reportType: 'financial',
      );

      if (!context.mounted) return;
      if (navigator.canPop()) {
        navigator.pop();
      }
      _showAnalyticsReportResult(context, reportContent, forMonths);
    } catch (e) {
      if (!context.mounted) return;
      if (navigator.canPop()) {
        navigator.pop();
      }
      scaffold.showSnackBar(
        SnackBar(
          content: Text('Failed to generate report: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  static void _showAnalyticsReportResult(BuildContext context, String reportContent, int? forMonths) {
    final theme = Theme.of(context);
    final scaffold = ScaffoldMessenger.of(context);

    void openInAppPreview() {
      scaffold.hideCurrentSnackBar();
      final previewText = FinancialReportService.sanitizeReportForDisplay(reportContent, maxLength: 2200);
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.visibility_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  forMonths == 0 ? 'Weekly Report Preview' :
                  forMonths == 1 ? 'Monthly Report Preview' :
                  forMonths == 3 ? 'Quarterly Report Preview' :
                  'Comprehensive Report Preview',
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 420,
            child: MarkdownBody(
              data: previewText,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 14, height: 1.5, color: theme.colorScheme.onSurface),
                h1: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                h2: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                listBullet: TextStyle(color: theme.colorScheme.primary),
                strong: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await FinancialReportService.shareReport(forMonths: forMonths);
              },
              icon: const Icon(Icons.share),
              label: const Text('Share Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      );
    }

    Future<void> downloadPdf() async {
      scaffold.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppTokens.gapMd),
              Expanded(child: Text('Generating PDF...')),
            ],
          ),
          duration: Duration(seconds: 60),
        ),
      );

      try {
        final pdfFile = await FinancialReportService.generatePDFReport(
          forMonths: forMonths,
        );
        if (!context.mounted) return;

        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: theme.colorScheme.inversePrimary,
                ),
                const SizedBox(width: AppTokens.gapMd),
                Expanded(
                  child: Text(
                    'Saved ${pdfFile.path.split(Platform.pathSeparator).last}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () async {
                scaffold.hideCurrentSnackBar();
                await FinancialReportService.shareReport(forMonths: forMonths);
              },
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.picture_as_pdf, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                forMonths == 0 ? 'Weekly Report' :
                forMonths == 1 ? 'Monthly Report' :
                forMonths == 3 ? 'Quarterly Report' :
                'Comprehensive Financial Report',
                style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: openInAppPreview,
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('View in App'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: downloadPdf,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download PDF'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.appCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.appBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AnalyticsReportPreview(
                      title: 'Report Content',
                      icon: Icons.description,
                      subtitle: 'Preview the full generated report',
                      onTap: openInAppPreview,
                    ),
                    const SizedBox(height: 12),
                    _AnalyticsReportPreview(
                      title: 'Download PDF',
                      icon: Icons.picture_as_pdf,
                      subtitle: 'Save a professional PDF copy',
                      onTap: () => downloadPdf(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = NavShellInsets.of(context);

    return StreamBuilder<List<ExpenseModel>>(
      stream: UserDataService.transactionsStream(),
      builder: (context, snapshot) {
        final transactions = _sortedTransactions(
          snapshot.data ?? const <ExpenseModel>[],
        );
        final expenses = transactions
            .where((transaction) => transaction.isExpense)
            .toList();
        final incomePaisa = _totalPaisa(
          transactions.where((transaction) => !transaction.isExpense),
        );
        final expensePaisa = _totalPaisa(expenses);
        final categorySlices = _buildCategorySlices(expenses);
        final sevenDayTrend = _buildRecentTrend(expenses, dayCount: 7);
        final thirtyDayTrend = _buildRecentTrend(expenses, dayCount: 30);

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Analytics',
                subtitle: 'Where your money goes',
                icon: Icons.insights_rounded,
              ),
            ),
            SliverToBoxAdapter(
              child: _SummaryBand(
                incomePaisa: incomePaisa,
                expensePaisa: expensePaisa,
                onSpentTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AllExpensesScreen(),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _ChartPanel(
                totalExpensePaisa: expensePaisa,
                slices: categorySlices,
              ),
            ),
            SliverToBoxAdapter(
              child: _TrendPanel(
                sevenDayPoints: sevenDayTrend,
                thirtyDayPoints: thirtyDayTrend,
              ),
            ),
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Category Details'),
            ),
            if (categorySlices.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyStateCard(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'Nothing to break down yet',
                  message: 'Add a few expenses to see category analytics here.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.pageGutter,
                ),
                sliver: SliverList.separated(
                  itemCount: categorySlices.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppTokens.gapSm),
                  itemBuilder: (context, index) {
                    return _CategoryBreakdownRow(
                      slice: categorySlices[index],
                      maxPaisa: categorySlices.first.paisa,
                      totalPaisa: expensePaisa,
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTokens.pageGutter,
                  AppTokens.gapXl,
                  AppTokens.pageGutter,
                  bottomInset,
                ),
                child: FilledButton.icon(
                  onPressed: () => _showAnalyticsReportOptions(context),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Generate Report'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<ExpenseModel> _sortedTransactions(List<ExpenseModel> transactions) {
    final sorted = List<ExpenseModel>.from(transactions);
    sorted.sort((first, second) => second.date.compareTo(first.date));
    return sorted;
  }

  int _totalPaisa(Iterable<ExpenseModel> transactions) {
    return transactions.fold(
      0,
      (total, transaction) => total + transaction.amountPaisa,
    );
  }

  List<_CategorySlice> _buildCategorySlices(List<ExpenseModel> expenses) {
    final totals = <String, int>{};
    for (final expense in expenses) {
      totals.update(
        expense.category,
        (value) => value + expense.amountPaisa,
        ifAbsent: () => expense.amountPaisa,
      );
    }

    Color getColorForCategory(String category) {
      final lower = category.toLowerCase();
      if (lower.contains('food') || lower.contains('restaurant')) return const Color(0xFFE76F51);
      if (lower.contains('travel') || lower.contains('transport')) return const Color(0xFF457B9D);
      if (lower.contains('shopping') || lower.contains('clothes')) return const Color(0xFFE9C46A);
      if (lower.contains('bill') || lower.contains('utilit')) return const Color(0xFF2A9D8F);
      if (lower.contains('health') || lower.contains('medic')) return const Color(0xFFE63946);
      if (lower.contains('entertain') || lower.contains('movie')) return const Color(0xFF9B5DE5);
      
      // Deterministic fallback color based on string hash
      final colors = [
        const Color(0xFFF4A261),
        const Color(0xFF264653),
        const Color(0xFF00B4D8),
        const Color(0xFF8338EC),
        const Color(0xFFFF006E),
        const Color(0xFF38B000),
      ];
      return colors[category.hashCode.abs() % colors.length];
    }

    final slices = totals.entries.map((entry) {
      return _CategorySlice(
        label: entry.key,
        paisa: entry.value,
        color: getColorForCategory(entry.key),
        icon: _iconForCategory(entry.key),
      );
    }).toList();

    slices.sort((first, second) => second.paisa.compareTo(first.paisa));
    return slices;
  }

  List<_TrendPoint> _buildRecentTrend(
    List<ExpenseModel> expenses, {
    required int dayCount,
  }) {
    final today = DateTime.now();
    final days = List.generate(dayCount, (index) {
      final day = today.subtract(Duration(days: dayCount - 1 - index));
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
      return _TrendPoint(
        label: dayCount == 7 ? _shortDay(day) : day.day.toString(),
        paisa: totals[day] ?? 0,
      );
    }).toList();
  }

  String _shortDay(DateTime date) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.weekday - 1];
  }

  IconData _iconForCategory(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('food') || lower.contains('restaurant') || lower.contains('grocer')) return Icons.restaurant_rounded;
    if (lower.contains('shopping') || lower.contains('clothes') || lower.contains('electronics')) return Icons.shopping_bag_rounded;
    if (lower.contains('travel') || lower.contains('transport')) return Icons.flight_takeoff_rounded;
    if (lower.contains('bill') || lower.contains('utilit')) return Icons.receipt_long_rounded;
    if (lower.contains('salary') || lower.contains('income') || lower.contains('freelance') || lower.contains('business')) return Icons.attach_money_rounded;
    if (lower.contains('invest')) return Icons.trending_up_rounded;
    if (lower.contains('gift')) return Icons.card_giftcard_rounded;
    if (lower.contains('entertain') || lower.contains('movie')) return Icons.movie_rounded;
    if (lower.contains('health') || lower.contains('medic')) return Icons.medical_services_rounded;
    return Icons.category_rounded;
  }
}

class _SummaryBand extends StatelessWidget {
  final int incomePaisa;
  final int expensePaisa;
  final VoidCallback onSpentTap;

  const _SummaryBand({
    required this.incomePaisa,
    required this.expensePaisa,
    required this.onSpentTap,
  });

  @override
  Widget build(BuildContext context) {
    final balancePaisa = incomePaisa - expensePaisa;

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.pageGutter,
        vertical: AppTokens.gapSm,
      ),
      // Stretch keeps both cards the same height even though each sizes to its
      // own content.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Balance',
                amount: MoneyUtils.formatPaisa(balancePaisa),
                icon: Icons.account_balance_wallet_rounded,
                color: balancePaisa < 0
                    ? colorScheme.appExpense
                    : colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppTokens.gapMd),
            Expanded(
              child: _MetricCard(
                label: 'Spent',
                amount: MoneyUtils.formatPaisa(expensePaisa),
                icon: Icons.trending_down_rounded,
                color: colorScheme.appExpense,
                onTap: onSpentTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.appCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // No fixed height: the card grows with the text scale instead of
          // clipping the amount.
          padding: const EdgeInsets.all(AppTokens.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    )
                  else
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTokens.gapXs),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    maxLines: 1,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartPanel extends StatefulWidget {
  final int totalExpensePaisa;
  final List<_CategorySlice> slices;

  const _ChartPanel({required this.totalExpensePaisa, required this.slices});

  @override
  State<_ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<_ChartPanel> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isSharing = false;

  Future<void> _shareChart() async {
    if (_isSharing) return;

    setState(() {
      _isSharing = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final pngBytes = byteData.buffer.asUint8List();
            final directory = await getTemporaryDirectory();
            final filePath = '${directory.path}/expense_breakdown_${DateTime.now().millisecondsSinceEpoch}.png';
            final file = File(filePath);
            await file.writeAsBytes(pngBytes);

            if (!mounted) return;
            final box = context.findRenderObject() as RenderBox?;
            final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
            await Share.shareXFiles(
              [XFile(file.path)],
              text: 'My Expense Breakdown from Smart Expense!',
              sharePositionOrigin: origin,
            );
          }
        }
      } catch (e) {
        debugPrint('Error sharing chart: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to share chart: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSharing = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppTokens.pageGutter,
          AppTokens.gapSm,
          AppTokens.pageGutter,
          0,
        ),
        padding: const EdgeInsets.all(AppTokens.gapLg),
        decoration: BoxDecoration(
          color: colorScheme.appCard,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          border: Border.all(color: colorScheme.appBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Expense Breakdown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.slices.isNotEmpty && !_isSharing)
                  IconButton(
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    tooltip: 'Share breakdown chart',
                    onPressed: _shareChart,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.gapMd),
            Center(
              child: SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(176),
                      painter: _DonutChartPainter(slices: widget.slices, backgroundColor: colorScheme.appCardMuted),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Total Spent',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
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
                              MoneyUtils.formatPaisa(widget.totalExpensePaisa),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: colorScheme.onSurface,
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
            _LegendList(slices: widget.slices, totalExpensePaisa: widget.totalExpensePaisa),
          ],
        ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final visibleSlices = slices.take(4).toList();
    final hiddenCount = slices.length - visibleSlices.length;

    if (visibleSlices.isEmpty) {
      return Center(
        child: Text(
          'No expenses yet',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
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
                const SizedBox(width: AppTokens.gapSm),
                Expanded(
                  child: Text(
                    slice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.gapSm),
                Text(
                  slice.percentLabel(totalExpensePaisa),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        // Previously the extra categories just vanished with no hint.
        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.gapSm),
            child: Text(
              '+$hiddenCount more in Category Details',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _TrendPanel extends StatefulWidget {
  final List<_TrendPoint> sevenDayPoints;
  final List<_TrendPoint> thirtyDayPoints;

  const _TrendPanel({
    required this.sevenDayPoints,
    required this.thirtyDayPoints,
  });

  @override
  State<_TrendPanel> createState() => _TrendPanelState();
}

class _TrendPanelState extends State<_TrendPanel> {
  var _selectedRange = _TrendRange.sevenDays;
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isSharing = false;

  List<_TrendPoint> get _points {
    return _selectedRange == _TrendRange.sevenDays
        ? widget.sevenDayPoints
        : widget.thirtyDayPoints;
  }

  int get _dayCount {
    return _selectedRange == _TrendRange.sevenDays ? 7 : 30;
  }

  Future<void> _shareChart() async {
    if (_isSharing) return;

    setState(() {
      _isSharing = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final pngBytes = byteData.buffer.asUint8List();
            final directory = await getTemporaryDirectory();
            final filePath = '${directory.path}/spending_trend_${_dayCount}d_${DateTime.now().millisecondsSinceEpoch}.png';
            final file = File(filePath);
            await file.writeAsBytes(pngBytes);

            if (!mounted) return;
            final box = context.findRenderObject() as RenderBox?;
            final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
            await Share.shareXFiles(
              [XFile(file.path)],
              text: 'My $_dayCount Days Spending Trend from Smart Expense!',
              sharePositionOrigin: origin,
            );
          }
        }
      } catch (e) {
        debugPrint('Error sharing chart: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to share chart: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSharing = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final points = _points;
    final totalPaisa = points.fold(0, (sum, point) => sum + point.paisa);
    final changePaisa = points.isEmpty
        ? 0
        : points.last.paisa - points.first.paisa;
    final changePercent = points.isEmpty || points.first.paisa == 0
        ? 0.0
        : changePaisa / points.first.paisa * 100;
    final isIncrease = changePaisa >= 0;

    final trendColor = isIncrease
        ? colorScheme.appExpense
        : colorScheme.appIncome;

    return RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppTokens.pageGutter,
          AppTokens.gapMd,
          AppTokens.pageGutter,
          0,
        ),
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gapLg,
          AppTokens.gapLg,
          AppTokens.gapLg,
          AppTokens.gapLg,
        ),
        decoration: BoxDecoration(
          color: colorScheme.appCard,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          border: Border.all(color: colorScheme.appBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Last $_dayCount Days',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Expense trend',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.gapSm),
                // Right column is width-capped; without this the total pushed
                // the whole header off-screen for six-figure amounts.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          MoneyUtils.formatPaisa(totalPaisa),
                          maxLines: 1,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.gapSm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: trendColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusPill,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isIncrease
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              color: trendColor,
                              size: 15,
                            ),
                            const SizedBox(width: AppTokens.gapXs),
                            Flexible(
                              child: Text(
                                '${isIncrease ? '+' : ''}'
                                '${changePercent.toStringAsFixed(1)}%',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: trendColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (points.isNotEmpty && !_isSharing)
                  IconButton(
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    tooltip: 'Share trend chart',
                    onPressed: _shareChart,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.gapLg),
            _TrendRangeSwitch(
              selectedRange: _selectedRange,
              onChanged: (range) {
                setState(() {
                  _selectedRange = range;
                });
              },
            ),
            const SizedBox(height: 22),
            TweenAnimationBuilder<double>(
              key: ValueKey(
                '$_dayCount-${points.map((point) => point.paisa).join(',')}',
              ),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutQuart,
              builder: (context, progress, child) {
                return SizedBox(
                  height: points.length > 7 ? 210 : 240,
                  child: _TrendLineChart(points: points, progress: progress),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _TrendRange { sevenDays, thirtyDays }

class _TrendRangeSwitch extends StatelessWidget {
  final _TrendRange selectedRange;
  final ValueChanged<_TrendRange> onChanged;

  const _TrendRangeSwitch({
    required this.selectedRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _TrendRangeOption(
            label: '7 Days',
            isSelected: selectedRange == _TrendRange.sevenDays,
            onTap: () => onChanged(_TrendRange.sevenDays),
          ),
          _TrendRangeOption(
            label: '30 Days',
            isSelected: selectedRange == _TrendRange.thirtyDays,
            onTap: () => onChanged(_TrendRange.thirtyDays),
          ),
        ],
      ),
    );
  }
}

class _TrendRangeOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TrendRangeOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendLineChart extends StatelessWidget {
  final List<_TrendPoint> points;
  final double progress;

  const _TrendLineChart({required this.points, required this.progress});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxValue = points.fold(0, (max, point) => math.max(max, point.paisa));
    final minValue = points.fold(
      maxValue,
      (min, point) => math.min(min, point.paisa),
    );
    final hasValues = maxValue > 0;
    final labels = _axisLabels(minValue, maxValue);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final label in labels)
                      // Shrink-to-fit keeps six-figure ticks inside the fixed
                      // gutter at any text scale.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hasValues
                              ? MoneyUtils.formatCompactPaisa(label)
                              : 'Rs. 0',
                          maxLines: 1,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomPaint(
                  painter: _TrendLinePainter(
                    points: points,
                    progress: progress,
                    lineColor: const Color(0xFFF6B900),
                    gridColor: colorScheme.appBorder,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 74),
          child: points.length > 7
              ? _SparseTrendLabels(
                  labels: _sparseBottomLabels(),
                  textColor: colorScheme.onSurfaceVariant,
                )
              : Row(
                  children: [
                    for (final point in points)
                      Expanded(
                        child: Text(
                          point.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (points.length <= 7) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 74),
            child: Row(
              children: [
                for (var index = 0; index < points.length; index++)
                  Expanded(
                    child: _TrendChangeLabel(
                      value: index == 0
                          ? points[index].paisa
                          : points[index].paisa - points[index - 1].paisa,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<int> _axisLabels(int minValue, int maxValue) {
    if (maxValue == 0) {
      return const [0, 0, 0, 0, 0];
    }

    final paddedMax = (maxValue * 1.14).ceil();
    final paddedMin = math.max(0, (minValue * 0.82).floor());
    return List.generate(5, (index) {
      final value = paddedMax - ((paddedMax - paddedMin) * index / 4);
      return value.round();
    });
  }

  List<String> _sparseBottomLabels() {
    if (points.isEmpty) {
      return [];
    }

    final lastIndex = points.length - 1;
    final indexes = <int>{0, 5, 10, 15, 20, 25, lastIndex}
        .where((index) => index >= 0 && index <= lastIndex)
        .toList();
    return indexes.map((index) => points[index].label).toList();
  }

}

class _SparseTrendLabels extends StatelessWidget {
  final List<String> labels;
  final Color textColor;

  const _SparseTrendLabels({
    required this.labels,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final label in labels)
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _TrendChangeLabel extends StatelessWidget {
  final int value;

  const _TrendChangeLabel({required this.value});

  @override
  Widget build(BuildContext context) {
    final isIncrease = value >= 0;
    // Spending more day-over-day is the bad direction, so it reads red here
    // exactly like the panel header above.
    final color = isIncrease
        ? Theme.of(context).colorScheme.appExpense
        : Theme.of(context).colorScheme.appIncome;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isIncrease
              ? Icons.arrow_drop_up_rounded
              : Icons.arrow_drop_down_rounded,
          color: color,
          size: 18,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${isIncrease ? '+' : '-'}'
            '${MoneyUtils.formatCompactPaisa(value.abs())}',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  final List<_TrendPoint> points;
  final double progress;
  final Color lineColor;
  final Color gridColor;

  const _TrendLinePainter({
    required this.points,
    required this.progress,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const chartPadding = 16.0;
    final chartLeft = chartPadding;
    final chartRight = size.width - chartPadding;
    final chartWidth = math.max(1.0, chartRight - chartLeft);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var index = 0; index < 5; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);
    }

    if (points.isEmpty) {
      return;
    }

    final maxValue = points.fold(0, (max, point) => math.max(max, point.paisa));
    final minValue = points.fold(
      maxValue,
      (min, point) => math.min(min, point.paisa),
    );
    final paddedMax = maxValue == 0 ? 1.0 : maxValue * 1.14;
    final paddedMin = maxValue == 0 ? 0.0 : math.max(0.0, minValue * 0.82);
    final range = math.max(1.0, paddedMax - paddedMin);
    final gap = points.length == 1 ? 0.0 : chartWidth / (points.length - 1);

    final chartPoints = <Offset>[
      for (var index = 0; index < points.length; index++)
        Offset(
          points.length == 1 ? size.width / 2 : chartLeft + gap * index,
          size.height -
              ((points[index].paisa - paddedMin) / range * size.height),
        ),
    ];

    final curvePath = _smoothPath(chartPoints);
    final fillPath = Path.from(curvePath)
      ..lineTo(chartRight, size.height)
      ..lineTo(chartLeft, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.26),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
      chartLeft - chartPadding,
      -20,
      chartWidth * clampedProgress + chartPadding,
      size.height + 40,
    ));
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(curvePath, linePaint);
    canvas.restore();

    final marker = _markerAtProgress(chartPoints, clampedProgress);
    final markerPaint = Paint()..color = lineColor;
    final haloPaint = Paint()..color = lineColor.withValues(alpha: 0.18);
    canvas.drawCircle(marker, 14, haloPaint);
    canvas.drawCircle(marker, 6, markerPaint);
    canvas.drawCircle(marker, 3, Paint()..color = Colors.white);
  }

  Path _smoothPath(List<Offset> offsets) {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    if (offsets.length == 1) {
      return path;
    }

    for (var index = 0; index < offsets.length - 1; index++) {
      final current = offsets[index];
      final next = offsets[index + 1];
      final controlX = (current.dx + next.dx) / 2;
      path.cubicTo(
        controlX,
        current.dy,
        controlX,
        next.dy,
        next.dx,
        next.dy,
      );
    }

    return path;
  }

  Offset _markerAtProgress(List<Offset> offsets, double progress) {
    if (offsets.length == 1) {
      return offsets.first;
    }

    final position = (offsets.length - 1) * progress;
    final lowerIndex = position.floor().clamp(0, offsets.length - 1);
    final upperIndex = math.min(lowerIndex + 1, offsets.length - 1);
    final localProgress = position - lowerIndex;
    return Offset.lerp(
      offsets[lowerIndex],
      offsets[upperIndex],
      localProgress,
    )!;
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.progress != progress ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _CategoryBreakdownRow extends StatelessWidget {
  final _CategorySlice slice;
  final int maxPaisa;
  final int totalPaisa;

  const _CategoryBreakdownRow({
    required this.slice,
    required this.maxPaisa,
    required this.totalPaisa,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      // Height comes from the content, so a large text scale grows the row
      // instead of overflowing it.
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.gapLg,
        vertical: AppTokens.gapMd,
      ),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: colorScheme.appBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: slice.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(slice.icon, color: slice.color, size: 22),
          ),
          const SizedBox(width: AppTokens.gapMd),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        slice.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // Was a hardcoded near-black that vanished in dark
                          // mode.
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.gapSm),
                    // Capped and shrink-to-fit so long amounts never push the
                    // row past its width.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 128),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          MoneyUtils.formatPaisa(slice.paisa),
                          maxLines: 1,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.gapSm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: maxPaisa == 0 ? 0 : slice.paisa / maxPaisa,
                    color: slice.color,
                    backgroundColor: colorScheme.appCardMuted,
                  ),
                ),
                const SizedBox(height: AppTokens.gapXs + 2),
                Text(
                  '${slice.percentLabel(totalPaisa)} of total spending',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<_CategorySlice> slices;
  final Color backgroundColor;

  const _DonutChartPainter({required this.slices, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.width * 0.12;
    final total = slices.fold(0, (sum, slice) => sum + slice.paisa);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = backgroundColor;

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

class _AnalyticsReportPreview extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  final VoidCallback onTap;

  const _AnalyticsReportPreview({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.appCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.appBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportOptionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReportOptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.appCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.appBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

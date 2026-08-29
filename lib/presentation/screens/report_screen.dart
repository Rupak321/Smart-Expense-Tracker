import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/components/app_widgets.dart';
import '../../core/models/expense_model.dart';
import '../../core/models/financial_report.dart';
import '../../core/secrets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_utils.dart';
import '../../services/financial_report_service.dart';

/// Full-screen financial report.
///
/// Replaces a stack of AlertDialogs that showed the report as a single
/// markdown-stripped paragraph truncated at 2,200 characters.
class ReportScreen extends StatefulWidget {
  final ReportPeriod period;

  const ReportScreen({super.key, required this.period});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

enum _NarrativeState { loading, ready, failed, unavailable }

class _ReportScreenState extends State<ReportScreen> {
  FinancialReport? _report;
  _NarrativeState _narrativeState = _NarrativeState.loading;
  String? _narrativeError;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The figures are local arithmetic, so they land immediately.
    final report = await FinancialReportService.buildReport(
      period: widget.period,
      withNarrative: false,
    );
    if (!mounted) return;

    setState(() {
      _report = report;
      _narrativeState = Secrets.hasApiKey && report.hasData
          ? _NarrativeState.loading
          : _NarrativeState.unavailable;
    });

    if (!Secrets.hasApiKey || !report.hasData) return;

    try {
      final narrative = await FinancialReportService.requestNarrative(report);
      if (!mounted) return;
      setState(() {
        _report = report.copyWith(narrative: narrative);
        _narrativeState = _NarrativeState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _narrativeState = _NarrativeState.failed;
        _narrativeError = _friendlyError(error);
      });
    }
  }

  /// Raw Dart exception text ("TimeoutException after 0:00:45.000000: Future
  /// not completed") means nothing to the person reading the report.
  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('TimeoutException')) {
      return 'The AI service took too long to write it. Everything above is '
          'already complete — tap below to try the analysis again.';
    }
    // package:http wraps socket failures in ClientException, so this is what a
    // dropped connection actually looks like rather than a SocketException.
    if (text.contains('Failed host lookup') ||
        text.contains('SocketException') ||
        text.contains('SocketFailed') ||
        text.contains('No address associated')) {
      return 'No internet connection, so the analysis could not be written. '
          'Everything above is calculated from your own records and is '
          'already complete.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  Future<void> _retryNarrative() async {
    final report = _report;
    if (report == null) return;
    setState(() {
      _narrativeState = _NarrativeState.loading;
      _narrativeError = null;
    });
    try {
      final narrative = await FinancialReportService.requestNarrative(report);
      if (!mounted) return;
      setState(() {
        _report = report.copyWith(narrative: narrative);
        _narrativeState = _NarrativeState.ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _narrativeState = _NarrativeState.failed;
        _narrativeError = _friendlyError(error);
      });
    }
  }

  Future<void> _export({required bool share}) async {
    final report = _report;
    if (report == null || _isExporting) return;

    // Exporting mid-fetch produces a PDF with no Analysis section. Silently
    // handing over an incomplete document is worse than saying so.
    final missingAnalysis = _narrativeState == _NarrativeState.loading;

    setState(() => _isExporting = true);
    try {
      if (share) {
        await FinancialReportService.sharePdf(report);
        if (mounted && missingAnalysis) {
          _snack('Shared. The written analysis was still loading, so it is '
              'not in this PDF.');
        }
      } else {
        final file = await FinancialReportService.generatePdf(report);
        if (!mounted) return;
        _snack(
          missingAnalysis
              ? 'Saved without the analysis — it was still loading.'
              : 'Saved ${file.path.split(Platform.pathSeparator).last}',
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => FinancialReportService.sharePdf(report),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      _snack('Could not create the PDF: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _snack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          IconButton(
            tooltip: 'Share as PDF',
            onPressed: report == null || _isExporting
                ? null
                : () => _export(share: true),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      bottomNavigationBar: report == null
          ? null
          : _ExportBar(
              isExporting: _isExporting,
              onSave: () => _export(share: false),
              onShare: () => _export(share: true),
            ),
      body: report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                AppTokens.pageGutter,
                AppTokens.gapLg,
                AppTokens.pageGutter,
                AppTokens.gapXl + bottomInset,
              ),
              children: [
                _ReportHeader(report: report),
                if (!report.hasData) ...[
                  const SizedBox(height: AppTokens.gapLg),
                  EmptyStateCard(
                    icon: Icons.insert_chart_outlined_rounded,
                    title: 'Nothing in this period',
                    message:
                        'There are no transactions between '
                        '${report.rangeLabel}. Try a longer period.',
                    margin: EdgeInsets.zero,
                  ),
                ] else ...[
                  const SizedBox(height: AppTokens.gapLg),
                  _KpiGrid(report: report),
                  if (report.expenseChangeRatio != null) ...[
                    const SizedBox(height: AppTokens.gapMd),
                    _ComparisonBanner(report: report),
                  ],
                  const SizedBox(height: AppTokens.gapXl),
                  _Section(
                    title: 'Where the money went',
                    child: _CategoryList(report: report),
                  ),
                  if (report.months.length > 1)
                    _Section(
                      title: 'Month by month',
                      child: _MonthList(report: report),
                    ),
                  if (report.topExpenses.isNotEmpty)
                    _Section(
                      title: 'Largest expenses',
                      child: _TransactionList(
                        transactions: report.topExpenses,
                        isExpense: true,
                      ),
                    ),
                  if (report.topIncome.isNotEmpty)
                    _Section(
                      title: 'Largest income',
                      child: _TransactionList(
                        transactions: report.topIncome,
                        isExpense: false,
                      ),
                    ),
                  if (report.observations.isNotEmpty)
                    _Section(
                      title: 'Observations',
                      child: _Observations(report: report),
                    ),
                  _Section(
                    title: 'Analysis',
                    child: _NarrativeBlock(
                      state: _narrativeState,
                      narrative: report.narrative,
                      error: _narrativeError,
                      onRetry: _retryNarrative,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ExportBar extends StatelessWidget {
  final bool isExporting;
  final VoidCallback onSave;
  final VoidCallback onShare;

  const _ExportBar({
    required this.isExporting,
    required this.onSave,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.pageGutter,
        AppTokens.gapMd,
        AppTokens.pageGutter,
        AppTokens.gapMd,
      ),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        border: Border(top: BorderSide(color: colorScheme.appBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isExporting ? null : onSave,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Save PDF'),
              ),
            ),
            const SizedBox(width: AppTokens.gapMd),
            Expanded(
              child: FilledButton.icon(
                onPressed: isExporting ? null : onShare,
                icon: isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(isExporting ? 'Working...' : 'Share PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  final FinancialReport report;

  const _ReportHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapXl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colorScheme.appHeroGradient,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FINANCIAL REPORT',
            style: TextStyle(
              color: colorScheme.appOnHero.withValues(alpha: 0.8),
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppTokens.gapSm),
          Text(
            report.period.label,
            style: TextStyle(
              color: colorScheme.appOnHero,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppTokens.gapXs),
          Text(
            report.rangeLabel,
            style: TextStyle(
              color: colorScheme.appOnHero.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.gapMd),
          Text(
            '${report.transactionCount} transaction'
            '${report.transactionCount == 1 ? '' : 's'} · '
            '${report.dayCount} day${report.dayCount == 1 ? '' : 's'}',
            style: TextStyle(
              color: colorScheme.appOnHero.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final FinancialReport report;

  const _KpiGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rate = report.savingsRate;

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KpiCard(
                label: 'Income',
                value: MoneyUtils.formatPaisa(report.incomePaisa),
                caption: '${report.incomeCount} entries',
                color: colorScheme.appIncome,
              ),
              const SizedBox(width: AppTokens.gapMd),
              _KpiCard(
                label: 'Spent',
                value: MoneyUtils.formatPaisa(report.expensePaisa),
                caption: '${report.expenseCount} entries',
                color: colorScheme.appExpense,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gapMd),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KpiCard(
                label: 'Net',
                value: MoneyUtils.formatPaisa(report.netPaisa),
                caption: report.netPaisa < 0 ? 'Overspent' : 'Kept',
                color: report.netPaisa < 0
                    ? colorScheme.appExpense
                    : colorScheme.primary,
              ),
              const SizedBox(width: AppTokens.gapMd),
              _KpiCard(
                label: 'Savings rate',
                value: rate == null ? '—' : '${(rate * 100).round()}%',
                caption: rate == null ? 'No income' : 'of income kept',
                color: rate == null
                    ? colorScheme.onSurfaceVariant
                    : rate < 0
                    ? colorScheme.appExpense
                    : colorScheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gapMd),
        _AverageStrip(report: report),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppTokens.gapLg),
        decoration: BoxDecoration(
          color: colorScheme.appCard,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: colorScheme.appBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppTokens.gapSm),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
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
    );
  }
}

class _AverageStrip extends StatelessWidget {
  final FinancialReport report;

  const _AverageStrip({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.gapLg,
        vertical: AppTokens.gapMd,
      ),
      decoration: BoxDecoration(
        color: colorScheme.appCardMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Per day',
              value: MoneyUtils.formatPaisa(report.averageDailyExpensePaisa),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: colorScheme.appBorder,
          ),
          Expanded(
            child: _MiniStat(
              label: 'Per expense',
              value: MoneyUtils.formatPaisa(
                report.averageExpensePerTransactionPaisa,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComparisonBanner extends StatelessWidget {
  final FinancialReport report;

  const _ComparisonBanner({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final change = report.expenseChangeRatio!;
    final up = change >= 0;
    final accent = up ? colorScheme.appExpense : colorScheme.appIncome;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapMd),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: AppTokens.gapMd),
          Expanded(
            child: Text(
              'Spending is ${up ? 'up' : 'down'} '
              '${(change.abs() * 100).round()}% versus the previous '
              '${report.period.label.toLowerCase()}',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.gapMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.gapSm),
              Container(width: 32, height: 3, color: colorScheme.primary),
            ],
          ),
        ),
        child,
        const SizedBox(height: AppTokens.gapXl),
      ],
    );
  }
}

class _CategoryList extends StatelessWidget {
  final FinancialReport report;

  const _CategoryList({required this.report});

  static const _palette = AppColorRoles.chartPalette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (report.categories.isEmpty) {
      return Text(
        'No spending recorded in this period.',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      );
    }

    final largest = report.categories.first.paisa;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapLg),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: colorScheme.appBorder),
      ),
      child: Column(
        children: [
          for (var index = 0; index < report.categories.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == report.categories.length - 1
                    ? 0
                    : AppTokens.gapLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _palette[index % _palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppTokens.gapSm),
                      Expanded(
                        child: Text(
                          report.categories[index].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTokens.gapSm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            MoneyUtils.formatPaisa(
                              report.categories[index].paisa,
                            ),
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
                      value: largest == 0
                          ? 0
                          : report.categories[index].paisa / largest,
                      color: _palette[index % _palette.length],
                      backgroundColor: colorScheme.appCardMuted,
                    ),
                  ),
                  const SizedBox(height: AppTokens.gapXs + 2),
                  Text(
                    '${(report.categories[index].share * 100).round()}% of '
                    'spending · ${report.categories[index].transactionCount} '
                    'transaction'
                    '${report.categories[index].transactionCount == 1 ? '' : 's'}',
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

class _MonthList extends StatelessWidget {
  final FinancialReport report;

  const _MonthList({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < report.months.length; index++)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.gapLg,
                vertical: AppTokens.gapMd,
              ),
              decoration: BoxDecoration(
                border: index == 0
                    ? null
                    : Border(
                        top: BorderSide(color: colorScheme.appBorder),
                      ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      report.months[index].shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: _MonthFigure(
                      label: 'in',
                      paisa: report.months[index].incomePaisa,
                      color: colorScheme.appIncome,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: _MonthFigure(
                      label: 'out',
                      paisa: report.months[index].expensePaisa,
                      color: colorScheme.appExpense,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: _MonthFigure(
                      label: 'net',
                      paisa: report.months[index].netPaisa,
                      color: report.months[index].netPaisa < 0
                          ? colorScheme.appExpense
                          : colorScheme.onSurface,
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

class _MonthFigure extends StatelessWidget {
  final String label;
  final int paisa;
  final Color color;

  const _MonthFigure({
    required this.label,
    required this.paisa,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            MoneyUtils.formatCompactPaisa(paisa),
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _TransactionList extends StatelessWidget {
  final List<ExpenseModel> transactions;
  final bool isExpense;

  const _TransactionList({
    required this.transactions,
    required this.isExpense,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isExpense ? colorScheme.appExpense : colorScheme.appIncome;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < transactions.length; index++)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.gapLg,
                vertical: AppTokens.gapMd,
              ),
              decoration: BoxDecoration(
                border: index == 0
                    ? null
                    : Border(top: BorderSide(color: colorScheme.appBorder)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          transactions[index].title.isEmpty
                              ? 'Untitled'
                              : transactions[index].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${transactions[index].category} · '
                          '${_date(transactions[index].date)}',
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
                  const SizedBox(width: AppTokens.gapSm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        MoneyUtils.formatAmount(transactions[index].amount),
                        maxLines: 1,
                        style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _date(DateTime date) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${names[date.month - 1]} ${date.year}';
  }
}

class _Observations extends StatelessWidget {
  final FinancialReport report;

  const _Observations({required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapLg),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: colorScheme.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final observation in report.observations)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.gapMd),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6, right: AppTokens.gapMd),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      observation,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
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

class _NarrativeBlock extends StatelessWidget {
  final _NarrativeState state;
  final String? narrative;
  final String? error;
  final VoidCallback onRetry;

  const _NarrativeBlock({
    required this.state,
    required this.narrative,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapLg),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: colorScheme.appBorder),
      ),
      child: switch (state) {
        _NarrativeState.loading => Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppTokens.gapMd),
            Expanded(
              child: Text(
                'Writing the analysis...',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        _NarrativeState.ready => MarkdownBody(
          data: narrative ?? '',
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 13,
              height: 1.55,
            ),
            strong: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
            h1: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            h2: TextStyle(
              color: colorScheme.primary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
            h3: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            listBullet: TextStyle(color: colorScheme.primary),
          ),
        ),
        _NarrativeState.failed => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The written analysis could not be generated.',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: AppTokens.gapSm),
              Text(
                error!,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: AppTokens.gapMd),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
        _NarrativeState.unavailable => Text(
          'Written analysis needs an AI key. Everything above is calculated '
          'from your own records and is complete without it.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      },
    );
  }
}

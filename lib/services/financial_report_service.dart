import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/expense_model.dart';
import '../core/models/financial_report.dart';
import '../core/secrets.dart';
import '../core/utils/money_utils.dart';
import 'report_pdf_builder.dart';
import 'user_data_service.dart';

class FinancialReportService {
  const FinancialReportService._();

  /// Builds the report for [period].
  ///
  /// Set [withNarrative] to add AI commentary. The report is complete without
  /// it: every number is computed locally, so a missing key or a failed call
  /// costs you the prose, not the report.
  static Future<FinancialReport> buildReport({
    required ReportPeriod period,
    bool withNarrative = true,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final transactions = await UserDataService.getTransactionsOnce();
    final report = compute(
      transactions: transactions,
      period: period,
      now: moment,
    );

    if (!withNarrative || !report.hasData || !Secrets.hasApiKey) {
      return report;
    }

    try {
      final narrative = await _requestNarrative(report);
      return report.copyWith(narrative: narrative);
    } catch (_) {
      // Prose is a bonus; never fail the report over it.
      return report;
    }
  }

  /// Pure computation, so the maths is testable without Firebase or network.
  static FinancialReport compute({
    required List<ExpenseModel> transactions,
    required ReportPeriod period,
    required DateTime now,
  }) {
    final start = period.startFrom(now);
    final end = period.endBefore(now);

    final inWindow =
        transactions.where((tx) => period.contains(tx.date, now)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final income = inWindow.where((tx) => tx.countsAsIncome).toList();
    final expenses = inWindow.where((tx) => tx.countsAsExpense).toList();

    final incomePaisa = income.fold(0, (sum, tx) => sum + tx.amountPaisa);
    final windfallPaisa = income
        .where((tx) => tx.isWindfall)
        .fold(0, (sum, tx) => sum + tx.amountPaisa);
    final expensePaisa = expenses.fold(0, (sum, tx) => sum + tx.amountPaisa);

    // Previous equally long window, for the comparison line.
    int? previousExpense;
    int? previousIncome;
    final previous = period.previousRange(now);
    if (previous != null) {
      previousExpense = 0;
      previousIncome = 0;
      for (final tx in transactions) {
        if (!previous.contains(tx.date)) continue;
        if (tx.isExpense) {
          previousExpense = previousExpense! + tx.amountPaisa;
        } else {
          previousIncome = previousIncome! + tx.amountPaisa;
        }
      }
    }

    final categoryTotals = <String, int>{};
    final categoryCounts = <String, int>{};
    for (final expense in expenses) {
      categoryTotals.update(
        expense.category,
        (value) => value + expense.amountPaisa,
        ifAbsent: () => expense.amountPaisa,
      );
      categoryCounts.update(
        expense.category,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    final categories =
        categoryTotals.entries
            .map(
              (entry) => ReportCategory(
                label: entry.key,
                paisa: entry.value,
                transactionCount: categoryCounts[entry.key] ?? 0,
                share: expensePaisa <= 0 ? 0 : entry.value / expensePaisa,
              ),
            )
            .toList()
          ..sort((a, b) => b.paisa.compareTo(a.paisa));

    final monthBuckets = <String, ReportMonth>{};
    for (final tx in inWindow) {
      final key =
          '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      final existing =
          monthBuckets[key] ??
          ReportMonth(
            month: DateTime(tx.date.year, tx.date.month),
            incomePaisa: 0,
            expensePaisa: 0,
          );
      monthBuckets[key] = ReportMonth(
        month: existing.month,
        incomePaisa:
            existing.incomePaisa + (tx.countsAsIncome ? tx.amountPaisa : 0),
        expensePaisa:
            existing.expensePaisa + (tx.countsAsExpense ? tx.amountPaisa : 0),
      );
    }
    final months = monthBuckets.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));

    final sortedExpenses = List<ExpenseModel>.from(expenses)
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));
    final sortedIncome = List<ExpenseModel>.from(income)
      ..sort((a, b) => b.amountPaisa.compareTo(a.amountPaisa));

    final report = FinancialReport(
      period: period,
      generatedAt: now,
      rangeStart: start ?? (inWindow.isEmpty ? null : inWindow.last.date),
      rangeEnd: end == null
          ? now
          : end.subtract(const Duration(days: 1)),
      incomePaisa: incomePaisa,
      expensePaisa: expensePaisa,
      incomeCount: income.length,
      expenseCount: expenses.length,
      windfallIncomePaisa: windfallPaisa,
      categories: categories,
      months: months,
      topExpenses: sortedExpenses.take(10).toList(),
      topIncome: sortedIncome.take(10).toList(),
      previousExpensePaisa: previousExpense,
      previousIncomePaisa: previousIncome,
      observations: const [],
    );

    return FinancialReport(
      period: report.period,
      generatedAt: report.generatedAt,
      rangeStart: report.rangeStart,
      rangeEnd: report.rangeEnd,
      incomePaisa: report.incomePaisa,
      expensePaisa: report.expensePaisa,
      incomeCount: report.incomeCount,
      expenseCount: report.expenseCount,
      categories: report.categories,
      months: report.months,
      topExpenses: report.topExpenses,
      topIncome: report.topIncome,
      previousExpensePaisa: report.previousExpensePaisa,
      previousIncomePaisa: report.previousIncomePaisa,
      windfallIncomePaisa: report.windfallIncomePaisa,
      observations: _buildObservations(report),
      narrative: null,
    );
  }

  /// Plain-language findings derived from the figures, so the report says
  /// something useful even with no AI available.
  static List<String> _buildObservations(FinancialReport report) {
    final observations = <String>[];
    if (!report.hasData) {
      return observations;
    }

    final rate = report.savingsRate;
    if (rate != null) {
      if (rate < 0) {
        observations.add(
          'Spending exceeded income by '
          '${MoneyUtils.formatPaisa(report.netPaisa.abs())} over this period.',
        );
      } else {
        observations.add(
          'Kept ${(rate * 100).round()}% of income '
          '(${MoneyUtils.formatPaisa(report.netPaisa)}).',
        );
      }
    } else if (report.expensePaisa > 0) {
      observations.add(
        'No income was recorded in this period, against '
        '${MoneyUtils.formatPaisa(report.expensePaisa)} of spending.',
      );
    }

    final change = report.expenseChangeRatio;
    if (change != null && change.abs() >= 0.05) {
      observations.add(
        'Spending is ${change >= 0 ? 'up' : 'down'} '
        '${(change.abs() * 100).round()}% versus the previous '
        '${report.period.label.toLowerCase()}.',
      );
    }

    final top = report.largestCategory;
    if (top != null && top.share >= 0.25) {
      observations.add(
        '${top.label} took ${(top.share * 100).round()}% of all spending '
        '(${MoneyUtils.formatPaisa(top.paisa)} across '
        '${top.transactionCount} transaction'
        '${top.transactionCount == 1 ? '' : 's'}).',
      );
    }

    final largest = report.largestExpense;
    if (largest != null &&
        report.expensePaisa > 0 &&
        largest.amountPaisa / report.expensePaisa >= 0.2) {
      observations.add(
        'A single expense, ${largest.title} at '
        '${MoneyUtils.formatAmount(largest.amount)}, accounts for '
        '${(largest.amountPaisa / report.expensePaisa * 100).round()}% of the '
        'total.',
      );
    }

    if (report.averageDailyExpensePaisa > 0) {
      observations.add(
        'Average spend was '
        '${MoneyUtils.formatPaisa(report.averageDailyExpensePaisa)} per day '
        'across ${report.dayCount} days.',
      );
    }

    return observations;
  }

  /// Fetches only the AI commentary for an already computed report.
  ///
  /// Exposed so the UI can render the exact figures instantly and fill the
  /// prose in when it arrives, instead of holding the whole report behind a
  /// network call that can take most of a minute.
  static Future<String> requestNarrative(FinancialReport report) {
    return _requestNarrative(report);
  }

  static Future<String> _requestNarrative(FinancialReport report) async {
    final payload = jsonEncode({
      'model': Secrets.groqModel,
      'messages': [
        {
          'role': 'system',
          'content':
              'You write the commentary section of a personal finance report. '
              'Every figure you need is supplied and already exact — never '
              'compute or invent one. Write in clear plain English for the '
              'person whose money it is, not for an accountant. Be specific '
              'and honest: name the biggest problem and the biggest win. No '
              'preamble, no sign-off, no invented context about their life. '
              'Currency is Nepalese Rupees written as Rs.',
        },
        {'role': 'user', 'content': _narrativePrompt(report)},
      ],
      'temperature': 0.4,
      'max_tokens': 900,
    });

    final response = await http
        .post(
          Uri.https('api.groq.com', '/openai/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer ${Secrets.groqApiKey}',
            'Content-Type': 'application/json',
          },
          body: payload,
        )
        // A four-section report is a much bigger generation than a chat reply,
        // and 45s was not enough for it on a first, cold request.
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Report narrative failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No narrative returned');
    }
    final message = choices.first['message'];
    if (message is! Map) {
      throw Exception('Malformed narrative response');
    }
    final content = message['content']?.toString().trim() ?? '';
    if (content.isEmpty) {
      throw Exception('Empty narrative');
    }
    return content;
  }

  static String _narrativePrompt(FinancialReport report) {
    final buffer = StringBuffer()
      ..writeln('Report period: ${report.period.label} (${report.rangeLabel})')
      ..writeln('Income: ${MoneyUtils.formatPaisa(report.incomePaisa)}')
      ..writeln('Spending: ${MoneyUtils.formatPaisa(report.expensePaisa)}')
      ..writeln('Net: ${MoneyUtils.formatPaisa(report.netPaisa)}');

    final rate = report.savingsRate;
    if (rate != null) {
      buffer.writeln('Share of income kept: ${(rate * 100).round()}%');
    }
    buffer
      ..writeln('Transactions: ${report.transactionCount}')
      ..writeln(
        'Average per day: '
        '${MoneyUtils.formatPaisa(report.averageDailyExpensePaisa)} '
        'over ${report.dayCount} days',
      );

    final change = report.expenseChangeRatio;
    if (change != null) {
      buffer.writeln(
        'Spending vs previous equal period: '
        '${change >= 0 ? '+' : ''}${(change * 100).round()}%',
      );
    }

    if (report.categories.isNotEmpty) {
      buffer.writeln('\nCategories:');
      for (final category in report.categories.take(8)) {
        buffer.writeln(
          '- ${category.label}: '
          '${MoneyUtils.formatPaisa(category.paisa)} '
          '(${(category.share * 100).round()}%, '
          '${category.transactionCount} txns)',
        );
      }
    }

    if (report.topExpenses.isNotEmpty) {
      buffer.writeln('\nLargest expenses:');
      for (final expense in report.topExpenses.take(5)) {
        buffer.writeln(
          '- ${expense.title} (${expense.category}): '
          '${MoneyUtils.formatAmount(expense.amount)}',
        );
      }
    }

    if (report.months.length > 1) {
      buffer.writeln('\nBy month:');
      for (final month in report.months) {
        buffer.writeln(
          '- ${month.shortLabel}: in '
          '${MoneyUtils.formatPaisa(month.incomePaisa)}, out '
          '${MoneyUtils.formatPaisa(month.expensePaisa)}, net '
          '${MoneyUtils.formatPaisa(month.netPaisa)}',
        );
      }
    }

    buffer
      ..writeln('\nVerified observations:')
      ..writeAll(report.observations.map((o) => '- $o\n'));

    buffer.writeln('''

Write exactly these four sections, using these headings verbatim:

## Overview
Two or three sentences on what this period looked like overall.

## What stands out
Three to five bullets on the specific things worth noticing. Cite figures.

## What to do next
Three concrete, prioritised actions. Each must name a number and be something
they can actually act on. No generic advice.

## Watch out for
One short paragraph on the main risk visible in these numbers. If there is no
real risk, say the position looks sound and why.
''');

    return buffer.toString();
  }

  /// Renders the report to a PDF file on disk.
  static Future<File> generatePdf(FinancialReport report) async {
    final bytes = await ReportPdfBuilder.build(report);

    Directory? directory;
    try {
      directory = await getDownloadsDirectory();
    } catch (_) {
      directory = null;
    }
    directory ??= await getApplicationDocumentsDirectory();

    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final stamp = report.generatedAt;
    final name =
        'SmartExpense_Report_'
        '${stamp.year}${_two(stamp.month)}${_two(stamp.day)}_'
        '${_two(stamp.hour)}${_two(stamp.minute)}.pdf';

    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<void> sharePdf(FinancialReport report) async {
    final file = await generatePdf(report);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'SmartExpense report — ${report.period.label}',
      text:
          'My ${report.period.label.toLowerCase()} financial report '
          '(${report.rangeLabel}).',
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

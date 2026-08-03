import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pdf;
import 'package:pdf/pdf.dart' as pdf;
import 'package:share_plus/share_plus.dart';

import '../core/models/expense_model.dart';
import '../core/secrets.dart';
import '../core/utils/money_utils.dart';
import 'user_data_service.dart';

class FinancialReportService {
  static Future<String> generateProfessionalReport({
    int? forMonths,
    DateTime? startDate,
    DateTime? endDate,
    String reportType = 'financial',
  }) async {
    // Fetch all transactions for the report period
    final transactions = await _fetchTransactionsForPeriod(startDate, endDate);

    if (transactions.isEmpty) {
      return 'No transactions found for the selected period.';
    }

    final reportData = _processReportData(transactions, forMonths, startDate, endDate);

    // Generate AI-powered report using Groq
    return _generateAIPoweredReport(reportData, reportType);
  }

  static Future<List<ExpenseModel>> _fetchTransactionsForPeriod(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    // Fetch all transactions first
    final allTransactions = await UserDataService.getTransactionsOnce();

    // Filter by date range if specified
    if (startDate != null || endDate != null) {
      return allTransactions.where((tx) {
        final txDate = tx.date;
        if (startDate != null && txDate.isBefore(startDate)) return false;
        if (endDate != null && txDate.isAfter(endDate)) return false;
        return true;
      }).toList();
    }

    return allTransactions;
  }

  static Map<String, dynamic> _processReportData(
    List<ExpenseModel> transactions,
    int? forMonths,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    // Sort by date descending
    transactions.sort((a, b) => b.date.compareTo(a.date));

    final income = transactions.where((tx) => !tx.isExpense).toList();
    final expenses = transactions.where((tx) => tx.isExpense).toList();

    final incomePaisa = income.fold(0, (sum, tx) => sum + tx.amountPaisa);
    final expensePaisa = expenses.fold(0, (sum, tx) => sum + tx.amountPaisa);
    final balancePaisa = incomePaisa - expensePaisa;

    // Category breakdown
    final categoryTotals = <String, int>{};
    for (final expense in expenses) {
      categoryTotals.update(
        expense.category,
        (value) => value + expense.amountPaisa,
        ifAbsent: () => expense.amountPaisa,
      );
    }

    final topCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Monthly trend
    final monthlyData = <String, Map<String, int>>{};
    for (final tx in transactions) {
      final monthKey = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      monthlyData.putIfAbsent(monthKey, () => {'income': 0, 'expense': 0});
      if (tx.isExpense) {
        monthlyData[monthKey]!['expense'] = monthlyData[monthKey]!['expense']! + tx.amountPaisa;
      } else {
        monthlyData[monthKey]!['income'] = monthlyData[monthKey]!['income']! + tx.amountPaisa;
      }
    }

    // Top transactions
    final topExpenses = expenses.take(10).map((tx) => {
      'title': tx.title,
      'category': tx.category,
      'amount': MoneyUtils.formatPaisa(tx.amountPaisa),
      'date': tx.date.toIso8601String().split('T').first,
    }).toList();

    final topIncome = income.take(10).map((tx) => {
      'title': tx.title,
      'category': tx.category,
      'amount': MoneyUtils.formatPaisa(tx.amountPaisa),
      'date': tx.date.toIso8601String().split('T').first,
    }).toList();

    // Date range for report header
    final earliestDate = transactions.last.date;
    final latestDate = transactions.first.date;
    final dateRange = '${earliestDate.day}/${earliestDate.month}/${earliestDate.year} - ${latestDate.day}/${latestDate.month}/${latestDate.year}';

    return {
      'reportDate': DateTime.now().toIso8601String().split('T').first,
      'dateRange': dateRange,
      'totalIncome': MoneyUtils.formatPaisa(incomePaisa),
      'totalExpenses': MoneyUtils.formatPaisa(expensePaisa),
      'netBalance': MoneyUtils.formatPaisa(balancePaisa),
      'incomePaisa': incomePaisa,
      'expensePaisa': expensePaisa,
      'balancePaisa': balancePaisa,
      'transactionCount': transactions.length,
      'incomeCount': income.length,
      'expenseCount': expenses.length,
      'topCategories': topCategories.take(10).map((e) => {
        'category': e.key,
        'amount': MoneyUtils.formatPaisa(e.value),
        'percentage': expensePaisa > 0 ? ((e.value / expensePaisa) * 100).toStringAsFixed(1) : '0',
      }).toList(),
      'monthlyTrend': monthlyData.entries.map((e) => {
        'month': e.key,
        'income': MoneyUtils.formatPaisa(e.value['income']!),
        'expense': MoneyUtils.formatPaisa(e.value['expense']!),
        'net': MoneyUtils.formatPaisa(e.value['income']! - e.value['expense']!),
      }).toList(),
      'topExpenses': topExpenses,
      'topIncome': topIncome,
      'savingsRate': incomePaisa > 0 ? ((balancePaisa / incomePaisa) * 100).toStringAsFixed(1) : '0',
    };
  }

  static Future<String> _generateAIPoweredReport(Map<String, dynamic> data, String reportType) async {
    if (Secrets.groqApiKey.isEmpty || !Secrets.groqApiKey.startsWith('gsk_')) {
      return _generateBasicReport(data);
    }

    try {
      final prompt = _buildReportPrompt(data, reportType);
      final response = await _callGroqApi(prompt);
      return response;
    } catch (e) {
      return _generateBasicReport(data);
    }
  }

  static String _buildReportPrompt(Map<String, dynamic> data, String reportType) {
    final categories = data['topCategories'].map((c) => '- ${c['category']}: ${c['amount']} (${c['percentage']}%)').join('\n');
    final monthlyTrend = data['monthlyTrend'].map((m) => '- ${m['month']}: Income ${m['income']}, Expense ${m['expense']}, Net ${m['net']}').join('\n');
    final topExpenses = data['topExpenses'].map((e) => '- ${e['title']} (${e['category']}): ${e['amount']} on ${e['date']}').join('\n');
    final topIncome = data['topIncome'].map((e) => '- ${e['title']} (${e['category']}): ${e['amount']} on ${e['date']}').join('\n');

    return '''
Generate a professional financial report for a CA-style financial statement.

USER DATA:
Report Period: ${data['dateRange']}
Report Date: ${data['reportDate']}

FINANCIAL SUMMARY:
- Total Income: ${data['totalIncome']}
- Total Expenses: ${data['totalExpenses']}
- Net Balance: ${data['netBalance']}
- Savings Rate: ${data['savingsRate']}%
- Total Transactions: ${data['transactionCount']} (Income: ${data['incomeCount']}, Expenses: ${data['expenseCount']})

TOP SPENDING CATEGORIES:
$categories

MONTHLY TREND:
$monthlyTrend

TOP EXPENSES:
$topExpenses

TOP INCOME SOURCES:
$topIncome

Generate a comprehensive report with these sections:
1. EXECUTIVE SUMMARY - Key financial highlights
2. INCOME ANALYSIS - Breakdown of income sources
3. EXPENSE ANALYSIS - Category-wise expense breakdown with insights
4. MONTHLY TREND ANALYSIS - Spending patterns over time
5. SAVINGS & CASH FLOW - Savings rate analysis and recommendations
6. KEY OBSERVATIONS - Notable patterns, anomalies, or concerns
7. ACTIONABLE RECOMMENDATIONS - Specific steps to improve financial health
8. RISK ASSESSMENT - Areas of concern

Format as clean markdown with professional tone. Use emojis sparingly for section headers.
Be specific with numbers. Give actionable advice.
''';
  }

  static Future<String> _callGroqApi(String prompt) async {
    final payload = jsonEncode({
      'model': Secrets.groqModel,
      'messages': [
        {
          'role': 'system',
          'content': 'You are a Chartered Accountant generating professional financial reports. Provide detailed, actionable, and professionally formatted reports with specific numbers and insights.',
        },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
      'temperature': 0.3,
      'max_tokens': 2500,
    });

    final response = await http.post(
      Uri.https('api.groq.com', '/openai/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${Secrets.groqApiKey}',
        'Content-Type': 'application/json',
      },
      body: payload,
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Groq API error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No response from Groq');
    }

    final message = choices.first['message'];
    if (message is! Map) {
      throw Exception('Invalid response format');
    }

    return message['content']?.toString().trim() ?? 'Report generation failed';
  }

  static String _generateBasicReport(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    buffer.writeln('# Financial Report');
    buffer.writeln('');
    buffer.writeln('**Report Period:** ${data['dateRange']}');
    buffer.writeln('**Generated:** ${data['reportDate']}');
    buffer.writeln('');
    buffer.writeln('## Executive Summary');
    buffer.writeln('- **Total Income:** ${data['totalIncome']}');
    buffer.writeln('- **Total Expenses:** ${data['totalExpenses']}');
    buffer.writeln('- **Net Balance:** ${data['netBalance']}');
    buffer.writeln('- **Savings Rate:** ${data['savingsRate']}%');
    buffer.writeln('- **Total Transactions:** ${data['transactionCount']}');
    buffer.writeln('');
    buffer.writeln('## Top Spending Categories');
    for (final cat in data['topCategories']) {
      buffer.writeln('- ${cat['category']}: ${cat['amount']} (${cat['percentage']}%)');
    }
    buffer.writeln('');
    buffer.writeln('## Monthly Trend');
    for (final month in data['monthlyTrend']) {
      buffer.writeln('- ${month['month']}: Income ${month['income']}, Expense ${month['expense']}, Net ${month['net']}');
    }
    buffer.writeln('');
    buffer.writeln('## Top Expenses');
    for (final exp in data['topExpenses']) {
      buffer.writeln('- ${exp['title']} (${exp['category']}): ${exp['amount']} on ${exp['date']}');
    }
    buffer.writeln('');
    buffer.writeln('## Top Income Sources');
    for (final inc in data['topIncome']) {
      buffer.writeln('- ${inc['title']} (${inc['category']}): ${inc['amount']} on ${inc['date']}');
    }
    return buffer.toString();
  }

  static String sanitizeReportForDisplay(String content, {int maxLength = 2500}) {
    if (content.trim().isEmpty) {
      return 'No report content available.';
    }

    var sanitized = content
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'`'), '')
        .replaceAll(RegExp(r'^[-*]\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (sanitized.length > maxLength) {
      sanitized = '${sanitized.substring(0, maxLength - 3).trim()}...';
    }

    return sanitized;
  }

  // PDF Generation
  static Future<File> generatePDFReport({
    int? forMonths,
    DateTime? startDate,
    DateTime? endDate,
    String reportType = 'financial',
  }) async {
    final rawReportContent = await generateProfessionalReport(
      forMonths: forMonths,
      startDate: startDate,
      endDate: endDate,
      reportType: reportType,
    );

    final reportContent = sanitizeReportForDisplay(rawReportContent, maxLength: 2200);
    final pdfDoc = pdf.Document();

    pdfDoc.addPage(
      pdf.Page(
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pdf.EdgeInsets.all(32),
        build: (context) {
          final content = reportContent;
          return pdf.Column(
            crossAxisAlignment: pdf.CrossAxisAlignment.start,
            children: [
              pdf.Text(
                'Financial Report',
                style: pdf.TextStyle(fontSize: 26, fontWeight: pdf.FontWeight.bold),
              ),
              pdf.SizedBox(height: 8),
              pdf.Text(
                'Generated: ${DateTime.now().toString().split('.').first}',
                style: pdf.TextStyle(fontSize: 10, color: pdf.PdfColors.grey700),
              ),
              pdf.SizedBox(height: 18),
              pdf.Text(
                content,
                style: pdf.TextStyle(fontSize: 11, height: 1.4),
              ),
            ],
          );
        },
      ),
    );

    Directory? directory;
    try {
      directory = await getDownloadsDirectory();
    } catch (_) {
      directory = null;
    }

    directory ??= await getTemporaryDirectory();

    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final fileName = 'financial_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(await pdfDoc.save());
    return file;
  }

  // Share report
  static Future<void> shareReport({
    int? forMonths,
    DateTime? startDate,
    DateTime? endDate,
    String reportType = 'financial',
  }) async {
    final file = await generatePDFReport(
      forMonths: forMonths,
      startDate: startDate,
      endDate: endDate,
      reportType: reportType,
    );

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'My Financial Report from SmartExpense',
    );
  }
}
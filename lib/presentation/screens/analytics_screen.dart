import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/expense_model.dart';
import '../../../core/utils/money_utils.dart';
import '../../../services/user_data_service.dart';
import 'all_expenses_screen.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  static const _ink = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExpenseModel>>(
      stream: UserDataService.transactionsStream(),
      builder: (context, snapshot) {
        final transactions = _sortedTransactions(snapshot.data ?? const <ExpenseModel>[]);
        final expenses = transactions.where((transaction) => transaction.isExpense).toList();
        final incomePaisa = _totalPaisa(transactions.where((transaction) => !transaction.isExpense));
        final expensePaisa = _totalPaisa(expenses);
        final categorySlices = _buildCategorySlices(expenses);
        final sevenDayTrend = _buildRecentTrend(expenses, dayCount: 7);
        final thirtyDayTrend = _buildRecentTrend(expenses, dayCount: 30);

        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Category Details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (categorySlices.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 170),
                  child: Center(
                    child: Text(
                      'Add expenses to see detailed analytics',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
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

class _FinancialAssistantPanel extends StatefulWidget {
  final List<ExpenseModel> transactions;
  final int expensePaisa;
  final int incomePaisa;
  final List<_CategorySlice> categorySlices;

  const _FinancialAssistantPanel({
    required this.transactions,
    required this.expensePaisa,
    required this.incomePaisa,
    required this.categorySlices,
  });

  @override
  State<_FinancialAssistantPanel> createState() =>
      _FinancialAssistantPanelState();
}

class _FinancialAssistantPanelState extends State<_FinancialAssistantPanel> {
  static const _apiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
  static const _model = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: 'llama-3.1-8b-instant',
  );

  final _questionController = TextEditingController();
  String? _answer;
  String? _error;
  var _isLoading = false;

  bool get _hasGroqApiKey => _apiKey.startsWith('gsk_');

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _askAssistant() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _isLoading) {
      return;
    }

    if (!_hasGroqApiKey) {
      setState(() {
        _error = 'Add a valid GROQ_API_KEY to enable AI responses.';
        _answer = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _answer = null;
    });

    try {
      final text = await _requestGroq(question);

      if (!mounted) {
        return;
      }
      setState(() {
        _answer = text.isNotEmpty
            ? text
            : 'I could not generate a report for this question.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyGroqError(error);
        _answer = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _useSuggestion(String question) {
    _questionController.text = question;
    _questionController.selection = TextSelection.fromPosition(
      TextPosition(offset: _questionController.text.length),
    );
  }

  Map<String, String> get _groqHeaders {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'SmartExpense/1.0',
      'Authorization': 'Bearer $_apiKey',
    };
  }

  Future<String> _requestGroq(String question) async {
    final payload = jsonEncode({
      'model': _model,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a smart, witty, and friendly financial companion (a "financial friend"). You have access to the user\'s financial snapshot, but DO NOT output a full report unless they explicitly ask for one or ask a question about their finances. If they just say "hi" or make small talk, respond casually, warmly, and playfully like a friend. When they DO ask for financial advice or a report, be highly analytical, point out money leaks, and use rich Markdown formatting (bolding, headers, bullet points, emojis). Always give highly specific, actionable advice based on their data. Keep it conversational, fun, and deeply insightful. Never be dull or generic.',
        },
        {
          'role': 'user',
          'content': _buildPrompt(question),
        },
      ],
      'temperature': 0.4,
      'max_tokens': 700,
    });

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .post(
              Uri.https('api.groq.com', '/openai/v1/chat/completions'),
              headers: _groqHeaders,
              body: payload,
            )
            .timeout(const Duration(seconds: 35));

        final data = _decodeJsonObject(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_groqErrorMessage(data, response.statusCode));
        }

        return _extractGroqText(data);
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }

    throw Exception(lastError ?? 'Groq request failed.');
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  String _groqErrorMessage(Map<String, dynamic> data, int statusCode) {
    final error = data['error'];
    if (error is Map) {
      final message = error['message']?.toString();
      if (message?.isNotEmpty == true) {
        return 'Groq HTTP $statusCode: $message';
      }
    }
    return 'Groq HTTP $statusCode';
  }

  String _extractGroqText(Map<String, dynamic> data) {
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return '';
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      return '';
    }

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      return '';
    }

    return message['content']?.toString().trim() ?? '';
  }

  String _friendlyGroqError(Object error) {
    final details = error.toString().replaceFirst('Exception: ', '');
    return 'Groq request failed. Check internet connection, then try again.\n\nDetails: $details';
  }

  String _buildPrompt(String question) {
    final recent = widget.transactions.take(12).map((transaction) {
      final type = transaction.isExpense ? 'expense' : 'income';
      final date = transaction.date.toIso8601String().split('T').first;
      return '- $type: ${transaction.title}, ${transaction.category}, ${MoneyUtils.formatPaisa(transaction.amountPaisa)}, $date';
    }).join('\n');
    final categories = widget.categorySlices.take(5).map((slice) {
      return '- ${slice.label}: ${MoneyUtils.formatPaisa(slice.paisa)}';
    }).join('\n');

    return '''
User question: $question

Financial snapshot:
- Total income: ${MoneyUtils.formatPaisa(widget.incomePaisa)}
- Total expenses: ${MoneyUtils.formatPaisa(widget.expensePaisa)}
- Balance: ${MoneyUtils.formatPaisa(widget.incomePaisa - widget.expensePaisa)}

Top spending categories:
${categories.isEmpty ? '- No expenses yet' : categories}

Recent transactions:
${recent.isEmpty ? '- No transactions yet' : recent}
''';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'AI Financial Assistant',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          if (!_hasGroqApiKey) ...[
            const SizedBox(height: 10),
            Text(
              'Add a Groq API key at run time for AI-generated responses.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AssistantPromptChip(
                label: 'Analyze my spending',
                onTap: () => _useSuggestion(
                  'Give me a brutally honest analysis of my recent spending and identify any money leaks.',
                ),
              ),
              _AssistantPromptChip(
                label: 'Generate weekly report',
                onTap: () => _useSuggestion(
                  'Generate a comprehensive weekly financial report with insights and emojis.',
                ),
              ),
              _AssistantPromptChip(
                label: 'Savings plan',
                onTap: () => _useSuggestion(
                  'Based strictly on my data, where can I cut costs to save 20% more this month?',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _questionController,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _askAssistant(),
            decoration: InputDecoration(
              hintText: 'Ask for advice or a spending report',
              suffixIcon: IconButton(
                tooltip: 'Ask AI',
                onPressed: _isLoading ? null : _askAssistant,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: colorScheme.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_answer != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: MarkdownBody(
                data: _answer!,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  h1: TextStyle(color: colorScheme.primary, fontSize: 18, fontWeight: FontWeight.bold),
                  h2: TextStyle(color: colorScheme.primary, fontSize: 16, fontWeight: FontWeight.bold),
                  h3: TextStyle(color: colorScheme.primary, fontSize: 15, fontWeight: FontWeight.bold),
                  listBullet: TextStyle(color: colorScheme.primary, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantPromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AssistantPromptChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(
        Icons.bolt_rounded,
        size: 16,
        color: colorScheme.primary,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.18)),
      onPressed: onTap,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Analytics',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.insights_rounded,
              color: colorScheme.primary,
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
  final VoidCallback onSpentTap;

  const _SummaryBand({
    required this.incomePaisa,
    required this.expensePaisa,
    required this.onSpentTap,
  });

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
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onSpentTap,
              child: _MetricCard(
                label: 'Spent',
                amount: MoneyUtils.formatPaisa(expensePaisa),
                icon: Icons.trending_down_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
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
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Expense Breakdown',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (widget.slices.isNotEmpty)
                  _isSharing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: SizedBox.shrink(),
                        )
                      : IconButton(
                          icon: const Icon(Icons.share_rounded, size: 20),
                          tooltip: 'Share breakdown chart',
                          onPressed: _shareChart,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
              ],
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
                      painter: _DonutChartPainter(slices: widget.slices, backgroundColor: colorScheme.outline),
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
    final visibleSlices = slices.take(4).toList();

    if (visibleSlices.isEmpty) {
      return Center(
        child: Text(
          'No expenses yet',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  slice.percentLabel(totalExpensePaisa),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

    return RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Last $_dayCount Days',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(width: 8),
                          if (points.isNotEmpty)
                            _isSharing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: SizedBox.shrink(),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.share_rounded, size: 18),
                                    tooltip: 'Share trend chart',
                                    onPressed: _shareChart,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Expense trend',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MoneyUtils.formatPaisa(totalPaisa),
                    maxLines: 1,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isIncrease ? colorScheme.error : _TrendColors.green)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isIncrease
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          color:
                              isIncrease ? colorScheme.error : _TrendColors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${isIncrease ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: isIncrease ? colorScheme.error : _TrendColors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                height: points.length > 7 ? 220 : 250,
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
                      Text(
                        hasValues ? _formatAxisPaisa(label) : 'Rs. 0',
                        maxLines: 1,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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
                    gridColor: colorScheme.outline.withValues(alpha: 0.55),
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

  String _formatAxisPaisa(int paisa) {
    final rupees = paisa / 100;
    if (rupees >= 100000) {
      return 'Rs. ${(rupees / 100000).toStringAsFixed(1)}L';
    }
    if (rupees >= 1000) {
      return 'Rs. ${(rupees / 1000).toStringAsFixed(1)}k';
    }
    return 'Rs. ${rupees.round()}';
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
    final color =
        isIncrease ? _TrendColors.green : Theme.of(context).colorScheme.error;

    return Column(
      children: [
        Icon(
          isIncrease
              ? Icons.arrow_drop_up_rounded
              : Icons.arrow_drop_down_rounded,
          color: color,
          size: 20,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${isIncrease ? '+' : '-'}${MoneyUtils.formatPaisa(value.abs())}',
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

class _TrendColors {
  static const green = Color(0xFF2E9D57);
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
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
                    backgroundColor: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            MoneyUtils.formatPaisa(slice.paisa),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
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

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/models/ai_chat_message.dart';
import '../core/models/expense_model.dart';
import '../core/models/financial_record_action.dart';
import '../core/secrets.dart';
import '../core/utils/money_utils.dart';
import 'user_data_service.dart';
import 'user_settings_service.dart';

class AiFinancialAssistantService {
  static const _uuid = Uuid();

  static Future<List<AiChatSession>> getSessions() async {
    return await UserSettingsService.getAiSessionsOnce();
  }

  static Future<AiChatSession?> getSession(String id) async {
    return await UserSettingsService.getAiSession(id);
  }

  static Future<String?> getActiveSessionId() async {
    return await UserSettingsService.getActiveAiSessionId();
  }

  static Future<AiChatSession> createSession({bool makeActive = true}) async {
    final now = DateTime.now();
    final session = AiChatSession(
      id: _uuid.v4(),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    await UserSettingsService.saveAiSession(session);
    if (makeActive) {
      await UserSettingsService.setActiveAiSessionId(session.id);
    }
    return session;
  }

  static Future<AiChatSession> createStartupSession() async {
    final activeId = await getActiveSessionId();
    if (activeId != null && activeId.isNotEmpty) {
      final existing = await getSession(activeId);
      if (existing != null) {
        return existing;
      }
    }
    return createSession();
  }

  static Future<void> setActiveSession(String id) async {
    await UserSettingsService.setActiveAiSessionId(id);
  }

  static Future<void> saveMessages(
    String sessionId,
    List<AiChatMessage> messages,
  ) async {
    final session = await getSession(sessionId);
    final now = DateTime.now();
    final nextSession = AiChatSession(
      id: sessionId,
      title: _titleFor(messages),
      createdAt: session?.createdAt ?? now,
      updatedAt: now,
      messages: messages,
    );
    await UserSettingsService.saveAiSession(nextSession);
  }

  static Future<void> clearSession(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) {
      return;
    }
    final cleared = session.copyWith(
      title: 'New chat',
      updatedAt: DateTime.now(),
      messages: const [],
    );
    await UserSettingsService.saveAiSession(cleared);
  }

  static Future<void> deleteSession(String sessionId) async {
    await UserSettingsService.deleteAiSession(sessionId);

    final activeId = await getActiveSessionId();
    if (activeId == sessionId) {
      final sessions = await getSessions();
      if (sessions.isNotEmpty) {
        await setActiveSession(sessions.first.id);
      } else {
        await UserSettingsService.setActiveAiSessionId('');
      }
    }
  }

  static AiChatMessage userMessage(String content) {
    return AiChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
    );
  }

  static AiChatMessage assistantMessage(String content) {
    return AiChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      content: content,
      createdAt: DateTime.now(),
    );
  }

  static Future<FinancialActionParseResult> detectFinancialAction({
    required String question,
    required List<AiChatMessage> history,
  }) async {
    if (!_looksLikeRecordMutationRequest(question)) {
      return const FinancialActionParseResult();
    }

    if (Secrets.groqApiKey.isEmpty || !Secrets.groqApiKey.startsWith('gsk_')) {
      return const FinancialActionParseResult();
    }

    final payload = jsonEncode({
      'model': Secrets.groqModel,
      'messages': [
        {
          'role': 'system',
          'content': '''
You convert user messages into financial record actions for SmartExpense.

Return STRICT JSON only. No markdown. No commentary.

Supported actions:
- add: create expense/income
- update: edit amount, category, title/note, date, or type
- delete: delete expense/income
- none: not a financial record action
- clarify: user wants an action but required information is missing

Rules:
- Only return add/update/delete when the user clearly asks to change app records.
- If the user asks for advice, analysis, reports, affordability, budgeting, saving tips, explanations, or casual chat, return actionType "none".
- If the user says they spent/earned money but does not clearly ask to save it, return actionType "none".
- Do not treat advice questions as actions.
- For update/delete, choose targetId from the provided transactions if possible.
- If target is unclear, return actionType "clarify" with a short clarification.
- "note" or "description" maps to title.
- type must be "expense" or "income".
- Dates must be ISO yyyy-mm-dd. If user omits date for add, use null.

JSON shape:
{
  "actionType": "add|update|delete|none|clarify",
  "clarification": "<string or null>",
  "targetId": "<existing transaction id or null>",
  "record": {
    "type": "expense|income|null",
    "title": "<string or null>",
    "amount": <number or null>,
    "category": "<string or null>",
    "date": "<yyyy-mm-dd or null>"
  }
}

''',
        },
        {
          'role': 'user',
          'content': await _buildActionPrompt(question, history),
        },
      ],
      'temperature': 0.05,
      'max_tokens': 500,
      'response_format': {'type': 'json_object'},
    });

    try {
      final response = await http
          .post(
            Uri.https('api.groq.com', '/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer ${Secrets.groqApiKey}',
              'Content-Type': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const FinancialActionParseResult();
      }

      final data = jsonDecode(response.body);
      final choices = data['choices'] as List<dynamic>?;
      final first = choices?.isNotEmpty == true ? choices!.first : null;
      if (first is! Map) {
        return const FinancialActionParseResult();
      }
      final message = first['message'];
      if (message is! Map) {
        return const FinancialActionParseResult();
      }
      final rawContent = message['content']?.toString();
      if (rawContent == null || rawContent.trim().isEmpty) {
        return const FinancialActionParseResult();
      }

      final decoded = jsonDecode(rawContent);
      if (decoded is! Map<String, dynamic>) {
        return const FinancialActionParseResult();
      }
      return await _parseFinancialAction(decoded, originalQuestion: question);
    } catch (_) {
      return const FinancialActionParseResult();
    }
  }

  static Future<String> executeFinancialAction(
    FinancialRecordAction action,
  ) async {
    switch (action.type) {
      case FinancialActionType.add:
        final next = action.newRecord;
        if (next == null) {
          throw Exception('Missing transaction details.');
        }
        await UserDataService.addTransaction(next);
        return 'Done bro. I added ${next.isExpense ? 'expense' : 'income'} "${next.title}" for ${MoneyUtils.formatAmount(next.amount)}.';
      case FinancialActionType.update:
        final next = action.newRecord;
        final targetId = action.targetId;
        if (next == null || targetId == null || targetId.isEmpty) {
          throw Exception('Missing transaction update details.');
        }
        await UserDataService.updateTransaction(targetId, next);
        return 'Done bro. I updated "${next.title}".';
      case FinancialActionType.delete:
        final targetId = action.targetId;
        final old = action.oldRecord;
        if (targetId == null || targetId.isEmpty || old == null) {
          throw Exception('Missing transaction delete details.');
        }
        await UserDataService.deleteTransaction(targetId);
        return 'Done bro. I deleted "${old.title}".';
    }
  }

  static Future<String> ask({
    required String question,
    required List<AiChatMessage> history,
  }) async {
    final localReply = _localCasualReply(question);
    if (localReply != null) {
      return localReply;
    }

    if (Secrets.groqApiKey.isEmpty || !Secrets.groqApiKey.startsWith('gsk_')) {
      throw Exception(
        'Please provide a valid Groq API key in lib/core/secrets.dart',
      );
    }

    final payload = jsonEncode({
      'model': Secrets.groqModel,
      'messages': [
        {'role': 'system', 'content': _systemPrompt()},
        for (final message in history)
          {
            'role': message.role == 'user' ? 'user' : 'assistant',
            'content': message.content,
          },
        {'role': 'user', 'content': await _buildPrompt(question)},
      ],
      'temperature': 0.45,
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
        .timeout(const Duration(seconds: 35));

    final data = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data is Map ? data['error'] : null;
      final message = error is Map ? error['message'] : response.body;
      throw Exception('AI request failed: $message');
    }

    final choices = data['choices'] as List<dynamic>?;
    final first = choices?.isNotEmpty == true ? choices!.first : null;
    if (first is! Map) {
      return 'I could not generate a useful response. Please try again.';
    }

    final message = first['message'];
    if (message is! Map) {
      return 'I could not generate a useful response. Please try again.';
    }

    return message['content']?.toString().trim().isNotEmpty == true
        ? message['content'].toString().trim()
        : 'I could not generate a useful response. Please try again.';
  }

  static Future<FinancialActionParseResult> _parseFinancialAction(
    Map<String, dynamic> data, {
    required String originalQuestion,
  }) async {
    final actionText = data['actionType']?.toString().toLowerCase().trim();
    if (actionText == null || actionText == 'none') {
      return const FinancialActionParseResult();
    }
    if (actionText == 'clarify') {
      return FinancialActionParseResult(
        clarification:
            data['clarification']?.toString().trim().isNotEmpty == true
            ? data['clarification'].toString().trim()
            : 'Which transaction should I change?',
      );
    }

    final type = switch (actionText) {
      'add' => FinancialActionType.add,
      'update' || 'edit' => FinancialActionType.update,
      'delete' || 'remove' => FinancialActionType.delete,
      _ => null,
    };
    if (type == null) {
      return const FinancialActionParseResult();
    }

    final recordMap = data['record'] is Map ? data['record'] as Map : const {};
    final targetId = data['targetId']?.toString();
    final existing = targetId == null || targetId.isEmpty
        ? null
        : await UserDataService.getTransactionById(targetId);

    if ((type == FinancialActionType.update ||
            type == FinancialActionType.delete) &&
        existing == null) {
      return const FinancialActionParseResult(
        clarification: 'Which transaction do you want me to change?',
      );
    }

    if (type == FinancialActionType.delete) {
      return FinancialActionParseResult(
        action: FinancialRecordAction(
          type: type,
          oldRecord: existing,
          targetId: targetId,
        ),
      );
    }

    final merged = _recordFromParsedData(
      recordMap,
      originalQuestion: originalQuestion,
      oldRecord: existing,
    );
    if (merged == null) {
      return const FinancialActionParseResult(
        clarification:
            'Please share the amount and whether this is income or expense.',
      );
    }

    return FinancialActionParseResult(
      action: FinancialRecordAction(
        type: type,
        oldRecord: existing,
        newRecord: merged,
        targetId: targetId,
      ),
    );
  }

  static ExpenseModel? _recordFromParsedData(
    Map<dynamic, dynamic> data, {
    required String originalQuestion,
    ExpenseModel? oldRecord,
  }) {
    final amount = (data['amount'] as num?)?.toDouble() ?? oldRecord?.amount;
    final parsedType = data['type']?.toString().toLowerCase();
    final inferredIsExpense = _inferIsExpense(originalQuestion, data);
    final isExpense =
        inferredIsExpense ??
        (parsedType == 'expense'
            ? true
            : parsedType == 'income'
            ? false
            : oldRecord?.isExpense);
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString().trim()
        : oldRecord?.title;
    final category = data['category']?.toString().trim().isNotEmpty == true
        ? data['category'].toString().trim()
        : oldRecord?.category;
    final dateText = data['date']?.toString();
    final parsedDate = dateText == null ? null : DateTime.tryParse(dateText);
    final date = parsedDate ?? oldRecord?.date ?? DateTime.now();

    if (amount == null || amount <= 0 || isExpense == null) {
      return null;
    }

    return ExpenseModel(
      id: oldRecord?.id ?? _uuid.v4(),
      title: title?.isNotEmpty == true
          ? title!
          : (isExpense ? 'Smart expense' : 'Smart income'),
      amount: amount,
      category: category?.isNotEmpty == true
          ? category!
          : (isExpense ? 'Other' : _incomeCategoryFor(originalQuestion)),
      date: date,
      isExpense: isExpense,
    );
  }

  static bool? _inferIsExpense(String question, Map<dynamic, dynamic> data) {
    final combined = [
      question,
      data['title']?.toString() ?? '',
      data['category']?.toString() ?? '',
    ].join(' ').toLowerCase();

    final outgoingPatterns = [
      RegExp(r'\b(gave|give|sent|send|paid|pay|transferred|transfer)\s+(to\s+)?(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
      RegExp(r'\b(to|for)\s+(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
    ];
    if (outgoingPatterns.any((pattern) => pattern.hasMatch(combined))) {
      return true;
    }

    final incomingPatterns = [
      RegExp(r'\b(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\s+(gave|sent|paid|transferred|send)\b'),
      RegExp(r'\b(cash|money|payment|transfer)\s+from\s+(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
      RegExp(r'\b(got|received|recieved)\s+.*\bfrom\s+\w+'),
      RegExp(r'\b(gave|sent|paid|transferred)\s+me\b'),
    ];
    if (incomingPatterns.any((pattern) => pattern.hasMatch(combined))) {
      return false;
    }

    const incomeSignals = [
      'salary',
      'paycheck',
      'pay cheque',
      'office pay',
      'office salary',
      'income',
      'earned',
      'earning',
      'received',
      'credited',
      'freelance',
      'business income',
      'bonus',
      'commission',
      'deposit',
      'refund',
      'reimbursement',
      'allowance',
      'pocket money',
      'cash from',
    ];
    const expenseSignals = [
      'spent',
      'spend',
      'paid',
      'payment',
      'bought',
      'purchase',
      'expense',
      'bill',
      'rent',
      'emi',
      'fee',
      'charge',
    ];

    final hasIncomeSignal = incomeSignals.any(combined.contains);
    final hasExpenseSignal = expenseSignals.any(combined.contains);
    if (hasIncomeSignal && !hasExpenseSignal) {
      return false;
    }
    if (hasExpenseSignal && !hasIncomeSignal) {
      return true;
    }
    if (combined.contains('salary') || combined.contains('income')) {
      return false;
    }
    return null;
  }

  static String _incomeCategoryFor(String question) {
    final lower = question.toLowerCase();
    if (lower.contains('freelance')) {
      return 'Freelance';
    }
    if (lower.contains('business')) {
      return 'Business';
    }
    if (lower.contains('investment') || lower.contains('dividend')) {
      return 'Investments';
    }
    if (lower.contains('gift')) {
      return 'Gifts';
    }
    return 'Salary';
  }

  static Future<String> _buildActionPrompt(
    String question,
    List<AiChatMessage> history,
  ) async {
    final transactions = await UserDataService.getRecentTransactions(30);
    transactions.sort((first, second) => second.date.compareTo(first.date));
    final recent = transactions.map((transaction) {
      return {
        'id': transaction.id,
        'type': transaction.isExpense ? 'expense' : 'income',
        'title': transaction.title,
        'amount': transaction.amount,
        'category': transaction.category,
        'date': transaction.date.toIso8601String().split('T').first,
      };
    }).toList();
    final recentChat = history.take(12).map((message) {
      return {'role': message.role, 'content': message.content};
    }).toList();

    return jsonEncode({
      'latestUserMessage': question,
      'recentChat': recentChat,
      'transactions': recent,
      'today': DateTime.now().toIso8601String().split('T').first,
    });
  }

  static String _titleFor(List<AiChatMessage> messages) {
    final firstUserMessage = messages
        .where((message) => message.role == 'user')
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .firstOrNull;
    if (firstUserMessage == null) {
      return 'New chat';
    }
    return firstUserMessage.length <= 34
        ? firstUserMessage
        : '${firstUserMessage.substring(0, 34)}...';
  }

  static String? _localCasualReply(String question) {
    final text = question.toLowerCase().trim();
    final clean = text.replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

    const greetings = {
      'hi',
      'hii',
      'hiii',
      'hello',
      'hey',
      'yo',
      'wassup',
      'whatsup',
      'sup',
      'namaste',
    };
    if (greetings.contains(clean)) {
      return clean == 'namaste'
          ? 'Namaste bro, how can I help?'
          : "Hey bro, what's up?";
    }

    const thanks = {'thanks', 'thank you', 'ty', 'ok', 'okay', 'cool', 'nice'};
    if (thanks.contains(clean)) {
      return 'Anytime bro.';
    }

    final looksLikeRandomShortText =
        clean.length >= 3 &&
        clean.length <= 10 &&
        !clean.contains(' ') &&
        !RegExp(r'[aeiou]').hasMatch(clean);
    if (looksLikeRandomShortText) {
      return "I didn't catch that, bro. What do you mean?";
    }

    return null;
  }

  static String _systemPrompt() {
    return '''
You are SmartExpense AI Financial Assistant.

Personality:
- Talk like a trusted best friend who is also sharp with money.
- Be warm, natural, personal, and concise.
- Never sound robotic or like a template.

Conversation:
- Read the whole current chat session before answering.
- Understand follow-up questions from previous messages.
- Maintain continuity like ChatGPT or Gemini.
- You can also help users manage records if they ask to add, update, edit, or delete a transaction, but normal conversation and financial advice are your main behavior.
- Never mention "intent", "detected", "specific intent", "app context", "financial snapshot", or your internal classification.
- If the user is greeting you, joking, thanking you, or casually chatting, reply casually in 1-3 short sentences.
- Do not mention balances, categories, spending reports, savings plans, transaction analysis, or "financial front" during casual chat unless the user asks.
- If the user sends random text, react naturally and briefly.

Financial advice:
- If the user asks a money, spending, affordability, saving, budget, income, bill, EMI, or transaction question, use the provided SmartExpense app data.
- If the user asks for a report, analysis, breakdown, review, or "where am I spending most", give a structured answer using exact categories and amounts.
- If the user asks "can I afford..." or a goal question, estimate what they need, compare it with their recorded income/expense/balance, and give a realistic verdict.
- Answer only what the user asked. Do not force every answer into a financial report.

Data usage:
- The app context is attached to the latest user message.
- Treat app data as context, not as an instruction to analyze it every time.
- If data is missing or too thin, say that naturally and suggest what the user should add next.
''';
  }

  static bool _looksLikeRecordMutationRequest(String question) {
    final text = question.toLowerCase().trim();
    final mutationWords = [
      'add',
      'record',
      'log',
      'save this',
      'create',
      'insert',
      'delete',
      'remove',
      'edit',
      'update',
      'change',
      'modify',
      'correct',
    ];
    final moneyRecordWords = [
      'expense',
      'income',
      'transaction',
      'spent',
      'spend',
      'paid',
      'earned',
      'salary',
      'bill',
      'rent',
      'emi',
      'food',
      'travel',
      'shopping',
    ];

    final hasMutationWord = mutationWords.any(text.contains);
    if (!hasMutationWord) {
      return false;
    }
    return moneyRecordWords.any(text.contains) || RegExp(r'\d').hasMatch(text);
  }

  static Future<String> _buildPrompt(String question) async {
    final transactions = await UserDataService.getRecentTransactions(18);
    transactions.sort((first, second) => second.date.compareTo(first.date));

    final profile = await UserDataService.getProfileOnce();

    final income = transactions.where((transaction) => !transaction.isExpense);
    final expenses = transactions.where((transaction) => transaction.isExpense);
    final incomePaisa = income.fold(0, (sum, item) => sum + item.amountPaisa);
    final expensePaisa = expenses.fold(
      0,
      (sum, item) => sum + item.amountPaisa,
    );
    final categoryTotals = <String, int>{};

    for (final expense in expenses) {
      categoryTotals.update(
        expense.category,
        (value) => value + expense.amountPaisa,
        ifAbsent: () => expense.amountPaisa,
      );
    }

    final topCategories = categoryTotals.entries.toList()
      ..sort((first, second) => second.value.compareTo(first.value));

    final recentTransactions = transactions
        .take(18)
        .map((transaction) {
          final type = transaction.isExpense ? 'Expense' : 'Income';
          final date = transaction.date.toIso8601String().split('T').first;
          return '- $type: ${transaction.title}, ${transaction.category}, ${MoneyUtils.formatPaisa(transaction.amountPaisa)}, $date';
        })
        .join('\n');

    final categories = topCategories
        .take(8)
        .map((entry) {
          return '- ${entry.key}: ${MoneyUtils.formatPaisa(entry.value)}';
        })
        .join('\n');

    final profileContext =
        '''
User profile:
- Name: ${profile?.name.trim().isNotEmpty == true ? profile!.name : 'Unknown'}
- Occupation: ${profile?.occupation.trim().isNotEmpty == true ? profile!.occupation : 'Unknown'}
- Address: ${profile?.address.trim().isNotEmpty == true ? profile!.address : 'Unknown'}
''';

    return '''
User message:
$question

$profileContext

Financial snapshot from SmartExpense:
- Total income recorded: ${MoneyUtils.formatPaisa(incomePaisa)}
- Total expenses recorded: ${MoneyUtils.formatPaisa(expensePaisa)}
- Current recorded balance: ${MoneyUtils.formatPaisa(incomePaisa - expensePaisa)}
- Transactions available: ${transactions.length}

Top spending categories:
${categories.isEmpty ? '- No expenses recorded yet' : categories}

Recent transactions:
${recentTransactions.isEmpty ? '- No transactions recorded yet' : recentTransactions}

Use this app context silently. Do not mention it unless it is relevant to the user's message. Reply directly to the user.
''';
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/categories/category_matcher.dart';
import '../core/models/ai_chat_message.dart';
import '../core/models/expense_model.dart';
import '../core/models/expense_category.dart';
import '../core/models/budget.dart';
import '../core/models/financial_insights.dart';
import '../core/models/financial_record_action.dart';
import '../core/secrets.dart';
import '../core/utils/money_utils.dart';
import 'category_service.dart';
import 'financial_insights_service.dart';
import 'user_data_service.dart';
import 'user_settings_service.dart';

class AiFinancialAssistantService {
  static const _uuid = Uuid();

  /// How many past messages to replay to the model. Enough for real follow-up
  /// continuity, bounded so a long chat cannot blow the context window.
  static const _historyWindow = 14;

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
- Return add/update/delete when the user wants their records changed.
- A plain statement of a completed transaction is an "add". "spent 500 on lunch",
  "got 45k salary", "paid 1200 rent" are all add actions — the user is telling
  their money app what happened.
- If the user asks for advice, analysis, reports, affordability, budgeting,
  saving tips, explanations, or casual chat, return actionType "none".
- A hypothetical or future amount is never an action: "if I spend 5000",
  "can I afford a 60000 bike", "planning to buy" are all "none".
- Do not treat advice questions as actions.
- For update/delete, choose targetId from the provided transactions if possible.
- If target is unclear, return actionType "clarify" with a short clarification.
- "category" MUST reuse one of the availableCategories names exactly when any
  of them fits, even loosely. Only invent a new category name when none of them
  could reasonably hold this transaction.
- Never invent a variant of a category that already exists (no "Food - Snacks"
  when "Food & Dining" is available).
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
    // The user approved this in the confirmation, so the category is created
    // before the transaction that needs it.
    if (action.createsCategory) {
      await CategoryService.create(
        name: action.newCategoryName!,
        kind: action.newCategoryIsExpense
            ? CategoryKind.expense
            : CategoryKind.income,
      );
    }

    switch (action.type) {
      case FinancialActionType.add:
        final next = action.newRecord;
        if (next == null) {
          throw Exception('Missing transaction details.');
        }
        await UserDataService.addTransaction(next);
        return 'Saved — ${next.isExpense ? 'expense' : 'income'} '
            '**${next.title}** for **${MoneyUtils.formatAmount(next.amount)}** '
            'under ${next.category}.';
      case FinancialActionType.update:
        final next = action.newRecord;
        final targetId = action.targetId;
        if (next == null || targetId == null || targetId.isEmpty) {
          throw Exception('Missing transaction update details.');
        }
        await UserDataService.updateTransaction(targetId, next);
        return 'Updated **${next.title}** — now '
            '${next.isExpense ? 'expense' : 'income'} of '
            '**${MoneyUtils.formatAmount(next.amount)}**.';
      case FinancialActionType.delete:
        final targetId = action.targetId;
        final old = action.oldRecord;
        if (targetId == null || targetId.isEmpty || old == null) {
          throw Exception('Missing transaction delete details.');
        }
        await UserDataService.deleteTransaction(targetId);
        return 'Deleted **${old.title}** '
            '(${MoneyUtils.formatAmount(old.amount)}).';
    }
  }

  static Future<String> ask({
    required String question,
    required List<AiChatMessage> history,
    FinancialInsights? insights,
  }) async {
    final localReply = _localCasualReply(question);
    if (localReply != null) {
      return localReply;
    }

    if (!Secrets.hasApiKey) {
      // The old wording sent people to edit secrets.dart, which does nothing —
      // the key is a compile-time define, so a build without it can never work
      // no matter what that file says.
      throw Exception(
        'This build has no API key compiled into it. Rebuild with:\n'
        'flutter run --dart-define-from-file=dart_defines.json',
      );
    }

    final brief = insights ?? await FinancialInsightsService.load();

    final payload = jsonEncode({
      'model': Secrets.groqModel,
      'messages': [
        {'role': 'system', 'content': _systemPrompt(brief)},
        for (final message in _replayHistory(history, question))
          {
            'role': message.role == 'user' ? 'user' : 'assistant',
            'content': message.content,
          },
        {'role': 'user', 'content': _buildPrompt(question, brief)},
      ],
      // Low enough that the numbers stay put, high enough to sound human.
      'temperature': 0.5,
      'max_tokens': 900,
    });

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.https('api.groq.com', '/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer ${Secrets.groqApiKey}',
              'Content-Type': 'application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 35));
    } on TimeoutException {
      throw Exception('The AI service took too long to answer. Try again.');
    } on SocketException {
      throw Exception('No internet connection reached the AI service.');
    } on http.ClientException catch (error) {
      // http wraps socket failures, so a dropped connection arrives here as a
      // ClientException rather than a SocketException.
      if (_looksLikeNetworkFailure(error.message)) {
        throw Exception('No internet connection reached the AI service.');
      }
      rethrow;
    }

    final data = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_describeApiFailure(response.statusCode, data));
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

    // Whatever the model called the category, resolve it against the user's
    // own vocabulary. The instruction to reuse an existing name is a request;
    // this is the guarantee.
    final resolution = await resolveCategory(
      rawName: merged.category,
      isExpense: merged.isExpense,
    );

    return FinancialActionParseResult(
      action: FinancialRecordAction(
        type: type,
        oldRecord: existing,
        newRecord: ExpenseModel(
          id: merged.id,
          title: merged.title,
          amount: merged.amount,
          category: resolution.resolvedName,
          date: merged.date,
          isExpense: merged.isExpense,
        ),
        targetId: targetId,
        newCategoryName: resolution.isNew ? resolution.resolvedName : null,
        newCategoryIsExpense: merged.isExpense,
      ),
    );
  }

  /// Resolves a free-text category name against the user's saved categories.
  ///
  /// Shared by the assistant and the quick-add box so both obey the same
  /// vocabulary.
  static Future<CategoryMatch> resolveCategory({
    required String rawName,
    required bool isExpense,
  }) async {
    var categories = await CategoryService.getOnce();
    if (categories.isEmpty) {
      categories = await CategoryService.ensureSeeded();
    }
    return CategoryMatcher.match(
      rawName: rawName,
      categories: categories,
      isExpense: isExpense,
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

    final categories = await CategoryService.getOnce();

    return jsonEncode({
      'latestUserMessage': question,
      'recentChat': recentChat,
      'transactions': recent,
      'availableCategories': [
        for (final category in categories)
          {'name': category.name, 'usedFor': category.kind.name},
      ],
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

  /// Drops the trailing copy of the question the caller is about to send as the
  /// final user turn, and keeps only the most recent slice of the chat.
  static List<AiChatMessage> _replayHistory(
    List<AiChatMessage> history,
    String question,
  ) {
    final replay = List<AiChatMessage>.from(history);
    // The chat screen appends the new user message before calling ask(), so
    // without this the model receives the same question twice.
    if (replay.isNotEmpty &&
        replay.last.role == 'user' &&
        replay.last.content.trim() == question.trim()) {
      replay.removeLast();
    }
    if (replay.length <= _historyWindow) {
      return replay;
    }
    return replay.sublist(replay.length - _historyWindow);
  }

  static String _systemPrompt(FinancialInsights insights) {
    return '''
You are the SmartExpense money friend.

WHO YOU ARE
You are the friend who happens to be sharp with money. Warm, plain-spoken,
on their side. You remember what they told you earlier in this chat. You are
not a chatbot, not a bank, and never a template.

But you are the honest kind of friend. When the numbers say they are in
trouble, you say it straight — no cheerleading, no burying it under three
compliments. A friend who only ever agrees with you is useless with money.

HOW FIRM TO BE RIGHT NOW
${insights.stance.directive}
This was decided from their actual figures, not guessed. Match it.

CONVERSATION
- Small talk gets small talk. A greeting, a joke, a thanks: reply in one or
  two short human lines and stop. Do not pivot to their finances uninvited.
- Answer the question they asked. Do not turn every reply into a full report.
- Follow-ups refer to earlier turns. Read them before answering.
- Never mention "context", "snapshot", "brief", "data provided", "intent", or
  anything about how you work. They are talking to a friend, not a system.

USING THE NUMBERS
- A FINANCIAL BRIEF is attached to the user's message. Every figure in it is
  already computed and exact.
- Never invent, estimate, or recompute a number. If a figure is not in the
  brief, say you do not have it rather than guessing.
- Quote real amounts and real category names when they make your point. Vague
  advice is worthless — "cut back on food" is noise, "Food is Rs. 6,200 this
  month, 50% of everything you spent" lands.
- When the brief lists CONCERNS, those are real and already verified. Raise
  the most important one rather than listing all of them.
- When it lists WINS, credit them specifically. People repeat what gets
  noticed.

GIVING ADVICE
- Lead with the answer or the verdict, not a preamble.
- One clear recommendation beats five vague ones. Name the single biggest
  lever and what it is worth in rupees.
- For "can I afford X": compare X against their balance, what they keep in a
  typical month, and what is already committed to recurring bills. Give a
  straight yes / no / yes-but-here-is-the-condition, with the arithmetic
  behind it.
- For goals ("save X by Y"): work out the monthly figure required, compare it
  with what they actually keep, and say whether it is realistic. If it is not,
  say so and give the number that would be.
- If the data is too thin to answer honestly, say that plainly and tell them
  what to record so you can answer next time. Never bluff.

FORMAT
- Short paragraphs. Markdown bold for key numbers. Bullets only for genuine
  lists.
- No headers or tables unless they asked for a report or breakdown.
- Keep it under roughly 200 words unless they asked for depth.
- Currency is Nepalese Rupees, written as Rs.
''';
  }

  /// True when the message is asking *about* money rather than reporting it.
  ///
  /// Without this, "should I send 5000 to mom?" matches a high-confidence
  /// relation rule in the parser and gets offered as a transaction to save,
  /// even though it is a question about something that has not happened.
  static bool looksLikeQuestionOrHypothetical(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.endsWith('?')) {
      return true;
    }

    const starters = [
      'can i',
      'can we',
      'could i',
      'should i',
      'shall i',
      'would it',
      'do i',
      'am i',
      'is it',
      'what',
      'how',
      'why',
      'when',
      'where',
      'which',
      'who',
    ];
    if (starters.any((starter) => lower.startsWith('$starter '))) {
      return true;
    }

    const hypothetical = [
      'afford',
      'planning to',
      'plan to',
      'thinking of',
      'thinking about',
      'want to buy',
      'wanna buy',
      'going to buy',
      'if i ',
      'suppose',
      'advice',
      'advise',
      'suggest',
      'recommend',
    ];
    return hypothetical.any(lower.contains);
  }

  /// Cheap gate before spending a network call on action classification.
  ///
  /// Deliberately permissive: a question that slips through only costs one
  /// classifier call that returns "none", whereas one that is wrongly filtered
  /// out means the user's "spent 500 on lunch" is never offered for saving.
  static bool _looksLikeRecordMutationRequest(String question) {
    final text = question.toLowerCase().trim();

    // Advice and analysis are never record mutations, however many numbers
    // they contain.
    if (looksLikeQuestionOrHypothetical(text)) {
      return false;
    }

    const analysisCues = [
      'report',
      'analys',
      'summary',
      'breakdown',
      'compare',
      'review',
    ];
    if (analysisCues.any(text.contains)) {
      return false;
    }

    const mutationWords = [
      'add',
      'record',
      'log',
      'save',
      'create',
      'insert',
      'delete',
      'remove',
      'edit',
      'update',
      'change',
      'modify',
      'correct',
      'move',
      'mark',
    ];
    if (mutationWords.any(text.contains)) {
      return true;
    }

    // A plain statement of fact with an amount — "spent 500 on lunch",
    // "got 45k salary" — is someone telling their friend what happened, and
    // almost always wants recording.
    const statementWords = [
      'spent',
      'spend',
      'paid',
      'bought',
      'earned',
      'received',
      'got',
      'gave',
      'sent',
      'salary',
      'income',
      'expense',
      'transaction',
    ];
    final hasAmount = RegExp(r'\d').hasMatch(text);
    return hasAmount && statementWords.any(text.contains);
  }

  /// Renders the computed figures as a compact brief.
  ///
  /// Everything here is already exact, so the model only has to choose what to
  /// say. The previous version summed a 18-row slice and labelled it "Total
  /// income recorded", which quietly made every total and every affordability
  /// verdict wrong for anyone with more history than that.
  static String _buildPrompt(String question, FinancialInsights insights) {
    if (!insights.hasData) {
      return '''
User message:
$question

FINANCIAL BRIEF
No transactions recorded yet, so there is nothing to analyse. If they ask
anything about their money, say plainly that you need some entries first and
suggest they log a few days of spending or their latest income.
''';
    }

    final buffer = StringBuffer()
      ..writeln('User message:')
      ..writeln(question)
      ..writeln()
      ..writeln('FINANCIAL BRIEF (exact, already computed — never recalculate)')
      ..writeln('Today: ${_isoDate(insights.generatedAt)}');

    final since = insights.earliestDate;
    buffer
      ..writeln(
        'All time across ${insights.transactionCount} transactions'
        '${since == null ? '' : ' since ${_isoDate(since)}'}:',
      )
      ..writeln('  Income ${_money(insights.totalIncomePaisa)}')
      ..writeln('  Spent ${_money(insights.totalExpensePaisa)}')
      ..writeln('  Balance ${_money(insights.balancePaisa)}')
      ..writeln();

    buffer
      ..writeln('This month (${_monthName(insights.thisMonth.month)}):')
      ..writeln(
        '  Income ${_money(insights.thisMonth.incomePaisa)}, '
        'spent ${_money(insights.thisMonth.expensePaisa)}, '
        'difference ${_money(insights.thisMonth.netPaisa)}'
        '${_ratePart(insights.thisMonth.savingsRate)}',
      )
      ..writeln('Last month (${_monthName(insights.lastMonth.month)}):')
      ..writeln(
        '  Income ${_money(insights.lastMonth.incomePaisa)}, '
        'spent ${_money(insights.lastMonth.expensePaisa)}, '
        'difference ${_money(insights.lastMonth.netPaisa)}'
        '${_ratePart(insights.lastMonth.savingsRate)}',
      );

    final spendingChange = insights.spendingChangeRatio;
    if (spendingChange != null) {
      final direction = spendingChange >= 0 ? 'up' : 'down';
      buffer.writeln(
        '  Spending is $direction '
        '${(spendingChange.abs() * 100).round()}% vs last month.',
      );
    }
    buffer.writeln();

    buffer.writeln(
      'Pace: ${_money(insights.dailyBurnRoundedPaisa)} per day over the last '
      '30 days.',
    );
    final projected = insights.projectedMonthEndExpensePaisa;
    if (projected != null) {
      buffer.writeln(
        '  At this pace this month ends near ${_money(projected)} spent.',
      );
    }
    final runway = insights.runwayDays;
    if (runway != null) {
      buffer.writeln(
        '  Current balance covers about $runway more days at that pace.',
      );
    }
    if (insights.committedMonthlyPaisa > 0) {
      buffer.writeln(
        '  Already committed every month to recurring items: '
        '${_money(insights.committedMonthlyPaisa)}.',
      );
    }
    buffer.writeln();

    if (insights.topCategories.isNotEmpty) {
      buffer.writeln('Where this month went:');
      for (final category in insights.topCategories.take(6)) {
        final change = category.changeRatio;
        final trend = category.isNew
            ? ', new this month'
            : change == null
            ? ''
            : ', ${change >= 0 ? 'up' : 'down'} '
                  '${(change.abs() * 100).round()}% vs last month';
        buffer.writeln(
          '  - ${category.label}: ${_money(category.paisa)} '
          '(${(category.share * 100).round()}% of spending$trend)',
        );
      }
      buffer.writeln();
    }

    if (insights.biggestExpensesThisMonth.isNotEmpty) {
      buffer.writeln('Biggest single expenses this month:');
      for (final expense in insights.biggestExpensesThisMonth) {
        buffer.writeln(
          '  - ${expense.title}: ${_money(expense.amountPaisa)} '
          'on ${_isoDate(expense.date)} (${expense.category})',
        );
      }
      buffer.writeln();
    }

    if (insights.upcoming.isNotEmpty) {
      buffer.writeln('Due in the next 14 days:');
      for (final item in insights.upcoming) {
        buffer.writeln(
          '  - ${item.title}: ${_money(item.paisa)} '
          'on ${_isoDate(item.dueDate)} (${item.source})',
        );
      }
      buffer.writeln();
    }

    if (insights.budgets.isNotEmpty) {
      buffer.writeln('Budgets they set for this month:');
      for (final progress in insights.budgets) {
        final state = switch (progress.health) {
          BudgetHealth.over => 'OVER',
          BudgetHealth.atRisk => 'on track to go over',
          BudgetHealth.tight => 'tight',
          BudgetHealth.comfortable => 'comfortable',
        };
        buffer.writeln(
          '  - ${progress.budget.label}: '
          '${_money(progress.spentPaisa)} of ${_money(progress.limitPaisa)} '
          '(${(progress.ratio * 100).round()}%, $state, '
          'projected ${_money(progress.projectedPaisa)} by month end)',
        );
      }
      buffer
        ..writeln(
          'These are limits the user chose. Hold them to these rather than '
          'inventing new ones, and never suggest a budget for something they '
          'have already capped.',
        )
        ..writeln();
    }

    if (insights.concerns.isNotEmpty) {
      buffer.writeln('CONCERNS (verified, raise the most important one):');
      for (final concern in insights.concerns) {
        buffer.writeln('  - $concern');
      }
      buffer.writeln();
    }

    if (insights.wins.isNotEmpty) {
      buffer.writeln('WINS (credit these specifically):');
      for (final win in insights.wins) {
        buffer.writeln('  - $win');
      }
      buffer.writeln();
    }

    buffer.writeln(
      'Reply to the user directly. Reference the brief only where it '
      'genuinely helps their question.',
    );

    return buffer.toString();
  }

  /// Recognises the wording the platform uses for a dropped connection.
  static bool _looksLikeNetworkFailure(String message) {
    const markers = [
      'Failed host lookup',
      'SocketException',
      'SocketFailed',
      'No address associated',
      'Connection refused',
      'Network is unreachable',
    ];
    return markers.any(message.contains);
  }

  /// Turns an API failure into something the user can act on.
  ///
  /// A raw provider message like "model_decommissioned" tells the user nothing
  /// about what to do next, and every failure previously surfaced as the same
  /// generic "AI request failed".
  static String _describeApiFailure(int statusCode, dynamic data) {
    final error = data is Map ? data['error'] : null;
    final raw = error is Map
        ? error['message']?.toString() ?? ''
        : data.toString();
    final code = error is Map ? error['code']?.toString() ?? '' : '';
    final lower = '$raw $code'.toLowerCase();

    if (statusCode == 401 || statusCode == 403) {
      return 'The API key was rejected. It may be revoked or mistyped — '
          'check it at console.groq.com and rebuild.';
    }
    if (statusCode == 429) {
      return 'Rate limit reached on the AI service. Wait a moment and retry.';
    }
    if (lower.contains('decommission') ||
        lower.contains('deprecated') ||
        lower.contains('does not exist') ||
        lower.contains('model_not_found')) {
      return 'The model "${Secrets.groqModel}" is no longer available. '
          'Set a current one with --dart-define=GROQ_MODEL=...\n\n$raw';
    }
    if (statusCode >= 500) {
      return 'The AI service had a problem on its side ($statusCode). '
          'Try again shortly.';
    }
    return 'AI request failed ($statusCode): '
        '${raw.isEmpty ? 'no details returned' : raw}';
  }

  static String _money(int paisa) => MoneyUtils.formatPaisa(paisa);

  static String _isoDate(DateTime date) {
    return date.toIso8601String().split('T').first;
  }

  static String _ratePart(double? rate) {
    if (rate == null) return '';
    return ' (${(rate * 100).round()}% of income kept)';
  }

  static String _monthName(DateTime month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${names[month.month - 1]} ${month.year}';
  }
}

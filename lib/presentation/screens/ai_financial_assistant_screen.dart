import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/ai_chat_message.dart';
import '../../../core/models/expense_category.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/models/financial_insights.dart';
import '../../../core/models/financial_record_action.dart';
import '../../../core/parser/transaction_parser_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_utils.dart';
import '../../../services/ai_financial_assistant_service.dart';
import '../../../services/category_service.dart';
import '../../../services/financial_insights_service.dart';
import '../../../services/user_data_service.dart';
import '../../../services/user_settings_service.dart';

class AiFinancialAssistantScreen extends StatefulWidget {
  const AiFinancialAssistantScreen({super.key});

  @override
  State<AiFinancialAssistantScreen> createState() =>
      _AiFinancialAssistantScreenState();
}

class _AiFinancialAssistantScreenState
    extends State<AiFinancialAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  AiChatSession? _session;
  var _messages = <AiChatMessage>[];
  var _isSending = false;
  var _isBooting = true;

  /// Cached so the header can show live status and the model always reasons
  /// about the same figures the user can see.
  FinancialInsights? _insights;

  /// Kept so a failed turn can be retried without retyping.
  String? _lastFailedQuestion;

  /// Held explicitly rather than via StreamBuilder.
  ///
  /// A StreamBuilder in build() rebuilt its stream on every build, and its
  /// listener compared message Lists by identity, so each emission scheduled a
  /// setState that caused another build, another stream and another emission —
  /// an endless rebuild loop. Its stale queued callbacks also raced with
  /// session switching, which is why "New chat" appeared to do nothing.
  StreamSubscription<AiChatSession?>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _startFreshSession();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startFreshSession() async {
    final session = await AiFinancialAssistantService.createStartupSession();
    if (!mounted) return;
    _adoptSession(session, isBooting: false);
    _refreshInsights();
  }

  /// Makes [session] current and listens to just that session's document.
  void _adoptSession(AiChatSession session, {bool? isBooting}) {
    setState(() {
      _session = session;
      _messages = session.messages;
      if (isBooting != null) {
        _isBooting = isBooting;
      }
    });

    _sessionSubscription?.cancel();
    _sessionSubscription = UserSettingsService.aiSessionStream(session.id)
        .listen((remote) {
          if (!mounted || remote == null) return;
          // Ignore late emissions from a session the user has moved on from,
          // and never fight the in-flight turn for control of the list.
          if (_isSending || remote.id != _session?.id) return;
          if (_sameMessages(remote.messages, _messages)) return;
          setState(() {
            _session = remote;
            _messages = remote.messages;
          });
        });
  }

  /// Compares by content, not by list identity.
  static bool _sameMessages(List<AiChatMessage> a, List<AiChatMessage> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id ||
          a[index].content != b[index].content) {
        return false;
      }
    }
    return true;
  }

  Future<void> _refreshInsights() async {
    try {
      final insights = await FinancialInsightsService.load();
      if (mounted) {
        setState(() => _insights = insights);
      }
    } catch (_) {
      // The chat still works without the header summary.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isBooting || _session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _AssistantHeader(
          session: _session!,
          insights: _insights,
          onHistory: _showChatHistory,
          onNewChat: _newChat,
        ),
        Expanded(
          child: _messages.isEmpty
              ? _EmptyAssistantState(
                  insights: _insights,
                  onPrompt: _sendSuggestion,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.pageGutter,
                    AppTokens.gapSm,
                    AppTokens.pageGutter,
                    AppTokens.gapMd,
                  ),
                  itemCount: _messages.length + (_isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _messages.length) {
                      return const _TypingBubble();
                    }
                    final message = _messages[index];
                    final isLast = index == _messages.length - 1;
                    return _ChatBubble(
                      message: message,
                      showRetry:
                          isLast &&
                          message.role != 'user' &&
                          _lastFailedQuestion != null,
                      onRetry: _retryLast,
                    );
                  },
                ),
        ),
        _Composer(
          controller: _controller,
          isSending: _isSending,
          onSend: _sendMessage,
        ),
      ],
    );
  }

  Future<void> _sendSuggestion(String question) async {
    _controller.text = question;
    await _sendMessage();
  }

  Future<void> _retryLast() async {
    final question = _lastFailedQuestion;
    if (question == null || _isSending) return;
    _controller.text = question;
    setState(() => _lastFailedQuestion = null);
    await _sendMessage();
  }

  Future<void> _sendMessage() async {
    final session = _session;
    final text = _controller.text.trim();
    if (session == null || text.isEmpty || _isSending) {
      return;
    }

    final userMessage = AiFinancialAssistantService.userMessage(text);
    final nextMessages = [..._messages, userMessage];
    _controller.clear();
    setState(() {
      _messages = nextMessages;
      _isSending = true;
      _lastFailedQuestion = null;
    });
    await AiFinancialAssistantService.saveMessages(session.id, nextMessages);
    _scrollToBottom();

    try {
      // Fast local path: a clear "amount + direction" statement becomes a
      // proposed record. It still goes through confirmation — this used to
      // save silently, which meant a misparse wrote a wrong number into the
      // ledger with nothing to undo it.
      //
      // Questions are excluded first: "should I send 5000 to mom?" matches a
      // high-confidence relation rule, but it is asking about a transfer, not
      // reporting one.
      final isQuestion =
          AiFinancialAssistantService.looksLikeQuestionOrHypothetical(text);
      final parsed = isQuestion
          ? null
          : await TransactionParserService().parse(text);
      if (parsed != null &&
          parsed.type != TransactionType.unknown &&
          parsed.amount > 0 &&
          parsed.confidence >= 0.85 &&
          mounted) {
        final isExpense = parsed.type == TransactionType.expense;
        // Route the rule-based guess through the same vocabulary the
        // assistant uses, so both paths agree on category names.
        final resolution = await AiFinancialAssistantService.resolveCategory(
          rawName: parsed.category,
          isExpense: isExpense,
        );
        final proposal = ExpenseModel(
          id: const Uuid().v4(),
          title: parsed.title,
          amount: parsed.amount,
          category: resolution.resolvedName,
          date: DateTime.now(),
          isExpense: isExpense,
        );
        final action = FinancialRecordAction(
          type: FinancialActionType.add,
          newRecord: proposal,
          newCategoryName: resolution.isNew ? resolution.resolvedName : null,
          newCategoryIsExpense: isExpense,
        );
        final confirmed = await _confirmFinancialAction(action);

        if (confirmed) {
          if (action.createsCategory) {
            await CategoryService.create(
              name: action.newCategoryName!,
              kind: isExpense ? CategoryKind.expense : CategoryKind.income,
            );
          }
          await UserDataService.addTransaction(proposal);
          await _reply(
            session.id,
            nextMessages,
            'Saved — ${proposal.isExpense ? 'expense' : 'income'} '
            '**${proposal.title}** for '
            '**${MoneyUtils.formatAmount(proposal.amount)}** '
            'under ${proposal.category}.',
          );
          _refreshInsights();
        } else {
          await _reply(
            session.id,
            nextMessages,
            'No problem, I did not save it. Tell me the right details and '
            'I will log it properly.',
          );
        }
        return;
      }

      final actionResult =
          await AiFinancialAssistantService.detectFinancialAction(
            question: text,
            history: nextMessages,
          );

      if (actionResult.clarification != null) {
        await _reply(session.id, nextMessages, actionResult.clarification!);
        return;
      }

      final action = actionResult.action;
      if (action != null) {
        if (!mounted) return;
        final confirmed = await _confirmFinancialAction(action);
        final response = confirmed
            ? await AiFinancialAssistantService.executeFinancialAction(action)
            : 'Cancelled — nothing in your records changed.';
        await _reply(session.id, nextMessages, response);
        if (confirmed) {
          _refreshInsights();
        }
        return;
      }

      final answer = await AiFinancialAssistantService.ask(
        question: text,
        history: nextMessages,
        insights: _insights,
      );
      await _reply(session.id, nextMessages, answer);
    } catch (error) {
      _lastFailedQuestion = text;
      await _reply(
        session.id,
        nextMessages,
        'I could not reach the AI service just now.\n\n'
        '${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) {
        final freshSession =
            await AiFinancialAssistantService.getSession(session.id) ?? session;
        setState(() {
          _session = freshSession;
          _messages = freshSession.messages;
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _reply(
    String sessionId,
    List<AiChatMessage> baseMessages,
    String content,
  ) async {
    final assistantMessage = AiFinancialAssistantService.assistantMessage(
      content,
    );
    final updated = [...baseMessages, assistantMessage];
    await AiFinancialAssistantService.saveMessages(sessionId, updated);
    if (mounted) {
      setState(() => _messages = updated);
    }
  }

  Future<bool> _confirmFinancialAction(FinancialRecordAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _FinancialActionDialog(action: action),
    );
    return confirmed == true;
  }

  Future<void> _newChat() async {
    final session = await AiFinancialAssistantService.createSession();
    if (!mounted) return;
    _adoptSession(session);
    _refreshInsights();
  }

  Future<void> _switchSession(AiChatSession session) async {
    await AiFinancialAssistantService.setActiveSession(session.id);
    final freshSession = await AiFinancialAssistantService.getSession(
      session.id,
    );
    if (!mounted || freshSession == null) return;
    _adoptSession(freshSession);
    _scrollToBottom();
  }

  Future<void> _deleteSession(AiChatSession session) async {
    await AiFinancialAssistantService.deleteSession(session.id);
    final activeId = await AiFinancialAssistantService.getActiveSessionId();
    final activeSession = activeId == null
        ? null
        : await AiFinancialAssistantService.getSession(activeId);
    if (!mounted) return;
    if (activeSession != null) {
      _adoptSession(activeSession);
    } else {
      final newSession = await AiFinancialAssistantService.createSession();
      if (!mounted) return;
      _adoptSession(newSession);
    }
  }

  Future<void> _showChatHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return _ChatHistorySheet(
          activeSessionId: _session?.id,
          onNewChat: () async {
            Navigator.of(context).pop();
            await _newChat();
          },
          onSelect: (session) async {
            Navigator.of(context).pop();
            await _switchSession(session);
          },
          onDelete: _deleteSession,
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }
}

class _AssistantHeader extends StatelessWidget {
  final AiChatSession session;
  final FinancialInsights? insights;
  final VoidCallback onHistory;
  final VoidCallback onNewChat;

  const _AssistantHeader({
    required this.session,
    required this.insights,
    required this.onHistory,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.pageGutter,
            AppTokens.gapLg,
            AppTokens.gapSm,
            AppTokens.gapSm,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppTokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AI Assistant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      session.title == 'New chat'
                          ? 'New conversation'
                          : session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Chat history',
                onPressed: onHistory,
                icon: const Icon(Icons.history_rounded),
              ),
              IconButton(
                tooltip: 'New chat',
                onPressed: onNewChat,
                icon: const Icon(Icons.add_comment_rounded),
              ),
            ],
          ),
        ),
        if (insights != null && insights!.hasData)
          _InsightStrip(insights: insights!),
      ],
    );
  }
}

/// Live status line so the user can see the same figures the assistant is
/// reasoning about, rather than having to take its word for them.
class _InsightStrip extends StatelessWidget {
  final FinancialInsights insights;

  const _InsightStrip({required this.insights});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stance = insights.stance;
    final accent = switch (stance) {
      CoachStance.strict => colorScheme.appExpense,
      CoachStance.watchful => colorScheme.appWarning,
      CoachStance.encouraging => colorScheme.appIncome,
      CoachStance.calm => colorScheme.primary,
    };
    final icon = switch (stance) {
      CoachStance.strict => Icons.error_outline_rounded,
      CoachStance.watchful => Icons.warning_amber_rounded,
      CoachStance.encouraging => Icons.trending_up_rounded,
      CoachStance.calm => Icons.check_circle_outline_rounded,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.pageGutter,
        0,
        AppTokens.pageGutter,
        AppTokens.gapSm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.gapMd,
        vertical: AppTokens.gapSm,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: AppTokens.gapSm),
          Expanded(
            child: Text(
              insights.headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.gapSm),
          Text(
            'Balance ${MoneyUtils.formatCompactPaisa(insights.balancePaisa)}',
            maxLines: 1,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gapMd,
        AppTokens.gapSm,
        AppTokens.gapMd,
        AppTokens.gapMd,
      ),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        border: Border(top: BorderSide(color: colorScheme.appBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask, or just say what you spent...',
                  prefixIcon: Icon(Icons.auto_awesome_rounded),
                ),
              ),
            ),
            const SizedBox(width: AppTokens.gapSm),
            SizedBox(
              width: 48,
              height: 48,
              child: FilledButton(
                onPressed: isSending ? null : onSend,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                child: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatHistorySheet extends StatelessWidget {
  final String? activeSessionId;
  final VoidCallback onNewChat;
  final ValueChanged<AiChatSession> onSelect;
  final ValueChanged<AiChatSession> onDelete;

  const _ChatHistorySheet({
    required this.activeSessionId,
    required this.onNewChat,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gapLg,
          0,
          AppTokens.gapLg,
          AppTokens.gapLg,
        ),
        child: FutureBuilder<List<AiChatSession>>(
          future: AiFinancialAssistantService.getSessions(),
          builder: (context, snapshot) {
            final sessions = snapshot.data ?? const [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chat History',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onNewChat,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New'),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.gapMd),
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.gapXl,
                    ),
                    child: Text(
                      'No saved chats yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppTokens.gapSm),
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final isActive = session.id == activeSessionId;
                        return Material(
                          color: isActive
                              ? colorScheme.primary.withValues(alpha: 0.10)
                              : colorScheme.appCard,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusMd,
                            ),
                            side: BorderSide(
                              color: isActive
                                  ? colorScheme.primary
                                  : colorScheme.appBorder,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            onTap: () => onSelect(session),
                            leading: Icon(
                              isActive
                                  ? Icons.chat_bubble_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              color: colorScheme.primary,
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${session.messages.length} message'
                              '${session.messages.length == 1 ? '' : 's'} • '
                              '${_dateLabel(session.updatedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete chat',
                              onPressed: () => onDelete(session),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class _FinancialActionDialog extends StatelessWidget {
  final FinancialRecordAction action;

  const _FinancialActionDialog({required this.action});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDelete = action.type == FinancialActionType.delete;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _iconForAction(),
            color: isDelete ? colorScheme.error : colorScheme.primary,
          ),
          const SizedBox(width: AppTokens.gapSm),
          Expanded(child: Text('${_actionLabel()} this?')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (action.createsCategory) ...[
              _NewCategoryNotice(name: action.newCategoryName!),
              const SizedBox(height: AppTokens.gapMd),
            ],
            if (action.type == FinancialActionType.add &&
                action.newRecord != null)
              _RecordDetails(record: action.newRecord!),
            if (action.type == FinancialActionType.delete &&
                action.oldRecord != null)
              _RecordDetails(record: action.oldRecord!),
            if (action.type == FinancialActionType.update &&
                action.oldRecord != null &&
                action.newRecord != null)
              _ChangeDetails(
                oldRecord: action.oldRecord!,
                newRecord: action.newRecord!,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDelete
              ? FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                )
              : null,
          child: Text(_actionLabel()),
        ),
      ],
    );
  }

  String _actionLabel() {
    return switch (action.type) {
      FinancialActionType.add => 'Save',
      FinancialActionType.update => 'Update',
      FinancialActionType.delete => 'Delete',
    };
  }

  IconData _iconForAction() {
    return switch (action.type) {
      FinancialActionType.add => Icons.add_circle_outline_rounded,
      FinancialActionType.update => Icons.edit_note_rounded,
      FinancialActionType.delete => Icons.delete_outline_rounded,
    };
  }
}

class _RecordDetails extends StatelessWidget {
  final ExpenseModel record;

  const _RecordDetails({required this.record});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = record.isExpense
        ? colorScheme.appExpense
        : colorScheme.appIncome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppTokens.gapMd),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                record.isExpense ? 'Expense' : 'Income',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: AppTokens.gapXs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  MoneyUtils.formatAmount(record.amount),
                  maxLines: 1,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gapMd),
        _DetailRow(label: 'Title', value: record.title),
        _DetailRow(label: 'Category', value: record.category),
        _DetailRow(label: 'Date', value: _dateLabel(record.date)),
      ],
    );
  }
}

class _ChangeDetails extends StatelessWidget {
  final ExpenseModel oldRecord;
  final ExpenseModel newRecord;

  const _ChangeDetails({required this.oldRecord, required this.newRecord});

  @override
  Widget build(BuildContext context) {
    final changes = <_ChangeRow>[
      _ChangeRow(
        label: 'Type',
        oldValue: oldRecord.isExpense ? 'Expense' : 'Income',
        newValue: newRecord.isExpense ? 'Expense' : 'Income',
      ),
      _ChangeRow(
        label: 'Title',
        oldValue: oldRecord.title,
        newValue: newRecord.title,
      ),
      _ChangeRow(
        label: 'Amount',
        oldValue: MoneyUtils.formatAmount(oldRecord.amount),
        newValue: MoneyUtils.formatAmount(newRecord.amount),
      ),
      _ChangeRow(
        label: 'Category',
        oldValue: oldRecord.category,
        newValue: newRecord.category,
      ),
      _ChangeRow(
        label: 'Date',
        oldValue: _dateLabel(oldRecord.date),
        newValue: _dateLabel(newRecord.date),
      ),
    ].where((row) => row.hasChanged).toList();

    if (changes.isEmpty) {
      return const Text('No visible changes detected.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: changes,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.gapSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final String label;
  final String oldValue;
  final String newValue;

  const _ChangeRow({
    required this.label,
    required this.oldValue,
    required this.newValue,
  });

  bool get hasChanged => oldValue != newValue;

  @override
  Widget build(BuildContext context) {
    if (!hasChanged) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.gapSm),
      padding: const EdgeInsets.all(AppTokens.gapMd),
      decoration: BoxDecoration(
        color: colorScheme.appCardMuted,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppTokens.gapXs),
          Row(
            children: [
              Flexible(
                child: Text(
                  oldValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.gapSm),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTokens.gapSm),
              Flexible(
                child: Text(
                  newValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _dateLabel(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

class _EmptyAssistantState extends StatelessWidget {
  final FinancialInsights? insights;
  final ValueChanged<String> onPrompt;

  const _EmptyAssistantState({required this.insights, required this.onPrompt});

  /// Suggestions follow the user's actual situation instead of being a fixed
  /// list, so the first tap already asks something worth answering.
  List<String> _prompts() {
    final data = insights;
    if (data == null || !data.hasData) {
      return const [
        'How should I start tracking my money?',
        'What should I record first?',
        'Explain how to budget on a small income',
      ];
    }

    final prompts = <String>[];
    if (data.stance == CoachStance.strict) {
      prompts.add('Why am I overspending, and what do I cut first?');
    }
    final top = data.topCategories.isNotEmpty
        ? data.topCategories.first.label
        : null;
    if (top != null) {
      prompts.add('How do I cut my $top spending?');
    }
    prompts.addAll([
      'Give me a straight review of this month',
      'How much can I safely save each month?',
      'Can I afford a Rs. 60,000 laptop?',
    ]);
    return prompts.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final data = insights;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.pageGutter,
        AppTokens.gapLg,
        AppTokens.pageGutter,
        AppTokens.gapXl,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
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
              Icon(Icons.auto_awesome_rounded, color: colorScheme.appOnHero),
              const SizedBox(height: AppTokens.gapMd),
              Text(
                'Ask anything about your money.',
                style: TextStyle(
                  color: colorScheme.appOnHero,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.gapXs + 2),
              Text(
                data != null && data.hasData
                    ? 'I can see all ${data.transactionCount} of your '
                          'transactions. I will be straight with you about '
                          'what they say.'
                    : 'Tell me what you spent and I will log it. Ask me '
                          'anything and I will be straight with you.',
                style: TextStyle(
                  color: colorScheme.appOnHero.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (data != null && data.hasData) ...[
          const SizedBox(height: AppTokens.gapLg),
          _BriefingCard(insights: data),
        ],
        const SizedBox(height: AppTokens.gapLg),
        for (final prompt in _prompts()) ...[
          _PromptTile(prompt: prompt, onTap: () => onPrompt(prompt)),
          const SizedBox(height: AppTokens.gapSm),
        ],
      ],
    );
  }
}

/// The month at a glance, computed locally.
///
/// Everything here is exact arithmetic over the user's own records, so it is
/// correct and available even before the assistant makes a single API call.
class _BriefingCard extends StatelessWidget {
  final FinancialInsights insights;

  const _BriefingCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final month = insights.thisMonth;
    final note = insights.concerns.isNotEmpty
        ? insights.concerns.first
        : insights.wins.isNotEmpty
        ? insights.wins.first
        : null;
    final isConcern = insights.concerns.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapLg),
      decoration: BoxDecoration(
        color: colorScheme.appCard,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: colorScheme.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This month so far',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 11,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppTokens.gapMd),
          Row(
            children: [
              _Figure(
                label: 'Came in',
                paisa: month.incomePaisa,
                color: colorScheme.appIncome,
              ),
              _Figure(
                label: 'Went out',
                paisa: month.expensePaisa,
                color: colorScheme.appExpense,
              ),
              _Figure(
                label: 'Difference',
                paisa: month.netPaisa,
                color: month.netPaisa < 0
                    ? colorScheme.appExpense
                    : colorScheme.primary,
              ),
            ],
          ),
          if (insights.dailyBurnPaisa > 0) ...[
            const SizedBox(height: AppTokens.gapMd),
            Text(
              'Averaging '
              '${MoneyUtils.formatPaisa(insights.dailyBurnRoundedPaisa)} '
              'a day over the last 30 days.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: AppTokens.gapMd),
            Container(
              padding: const EdgeInsets.all(AppTokens.gapMd),
              decoration: BoxDecoration(
                color:
                    (isConcern
                            ? colorScheme.appWarning
                            : colorScheme.appIncome)
                        .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isConcern
                        ? Icons.priority_high_rounded
                        : Icons.celebration_rounded,
                    size: 16,
                    color: isConcern
                        ? colorScheme.appWarning
                        : colorScheme.appIncome,
                  ),
                  const SizedBox(width: AppTokens.gapSm),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final int paisa;
  final Color color;

  const _Figure({
    required this.label,
    required this.paisa,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                MoneyUtils.formatCompactPaisa(paisa),
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptTile extends StatelessWidget {
  final String prompt;
  final VoidCallback onTap;

  const _PromptTile({required this.prompt, required this.onTap});

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
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.bolt_rounded, color: colorScheme.primary),
        title: Text(prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final AiChatMessage message;
  final bool showRetry;
  final VoidCallback onRetry;

  const _ChatBubble({
    required this.message,
    this.showRetry = false,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: message.content));
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: AppTokens.gapXs),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.gapMd,
                  vertical: AppTokens.gapMd,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? colorScheme.primary
                      : colorScheme.appCardMuted,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(AppTokens.radiusMd),
                    topRight: const Radius.circular(AppTokens.radiusMd),
                    bottomLeft: Radius.circular(isUser ? AppTokens.radiusMd : 4),
                    bottomRight: Radius.circular(
                      isUser ? 4 : AppTokens.radiusMd,
                    ),
                  ),
                ),
                child: isUser
                    ? Text(
                        message.content,
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : MarkdownBody(
                        data: message.content,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            height: 1.45,
                          ),
                          strong: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                          listBullet: TextStyle(color: colorScheme.onSurface),
                          h1: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          h2: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          h3: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 4,
                right: 4,
                bottom: AppTokens.gapMd,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeLabel(message.createdAt),
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showRetry) ...[
                    const SizedBox(width: AppTokens.gapSm),
                    InkWell(
                      onTap: onRetry,
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 12,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Retry',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _timeLabel(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'am' : 'pm'}';
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTokens.gapMd),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.gapLg,
          vertical: AppTokens.gapMd,
        ),
        decoration: BoxDecoration(
          color: colorScheme.appCardMuted,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTokens.radiusMd),
            topRight: Radius.circular(AppTokens.radiusMd),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(AppTokens.radiusMd),
          ),
        ),
        child: const SizedBox(
          width: 46,
          child: LinearProgressIndicator(minHeight: 3),
        ),
      ),
    );
  }
}

/// Flags that confirming will also add a category the user does not have.
class _NewCategoryNotice extends StatelessWidget {
  final String name;

  const _NewCategoryNotice({required this.name});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.gapMd),
      decoration: BoxDecoration(
        color: colorScheme.appWarning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: colorScheme.appWarning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.new_label_rounded, size: 16, color: colorScheme.appWarning),
          const SizedBox(width: AppTokens.gapSm),
          Expanded(
            child: Text(
              'Creates a new category: $name',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

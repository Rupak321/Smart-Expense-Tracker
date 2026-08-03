import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/ai_chat_message.dart';
import '../../../core/models/expense_model.dart';
import '../../../core/models/financial_record_action.dart';
import '../../../core/utils/money_utils.dart';
import '../../../core/parser/transaction_parser_service.dart';
import '../../../services/ai_financial_assistant_service.dart';
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

  @override
  void initState() {
    super.initState();
    _startFreshSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startFreshSession() async {
    final session = await AiFinancialAssistantService.createStartupSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = session;
      _messages = session.messages;
      _isBooting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isBooting || _session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _AssistantHeader(
          session: _session!,
          onHistory: _showChatHistory,
          onNewChat: _newChat,
        ),
      
        Expanded(
          child: StreamBuilder<AiChatSession?>(
            stream: _session != null
                ? UserSettingsService.aiSessionStream(_session!.id)
                : const Stream<AiChatSession?>.empty(),
            builder: (context, snapshot) {
              if (snapshot.hasData && !_isSending) {
                final sessionData = snapshot.data!;
                if (_session == null ||
                    _session!.messages != sessionData.messages) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _session = sessionData;
                      _messages = sessionData.messages;
                    });
                  });
                }
              }

              if (_messages.isEmpty) {
                return _EmptyAssistantState(onPrompt: _sendSuggestion);
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                itemCount: _messages.length + (_isSending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _messages.length) {
                    return const _TypingBubble();
                  }
                  return _ChatBubble(message: _messages[index]);
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outline)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Ask your finance advisor...',
                      prefixIcon: Icon(Icons.auto_awesome_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isSending ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSending
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
        ),
      ],
    );
  }

  Future<void> _sendSuggestion(String question) async {
    _controller.text = question;
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
    });
    await AiFinancialAssistantService.saveMessages(session.id, nextMessages);
    _scrollToBottom();

    try {
      final parser = TransactionParserService();
      final parsed = await parser.parse(text);
      if (parsed.type != TransactionType.unknown && parsed.confidence >= 0.85) {
        final newExpense = ExpenseModel(
          id: Uuid().v4(),
          title: parsed.title,
          amount: parsed.amount,
          category: parsed.category,
          date: DateTime.now(),
          isExpense: parsed.type == TransactionType.expense,
        );
        await UserDataService.addTransaction(newExpense);
        final assistantMessage = AiFinancialAssistantService.assistantMessage(
          'Saved ${parsed.type == TransactionType.expense ? 'expense' : 'income'}: ${parsed.title} for ${MoneyUtils.formatAmount(parsed.amount)}.',
        );
        final updatedMessages = [...nextMessages, assistantMessage];
        await AiFinancialAssistantService.saveMessages(session.id, updatedMessages);
        if (mounted) {
          setState(() => _messages = updatedMessages);
        }
        return;
      }

      final actionResult =
          await AiFinancialAssistantService.detectFinancialAction(
            question: text,
            history: nextMessages,
          );
      if (actionResult.clarification != null) {
        final assistantMessage = AiFinancialAssistantService.assistantMessage(
          actionResult.clarification!,
        );
        final updatedMessages = [...nextMessages, assistantMessage];
        await AiFinancialAssistantService.saveMessages(
          session.id,
          updatedMessages,
        );
        if (mounted) {
          setState(() => _messages = updatedMessages);
        }
        return;
      }

      final action = actionResult.action;
      if (action != null) {
        if (!mounted) {
          return;
        }
        final confirmed = await _confirmFinancialAction(action);
        final response = confirmed
            ? await AiFinancialAssistantService.executeFinancialAction(action)
            : 'Cancelled bro. I did not change any records.';
        final assistantMessage = AiFinancialAssistantService.assistantMessage(
          response,
        );
        final updatedMessages = [...nextMessages, assistantMessage];
        await AiFinancialAssistantService.saveMessages(
          session.id,
          updatedMessages,
        );
        if (mounted) {
          setState(() => _messages = updatedMessages);
        }
        return;
      }

      final answer = await AiFinancialAssistantService.ask(
        question: text,
        history: nextMessages,
      );
      final assistantMessage = AiFinancialAssistantService.assistantMessage(
        answer,
      );
      final updatedMessages = [...nextMessages, assistantMessage];
      await AiFinancialAssistantService.saveMessages(
        session.id,
        updatedMessages,
      );
      if (mounted) {
        setState(() => _messages = updatedMessages);
      }
    } catch (error) {
      final assistantMessage = AiFinancialAssistantService.assistantMessage(
        'I could not reach the AI service right now.\n\n${error.toString().replaceFirst('Exception: ', '')}',
      );
      final updatedMessages = [...nextMessages, assistantMessage];
      await AiFinancialAssistantService.saveMessages(
        session.id,
        updatedMessages,
      );
      if (mounted) {
        setState(() => _messages = updatedMessages);
      }
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

  Future<bool> _confirmFinancialAction(FinancialRecordAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _FinancialActionDialog(action: action);
      },
    );
    return confirmed == true;
  }

  Future<void> _newChat() async {
    final session = await AiFinancialAssistantService.createSession();
    if (mounted) {
      setState(() {
        _session = session;
        _messages = session.messages;
      });
    }
  }

  Future<void> _switchSession(AiChatSession session) async {
    await AiFinancialAssistantService.setActiveSession(session.id);
    final freshSession = await AiFinancialAssistantService.getSession(
      session.id,
    );
    if (!mounted || freshSession == null) {
      return;
    }
    setState(() {
      _session = freshSession;
      _messages = freshSession.messages;
    });
    _scrollToBottom();
  }

  Future<void> _deleteSession(AiChatSession session) async {
    await AiFinancialAssistantService.deleteSession(session.id);
    final activeId = await AiFinancialAssistantService.getActiveSessionId();
    final activeSession = activeId == null
        ? null
        : await AiFinancialAssistantService.getSession(activeId);
    if (!mounted) {
      return;
    }
    if (activeSession != null) {
      setState(() {
        _session = activeSession;
        _messages = activeSession.messages;
      });
    } else {
      final newSession = await AiFinancialAssistantService.createSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = newSession;
        _messages = newSession.messages;
      });
    }
  }

  Future<void> _showChatHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
      if (!_scrollController.hasClients) {
        return;
      }
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
  final VoidCallback onHistory;
  final VoidCallback onNewChat;

  const _AssistantHeader({
    required this.session,
    required this.onHistory,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.smart_toy_rounded, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Financial Assistant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 21,
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: FutureBuilder<List<AiChatSession>>(
          future: AiFinancialAssistantService.getSessions(),
          builder: (context, snapshot) {
            final sessions = snapshot.data ?? const [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.36,
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sessions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = session.id == activeSessionId;
                      return Material(
                        color: isActive
                            ? colorScheme.primary.withValues(alpha: 0.10)
                            : colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            
                            
                            
                            color: isActive
                                ? colorScheme.primary
                                : colorScheme.outline,
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
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${session.messages.length} message${session.messages.length == 1 ? '' : 's'} • ${_dateLabel(session.updatedAt)}',
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
    return AlertDialog(
      title: Row(
        children: [
          Icon(_iconForAction(), color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('${_actionLabel()} transaction?')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailRow(label: 'Action', value: _actionLabel()),
            const SizedBox(height: 10),
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
          child: const Text('Confirm'),
        ),
      ],
    );
  }

  String _actionLabel() {
    return switch (action.type) {
      FinancialActionType.add => 'Add',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailRow(
          label: 'Type',
          value: record.isExpense ? 'Expense' : 'Income',
        ),
        _DetailRow(label: 'Title / Note', value: record.title),
        _DetailRow(
          label: 'Amount',
          value: MoneyUtils.formatAmount(record.amount),
        ),
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
    final changes = <Widget>[
      _ChangeRow(
        label: 'Type',
        oldValue: oldRecord.isExpense ? 'Expense' : 'Income',
        newValue: newRecord.isExpense ? 'Expense' : 'Income',
      ),
      _ChangeRow(
        label: 'Title / Note',
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
    ].whereType<_ChangeRow>().where((row) => row.hasChanged).toList();

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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(oldValue, style: TextStyle(color: colorScheme.error)),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(
                Icons.arrow_downward_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  newValue,
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
  final ValueChanged<String> onPrompt;

  const _EmptyAssistantState({required this.onPrompt});

  @override
  Widget build(BuildContext context) {
    final prompts = [
      'Where am I spending most?',
      'How can I save money this month?',
      'Can I afford a bike in 6 months?',
      'Create a weekly spending report.',
    ];
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 140),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, color: colorScheme.onPrimary),
              const SizedBox(height: 12),
              Text(
                'Ask anything about your money.',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Each chat keeps its own memory, so follow-up questions make sense.',
                style: TextStyle(
                  color: colorScheme.onPrimary.withValues(alpha: 0.82),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final prompt in prompts) ...[
          _PromptTile(prompt: prompt, onTap: () => onPrompt(prompt)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PromptTile extends StatelessWidget {
  final String prompt;
  final VoidCallback onTap;

  const _PromptTile({required this.prompt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.bolt_rounded),
        title: Text(prompt),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final AiChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
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
                ),
              ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const SizedBox(
          width: 46,
          child: LinearProgressIndicator(minHeight: 3),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/components/app_widgets.dart';
import '../../../core/models/bill_reminder.dart';
import '../../../core/services/ocr_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_utils.dart';
import '../../../services/bill_reminder_service.dart';
import '../../../services/user_settings_service.dart';

class BillReminderScreen extends StatefulWidget {
  const BillReminderScreen({super.key});

  @override
  State<BillReminderScreen> createState() => _BillReminderScreenState();
}

class _BillReminderScreenState extends State<BillReminderScreen> {
  @override
  void initState() {
    super.initState();
    BillReminderService.rescheduleAll();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Reminder'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openReminderSheet(),
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Add Bill'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<BillReminder>>(
          stream: UserSettingsService.billRemindersStream(),
          builder: (context, snapshot) {
            final reminders = snapshot.data ?? <BillReminder>[];

            return ListView(
              padding: EdgeInsets.fromLTRB(
                AppTokens.pageGutter,
                AppTokens.gapMd,
                AppTokens.pageGutter,
                // Room for the extended FAB plus the gesture inset.
                96 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppTokens.gapLg),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colorScheme.appHeroGradient,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: colorScheme.appOnHero.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: colorScheme.appOnHero,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI bill alerts',
                              style: TextStyle(
                                color: colorScheme.appOnHero,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Get reminders for electricity, internet, rent, EMI and other payments.',
                              style: TextStyle(
                                color: colorScheme.appOnHero.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (reminders.isEmpty)
                  _EmptyReminderState(onAdd: () => _openReminderSheet())
                else
                  ...reminders.map(
                    (reminder) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReminderTile(
                        reminder: reminder,
                        onEdit: () => _openReminderSheet(reminder: reminder),
                        onDelete: () => _deleteReminder(reminder),
                        onEnabledChanged: (value) => _toggleReminder(
                          reminder,
                          value,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openReminderSheet({BillReminder? reminder}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ReminderFormSheet(reminder: reminder),
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill reminder saved')),
      );
    }
  }

  Future<void> _toggleReminder(BillReminder reminder, bool enabled) async {
    await UserSettingsService.saveBillReminder(reminder.copyWith(enabled: enabled));
  }

  Future<void> _deleteReminder(BillReminder reminder) async {
    await UserSettingsService.deleteBillReminder(reminder.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${reminder.title} reminder deleted')),
      );
    }
  }
}

class _ReminderFormSheet extends StatefulWidget {
  final BillReminder? reminder;

  const _ReminderFormSheet({this.reminder});

  @override
  State<_ReminderFormSheet> createState() => _ReminderFormSheetState();
}

class _ReminderFormSheetState extends State<_ReminderFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));
  int _remindDaysBefore = 1;
  bool _enabled = true;
  bool _saving = false;
  bool _isScanning = false;

  static const _quickBills = ['Electricity bill', 'Internet bill', 'Rent', 'EMI'];

  final OcrService _ocrService = OcrService();

  Future<void> _scanReceipt(ImageSource source) async {
    setState(() => _isScanning = true);
    try {
      final imageFile = await _ocrService.pickImage(source);
      if (imageFile == null) return;

      final result = await _ocrService.scanBill(imageFile);

      if (!mounted) return;

      if (result.title != null && result.title!.isNotEmpty) {
        _titleController.text = result.title!;
      }
      if (result.amount != null && result.amount! > 0) {
        _amountController.text = result.amount!.toStringAsFixed(2);
      }
      if (result.date != null) {
        setState(() => _dueDate = result.date!);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.title != null || result.amount != null
                ? 'Bill details auto-filled from scan!'
                : 'Scanned text, but could not detect exact fields.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to scan image: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showScanSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _scanReceipt(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _scanReceipt(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final reminder = widget.reminder;
    if (reminder != null) {
      _titleController.text = reminder.title;
      _amountController.text =
          reminder.amount > 0 ? reminder.amount.toStringAsFixed(2) : '';
      _notesController.text = reminder.notes;
      _dueDate = reminder.dueDate;
      _remindDaysBefore = reminder.remindDaysBefore;
      _enabled = reminder.enabled;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.gapLg,
        right: AppTokens.gapLg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.gapXl,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title and the Scan button used to sit in a plain Row, so
              // "Edit Bill Reminder" plus a scanning label overflowed on
              // narrow screens and at larger text scales.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.reminder == null
                          ? 'Add Bill Reminder'
                          : 'Edit Bill Reminder',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.gapSm),
                  Flexible(
                    child: OutlinedButton.icon(
                      onPressed: _isScanning ? null : _showScanSourceDialog,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.document_scanner_rounded, size: 18),
                      label: Text(
                        _isScanning ? 'Scanning...' : 'Scan Bill',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gapLg),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickBills.map((bill) {
                  return ActionChip(
                    avatar: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: Text(bill),
                    onPressed: () => _titleController.text = bill,
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Bill name',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter bill name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                ),
              ),
              const SizedBox(height: 12),
              _PickerTile(
                icon: Icons.event_rounded,
                title: 'Due date',
                value: _formatDate(_dueDate),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _remindDaysBefore,
                decoration: const InputDecoration(
                  labelText: 'Remind me',
                  prefixIcon: Icon(Icons.notifications_active_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('On due date')),
                  DropdownMenuItem(value: 1, child: Text('1 day before')),
                  DropdownMenuItem(value: 2, child: Text('2 days before')),
                  DropdownMenuItem(value: 3, child: Text('3 days before')),
                  DropdownMenuItem(value: 7, child: Text('1 week before')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _remindDaysBefore = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable reminder alerts'),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: Icon(_saving ? Icons.hourglass_top_rounded : Icons.save_rounded),
                label: Text(_saving ? 'Saving...' : 'Save Reminder'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    final reminder = BillReminder(
      id: widget.reminder?.id ?? const Uuid().v4(),
      title: _titleController.text.trim(),
      amount: double.tryParse(_amountController.text.trim()) ?? 0,
      dueDate: _dueDate,
      enabled: _enabled,
      remindDaysBefore: _remindDaysBefore,
      notes: _notesController.text.trim(),
    );

    await BillReminderService.saveReminder(reminder);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class _ReminderTile extends StatelessWidget {
  final BillReminder reminder;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;

  const _ReminderTile({
    required this.reminder,
    required this.onEdit,
    required this.onDelete,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final daysLeft = reminder.dueDate.difference(DateTime.now()).inDays + 1;
    final statusColor = daysLeft <= 0
        ? colorScheme.appExpense
        : daysLeft <= 2
        ? colorScheme.appWarning
        : colorScheme.onSurfaceVariant;

    return Material(
      color: colorScheme.appCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        // A ListTile could not hold a Switch and a delete button plus the
        // status line without crowding the title, so this lays out explicitly.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gapMd,
            AppTokens.gapMd,
            AppTokens.gapSm,
            AppTokens.gapMd,
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
                  Icons.receipt_long_rounded,
                  color: colorScheme.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: AppTokens.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reminder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatStatus(daysLeft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_formatDate(reminder.dueDate)}'
                      '${reminder.amount > 0 ? ' • ${MoneyUtils.formatAmount(reminder.amount)}' : ''}',
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
              const SizedBox(width: AppTokens.gapSm),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: reminder.enabled,
                    onChanged: onEnabledChanged,
                  ),
                  IconButton(
                    tooltip: 'Delete reminder',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatStatus(int daysLeft) {
    if (daysLeft < 0) {
      return 'Overdue';
    }
    if (daysLeft == 0) {
      return 'Due today';
    }
    if (daysLeft == 1) {
      return 'Due tomorrow';
    }
    return 'Due in $daysLeft days';
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.appCardMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: colorScheme.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: colorScheme.onSurfaceVariant),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _EmptyReminderState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyReminderState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: Icons.notifications_active_outlined,
      title: 'No bill reminders yet',
      message:
          'Add your monthly bills and Smart Expense will alert you before '
          'they are due.',
      actionLabel: 'Add first bill',
      onAction: onAdd,
      margin: EdgeInsets.zero,
    );
  }
}

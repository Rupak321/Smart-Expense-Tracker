class BillReminder {
  final String id;
  final String title;
  final double amount;
  final DateTime dueDate;
  final bool enabled;
  final int remindDaysBefore;
  final String notes;

  const BillReminder({
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.enabled,
    required this.remindDaysBefore,
    required this.notes,
  });

  factory BillReminder.fromMap(Map<dynamic, dynamic> map) {
    return BillReminder(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Bill',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      dueDate: DateTime.tryParse(map['dueDate']?.toString() ?? '') ??
          DateTime.now(),
      enabled: map['enabled'] as bool? ?? true,
      remindDaysBefore: (map['remindDaysBefore'] as num?)?.toInt() ?? 1,
      notes: map['notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'dueDate': dueDate.toIso8601String(),
      'enabled': enabled,
      'remindDaysBefore': remindDaysBefore,
      'notes': notes,
    };
  }

  BillReminder copyWith({
    String? id,
    String? title,
    double? amount,
    DateTime? dueDate,
    bool? enabled,
    int? remindDaysBefore,
    String? notes,
  }) {
    return BillReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      enabled: enabled ?? this.enabled,
      remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
      notes: notes ?? this.notes,
    );
  }
}

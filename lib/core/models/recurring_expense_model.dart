import 'package:cloud_firestore/cloud_firestore.dart';

class RecurringExpenseModel {
  final String id;
  final String userId;
  final String title;
  final String category;
  final double amount;
  final String currency;
  final RecurringFrequency frequency;
  final int interval;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextDueDate;
  final DateTime? lastGeneratedDate;
  final RecurringStatus status;
  final bool reminderEnabled;
  final int reminderDaysBefore;
  final String notes;
  final String iconKey;
  final String colorHex;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RecurringExpenseModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    required this.amount,
    required this.currency,
    required this.frequency,
    this.interval = 1,
    required this.startDate,
    this.endDate,
    required this.nextDueDate,
    this.lastGeneratedDate,
    this.status = RecurringStatus.active,
    this.reminderEnabled = true,
    this.reminderDaysBefore = 2,
    this.notes = '',
    this.iconKey = '',
    this.colorHex = '#4DB6AC',
    required this.createdAt,
    required this.updatedAt,
  });

  RecurringExpenseModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? category,
    double? amount,
    String? currency,
    RecurringFrequency? frequency,
    int? interval,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? nextDueDate,
    DateTime? lastGeneratedDate,
    RecurringStatus? status,
    bool? reminderEnabled,
    int? reminderDaysBefore,
    String? notes,
    String? iconKey,
    String? colorHex,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecurringExpenseModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      lastGeneratedDate: lastGeneratedDate ?? this.lastGeneratedDate,
      status: status ?? this.status,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
      notes: notes ?? this.notes,
      iconKey: iconKey ?? this.iconKey,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'category': category,
      'amount': amount,
      'currency': currency,
      'frequency': frequency.name,
      'interval': interval,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'nextDueDate': nextDueDate.toIso8601String(),
      'lastGeneratedDate': lastGeneratedDate?.toIso8601String(),
      'status': status.name,
      'reminderEnabled': reminderEnabled,
      'reminderDaysBefore': reminderDaysBefore,
      'notes': notes,
      'iconKey': iconKey,
      'colorHex': colorHex,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory RecurringExpenseModel.fromJson(
    String id,
    Map<String, dynamic> json,
  ) {
    DateTime readDate(dynamic value) {
      if (value == null) {
        return DateTime.now();
      }
      if (value is DateTime) {
        return value;
      }
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      if (value is Timestamp) {
        return value.toDate();
      }
      return DateTime.now();
    }

    return RecurringExpenseModel(
      id: id,
      userId: json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'custom',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency']?.toString() ?? 'NPR',
      frequency: RecurringFrequency.values.firstWhere(
        (value) => value.name == (json['frequency']?.toString() ?? 'monthly'),
        orElse: () => RecurringFrequency.monthly,
      ),
      interval: (json['interval'] as num?)?.toInt() ?? 1,
      startDate: readDate(json['startDate']),
      endDate: json['endDate'] == null ? null : readDate(json['endDate']),
      nextDueDate: readDate(json['nextDueDate']),
      lastGeneratedDate: json['lastGeneratedDate'] == null
          ? null
          : readDate(json['lastGeneratedDate']),
      status: RecurringStatus.values.firstWhere(
        (value) => value.name == (json['status']?.toString() ?? 'active'),
        orElse: () => RecurringStatus.active,
      ),
      reminderEnabled: json['reminderEnabled'] as bool? ?? true,
      reminderDaysBefore: (json['reminderDaysBefore'] as num?)?.toInt() ?? 2,
      notes: json['notes']?.toString() ?? '',
      iconKey: json['iconKey']?.toString() ?? '',
      colorHex: json['colorHex']?.toString() ?? '#4DB6AC',
      createdAt: readDate(json['createdAt']),
      updatedAt: readDate(json['updatedAt']),
    );
  }
}

enum RecurringFrequency { daily, weekly, monthly, yearly }
enum RecurringStatus { active, paused, ended }
